import AppKit
import Contacts
import SearchCore

enum SearchScope: String, CaseIterable {
    case all = "All", applications = "Apps", contacts = "Contacts"
    var kind: ItemKind? {
        switch self {
        case .all: return nil
        case .applications: return .application
        case .contacts: return .contact
        }
    }
}

enum ContactsState: Equatable {
    case notRequested, loading, ready(Int), denied, restricted, failed(String)
}

@MainActor
final class SearchModel: ObservableObject {
    @Published private(set) var input = LauncherInput()
    var query: String {
        get { input.text }
        set { input.edit(newValue); updateResults() }
    }
    var isChat: Bool { input.isChat }
    var showsResults: Bool { hasQuery && !isChat }
    @Published private(set) var openingChat = false
    @Published var scope: SearchScope = .all { didSet { updateResults() } }
    @Published private(set) var results: [SearchItem] = []
    @Published var selectedID: String?
    @Published var detail: SearchItem?
    @Published var contactsState: ContactsState = .notRequested
    @Published var indexing = false
    @Published var error: String?
    @Published var shortcutAvailable = true
    @Published var copiedField: String?
    @Published private(set) var appCount = 0
    var dismiss: (() -> Void)?
    var presentationChanged: (() -> Void)?
    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var expandedPanelHeight: CGFloat = 556
    var panelHeight: CGFloat { isChat ? (error == nil ? 112 : 150) : hasQuery ? expandedPanelHeight : 76 }
    private var applications: [SearchItem] = []
    private var contacts: [SearchItem] = []
    private var recents = UserDefaults.standard.stringArray(forKey: "recentApplications") ?? []
    private var contactObserver: NSObjectProtocol?
    private var contactsGeneration = 0

    init() {
        contactObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshContacts() }
        }
    }

    func refresh() async {
        async let apps: () = refreshApplications()
        await refreshContacts()
        await apps
    }

    func refreshApplications() async {
        guard !indexing else { return }
        indexing = true
        applications = await Task.detached(priority: .userInitiated) {
            ApplicationIndex.scan()
        }.value
        appCount = applications.count
        indexing = false
        updateResults(preserveSelection: true)
    }

    func enableContacts() async {
        contactsState = .loading
        do {
            _ = try await CNContactStore().requestAccess(for: .contacts)
            await refreshContacts()
        } catch {
            contactsState = .failed("Contacts access could not be requested. Try again or check System Settings.")
        }
    }

    func refreshContacts() async {
        contactsGeneration += 1
        let generation = contactsGeneration
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            contacts = []
            contactsState = .notRequested
            updateResults(preserveSelection: true)
            return
        }
        if status == .denied || status == .restricted {
            contacts = []
            detail = nil
            contactsState = status == .denied ? .denied : .restricted
            updateResults(preserveSelection: true)
            return
        }
        contactsState = .loading
        let loaded = await Task.detached(priority: .userInitiated) { () -> Result<[SearchItem], Error> in
            Result { try ContactIndex.scan() }
        }.value
        guard generation == contactsGeneration else { return }
        switch loaded {
        case .success(let items):
            contacts = items
            contactsState = .ready(items.count)
            if let current = detail { detail = items.first { $0.id == current.id } }
        case .failure:
            contacts = []
            detail = nil
            contactsState = .failed("Couldn’t read contacts. Check access in System Settings, then retry.")
        }
        updateResults(preserveSelection: true)
    }

    func updateResults(preserveSelection: Bool = false) {
        results = showsResults ? SearchEngine.search(applications + contacts, query: query, kind: scope.kind,
                                                recents: recents, limit: 40) : []
        if !preserveSelection || !results.contains(where: { $0.id == selectedID }) {
            selectedID = results.first?.id
        }
        if !preserveSelection {
            detail = nil
            error = nil
        }
        presentationChanged?()
    }

    func moveSelection(_ delta: Int) {
        guard detail == nil, !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(index + delta, 0), results.count - 1)].id
    }

    func activateSelection() {
        if isChat { openCodex(); return }
        guard detail == nil, let item = results.first(where: { $0.id == selectedID }) else { return }
        activate(item)
    }

    func resetSearch() {
        input.reset()
        scope = .all
        updateResults()
    }

    func escape() {
        if detail != nil {
            detail = nil
        } else if isChat {
            input.exitChat()
            updateResults()
        } else {
            dismiss?()
        }
    }

    private func openCodex() {
        guard !openingChat, hasQuery else { return }
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let candidates = [URL(fileURLWithPath: "/Applications/Ghostty.app"),
            home.appendingPathComponent("Applications/Ghostty.app")]
        let app = candidates.first { Bundle(url: $0)?.bundleIdentifier == "com.mitchellh.ghostty" }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")
        guard let app else {
            error = "Install Ghostty in Applications, then try again."
            presentationChanged?()
            return
        }
        let paths = [home.appendingPathComponent(".npm-global/bin/codex").path,
                     home.appendingPathComponent(".local/bin/codex").path,
                     "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let executable = paths.first(where: { manager.isExecutableFile(atPath: $0) }) else {
            error = "Codex CLI wasn’t found. Install it in ~/.npm-global/bin, ~/.local/bin, or with Homebrew."
            presentationChanged?()
            return
        }
        let directory = home
        guard let arguments = CodexLaunch.arguments(prompt: query, executable: executable, directory: directory.path) else {
            error = "The question contains an unsupported null character. Remove it and try again."
            presentationChanged?()
            return
        }
        openingChat = true
        let submittedPrompt = query
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { [weak self] _, openError in
            Task { @MainActor in
                guard let self else { return }
                self.openingChat = false
                guard self.isChat, self.query == submittedPrompt else { return }
                if openError != nil {
                    self.error = "Couldn’t open Ghostty. Open it once from Applications, then try again."
                    self.presentationChanged?()
                } else {
                    self.dismiss?()
                }
            }
        }
    }

    func activate(_ item: SearchItem) {
        selectedID = item.id
        if item.kind == .contact {
            copiedField = nil
            detail = item
            return
        }
        guard let path = item.path else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) {
            [weak self] _, launchError in
            Task { @MainActor in
                guard let self else { return }
                if launchError != nil {
                    self.error = "Couldn’t open \(item.title). It may have moved. Refresh from the menu bar and try again."
                } else {
                    self.recents.removeAll { $0 == item.id }
                    self.recents.insert(item.id, at: 0)
                    self.recents = Array(self.recents.prefix(20))
                    UserDefaults.standard.set(self.recents, forKey: "recentApplications")
                    self.dismiss?()
                }
            }
        }
    }

    func openInContacts(_ item: SearchItem) {
        guard item.kind == .contact, item.id.hasPrefix("contact:") else { return }
        let identifier = String(item.id.dropFirst("contact:".count))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-:._~"))
        guard !identifier.isEmpty,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "addressbook://" + encoded),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.AddressBook") else {
            error = "Couldn’t open this contact in Contacts."
            return
        }
        error = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) {
            [weak self] _, launchError in
            Task { @MainActor in
                guard let self, self.detail?.id == item.id else { return }
                if launchError != nil {
                    self.error = "Couldn’t open this contact in Contacts. Try again."
                } else {
                    self.dismiss?()
                }
            }
        }
    }

    func copy(_ field: ContactField) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(field.value, forType: .string)
        copiedField = field.id
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum ApplicationIndex {
    static func scan() -> [SearchItem] {
        let manager = FileManager.default
        let roots = [manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
                     "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
                     "/System/Cryptexes/App/System/Applications"]
        var seen = Set<String>()
        var items: [SearchItem] = []
        for root in roots {
            guard let enumerator = manager.enumerator(at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let resolved = url.resolvingSymlinksInPath()
                guard let bundle = Bundle(url: resolved) else { continue }
                let identifier = bundle.bundleIdentifier ?? resolved.path
                guard identifier != "ai.toyo.ironsearch", seen.insert(identifier).inserted else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? resolved.deletingPathExtension().lastPathComponent
                items.append(SearchItem(id: "app:" + identifier, title: name,
                    subtitle: resolved.deletingLastPathComponent().path.replacingOccurrences(
                        of: manager.homeDirectoryForCurrentUser.path, with: "~"),
                    kind: .application, path: resolved.path))
            }
        }
        // Finder lives outside the Applications directories; Safari's hidden
        // /Applications symlink is covered by the Cryptex directory above.
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if let bundle = Bundle(url: finder), let identifier = bundle.bundleIdentifier,
           seen.insert(identifier).inserted {
            items.append(SearchItem(id: "app:" + identifier, title: "Finder", subtitle: "macOS",
                                    kind: .application, path: finder.path))
        }
        return items
    }
}

enum ContactIndex {
    static func scan() throws -> [SearchItem] {
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        var items: [SearchItem] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            let emails = contact.emailAddresses.map {
                ContactField(label: label("Email", $0.label), value: $0.value as String)
            }
            let phones = contact.phoneNumbers.map {
                ContactField(label: label("Phone", $0.label), value: $0.value.stringValue)
            }
            let addresses = contact.postalAddresses.compactMap { address -> ContactField? in
                let value = CNPostalAddressFormatter.string(from: address.value, style: .mailingAddress)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                return ContactField(label: label("Address", address.label), value: value)
            }
            let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let title = !formatted.isEmpty ? formatted : (!contact.organizationName.isEmpty
                ? contact.organizationName : emails.first?.value ?? phones.first?.value ?? "Unnamed contact")
            let subtitle = !contact.organizationName.isEmpty && contact.organizationName != title
                ? contact.organizationName : emails.first?.value ?? phones.first?.value ?? "Contact"
            // Duplicate labelled values occur in linked cards; keep SwiftUI IDs unique.
            var seen = Set<String>()
            var fields = (emails + phones + addresses).filter { seen.insert($0.id).inserted }
            if !contact.organizationName.isEmpty {
                fields.insert(ContactField(label: "Company", value: contact.organizationName), at: 0)
            }
            items.append(SearchItem(id: "contact:" + contact.identifier, title: title,
                                    subtitle: subtitle, kind: .contact, fields: fields))
        }
        return items
    }

    private static func label(_ type: String, _ label: String?) -> String {
        guard let label else { return type }
        return type + " · " + CNLabeledValue<NSString>.localizedString(forLabel: label)
    }
}

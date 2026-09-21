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
    @Published var query = "" { didSet { updateResults() } }
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
        results = SearchEngine.search(applications + contacts, query: query, kind: scope.kind,
                                      recents: recents, limit: query.isEmpty ? 8 : 40)
        if !preserveSelection || !results.contains(where: { $0.id == selectedID }) {
            selectedID = results.first?.id
        }
        if !preserveSelection {
            detail = nil
            error = nil
        }
    }

    func moveSelection(_ delta: Int) {
        guard detail == nil, !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(index + delta, 0), results.count - 1)].id
    }

    func activateSelection() {
        guard detail == nil, let item = results.first(where: { $0.id == selectedID }) else { return }
        activate(item)
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
            CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
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
            let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let title = !formatted.isEmpty ? formatted : (!contact.organizationName.isEmpty
                ? contact.organizationName : emails.first?.value ?? phones.first?.value ?? "Unnamed contact")
            let subtitle = !contact.organizationName.isEmpty && contact.organizationName != title
                ? contact.organizationName : emails.first?.value ?? phones.first?.value ?? "Contact"
            // Duplicate labelled values occur in linked cards; keep SwiftUI IDs unique.
            var seen = Set<String>()
            var fields = (emails + phones).filter { seen.insert($0.id).inserted }
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

import AppKit
import SwiftUI
import SearchCore

// Explicitly select the property wrapper: the macOS 27 beta SDK also exports a
// same-named macro whose plugin is absent from standalone Command Line Tools.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SearchView: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if model.isChat {
                    Text("Codex")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                        .accessibilityLabel("Codex mode")
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 23, weight: .medium)).foregroundStyle(.secondary)
                }
                SearchField(text: $model.query, enabled: model.detail == nil,
                    placeholder: model.isChat ? "Ask Codex…" : "Search apps and contacts",
                    onMove: model.moveSelection, onSubmit: model.activateSelection,
                    onEscape: escape)
                    .frame(height: 42)
                if model.isChat {
                    Button(action: model.activateSelection) {
                        Image(systemName: "arrow.up.right").frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.hasQuery || model.openingChat)
                    .help("Start Codex in Ghostty with full access")
                    .accessibilityLabel("Start Codex in Ghostty with full access")
                }
                Button(action: escape) { KeyCap(text: "esc") }
                    .buttonStyle(.plain).frame(width: 40, height: 40)
                    .help(model.isChat ? "Exit Codex mode" : model.detail == nil ? "Close search" : "Back to results")
                    .accessibilityLabel(model.isChat ? "Exit Codex mode" : model.detail == nil ? "Close search" : "Back to results")
            }
            .padding(.horizontal, 24).padding(.vertical, 17)
            if model.isChat {
                HStack {
                    Text(model.openingChat ? "Opening Ghostty…" : "↵ Ask in Ghostty · Codex full access (--yolo)")
                    Spacer()
                    Text("esc Back to search")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 24).frame(height: 36)
                if let error = model.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                        .padding(.horizontal, 24).frame(height: 38)
                }
            } else if model.showsResults { expandedContent }
        }
        .frame(width: 740, height: model.panelHeight, alignment: .top)
        // Clip the full layout to the animating window, revealing it downward
        // without moving the search field or squeezing the result rows.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    @ViewBuilder private var expandedContent: some View {
            Divider().opacity(0.5)

            if let contact = model.detail {
                contactDetail(contact)
            } else {
                HStack(spacing: 6) {
                    Picker("Search in", selection: $model.scope) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240, height: 40)
                    .help("All: ⌥⌘0 · Apps: ⌥⌘1 · Contacts: ⌥⌘2")
                    Spacer()
                    if model.indexing { ProgressView().controlSize(.small) }
                    Text("\(model.results.count) results")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.horizontal, 16).padding(.vertical, 8)

                if model.scope != .applications { contactsNotice }

                if model.results.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(model.results) { item in
                                    ResultRow(item: item, selected: model.selectedID == item.id) {
                                        model.activate(item)
                                    }.id(item.id)
                                }
                            }.padding(.horizontal, 12).padding(.bottom, 10)
                        }
                        .onChange(of: model.selectedID) { _, id in
                            if let id { proxy.scrollTo(id, anchor: nil) }
                        }
                    }
                }
            }
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .padding(.horizontal, 24).padding(.vertical, 8)
            }
            Divider().opacity(0.5)
            footer
    }

    private func escape() {
        model.escape()
    }

    @ViewBuilder private var contactsNotice: some View {
        switch model.contactsState {
        case .notRequested:
            notice("Your people, a few keystrokes away.", button: "Enable contacts") {
                Task { await model.enableContacts() }
            }
        case .denied:
            notice("Allow Contacts access in System Settings.", button: "Open settings") {
                model.openPrivacySettings()
            }
        case .restricted:
            notice("Contacts access is restricted on this Mac.", button: nil, action: {})
        case .failed(let message):
            notice(message, button: "Retry") { Task { await model.refreshContacts() } }
        case .loading:
            notice("Loading contacts…", button: nil, action: {})
        case .ready(let count):
            if count == 0 && model.scope == .contacts {
                notice("No accessible contacts. Add contacts or check access in Settings.",
                       button: "Open settings", action: model.openPrivacySettings)
            }
        }
    }

    private func notice(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let button {
                Button(button, action: action).buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .frame(minHeight: 40)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16).padding(.bottom, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: model.indexing ? "square.grid.2x2" : "magnifyingglass")
                .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(model.indexing ? "Finding your applications…" : model.query.isEmpty ? "Find your people" : "No matches")
                .font(.system(size: 17, weight: .medium))
            Text(model.query.isEmpty ? "Search by name, company, email, or phone." : "Try a shorter name or a different spelling.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contactDetail(_ contact: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { model.detail = nil } label: {
                    Label("Results", systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                        .frame(minHeight: 40)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button { model.openInContacts(contact) } label: {
                    Label("Open in Contacts", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium)).frame(minHeight: 40)
                }.buttonStyle(.plain)
                    .help("Open this person’s card in Apple Contacts")
            }
            HStack(spacing: 16) {
                ContactAvatar(name: contact.title, size: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(contact.title).font(.system(size: 24, weight: .semibold)).textSelection(.enabled)
                    Text("CONTACT").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.5).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if contact.fields.isEmpty {
                        Text("No email address, phone number, postal address, or company on this contact.")
                            .foregroundStyle(.secondary).font(.system(size: 13)).padding(.vertical, 20)
                    }
                    ForEach(contact.fields) { field in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label).font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(field.value).font(.system(size: 14)).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button { model.copy(field) } label: {
                                Image(systemName: model.copiedField == field.id ? "checkmark" : "doc.on.doc")
                                    .frame(width: 40, height: 40)
                            }.buttonStyle(.plain)
                                .foregroundStyle(model.copiedField == field.id ? Color.green : Color.secondary)
                                .help("Copy \(field.label.lowercased())")
                                .accessibilityLabel("Copy \(field.label): \(field.value)")
                        }.padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }.padding(.horizontal, 24).padding(.bottom, 16).frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Iron Search").font(.system(size: 11))
            KeyCap(text: "⌘Space")
            if !model.shortcutAvailable {
                Text("· Shortcut in use; use menu bar").font(.system(size: 10)).foregroundStyle(.orange)
            }
            Spacer()
            if model.detail == nil {
                KeyCap(text: "↑"); KeyCap(text: "↓")
                Text("navigate").padding(.trailing, 10)
                KeyCap(text: "↵")
                Text(model.results.first(where: { $0.id == model.selectedID })?.kind == .contact ? "view contact" : "open app")
            } else {
                Text("Details stay on your Mac")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 24).frame(height: 44)
    }
}

private struct ResultRow: View {
    let item: SearchItem
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovered = false
    @ViewState private var icon: NSImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                if item.kind == .application {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.fill").resizable().foregroundStyle(.secondary) }
                    }.frame(width: 36, height: 36)
                } else { ContactAvatar(name: item.title, size: 36) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 10)
                Text(item.kind == .application ? "Application" : "Contact")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                Image(systemName: selected ? "return" : "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 18).opacity(selected || hovered ? 1 : 0)
            }
            .padding(.horizontal, 12).frame(height: 57)
            .background(selected ? Color.accentColor.opacity(0.13) : hovered ? Color.primary.opacity(0.045) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(item.title), \(item.kind.rawValue), \(item.subtitle)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onAppear {
            if icon == nil, let path = item.path { icon = NSWorkspace.shared.icon(forFile: path) }
        }
    }
}

private struct ContactAvatar: View {
    let name: String
    let size: CGFloat
    var body: some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.system(size: size * 0.34, weight: .medium, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5).frame(height: 19)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 4))
    }
}

// An AppKit field preserves native editing, IME, and reliable first-responder behavior.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 30, weight: .regular)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.string = text
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        let becameEnabled = enabled && !context.coordinator.wasEnabled
        context.coordinator.wasEnabled = enabled
        field.isEnabled = enabled
        if becameEnabled, field.window?.isKeyWindow == true, field.currentEditor() == nil {
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isEnabled else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var wasEnabled = true
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let entered = field.stringValue
            parent.text = entered
            // Consume the alias synchronously, before another keystroke arrives.
            // Waiting for SwiftUI's render can leave "ask " in a fast-typed prompt.
            let canonical = parent.text
            if canonical != entered {
                field.stringValue = canonical
                if let editor = field.currentEditor() {
                    editor.string = canonical
                    editor.selectedRange = NSRange(location: (canonical as NSString).length, length: 0)
                }
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onEscape()
            default: return false
            }
            return true
        }
    }
}

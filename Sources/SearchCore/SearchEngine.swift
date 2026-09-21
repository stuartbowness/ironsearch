import Foundation

public enum ItemKind: String, Sendable, CaseIterable {
    case application, contact
}

public struct ContactField: Identifiable, Sendable, Equatable {
    public var id: String { label + ":" + value }
    public let label: String
    public let value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct SearchItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: ItemKind
    public let path: String?
    public let fields: [ContactField]
    let name: String
    let terms: String
    let initials: String
    let phoneNumbers: [String]

    public init(id: String, title: String, subtitle: String, kind: ItemKind,
                path: String? = nil, fields: [ContactField] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.path = path
        self.fields = fields
        self.name = SearchEngine.normalize(title)
        self.terms = SearchEngine.normalize(([title, subtitle] + fields.map(\.value)).joined(separator: " "))
        self.initials = SearchEngine.normalize(title).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first).map(String.init).joined()
        self.phoneNumbers = fields.filter { $0.label.hasPrefix("Phone") }
            .map { $0.value.filter(\.isNumber) }
    }
}

public enum SearchEngine {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    public static func search(_ items: [SearchItem], query: String, kind: ItemKind? = nil,
                              recents: [String] = [], limit: Int = 40) -> [SearchItem] {
        let query = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.compactMap { item -> (SearchItem, Int)? in
            guard kind == nil || item.kind == kind else { return nil }
            let recentBoost = recents.firstIndex(of: item.id).map { max(0, 20 - $0) } ?? 0
            if query.isEmpty { return (item, recentBoost) }
            if item.name == query { return (item, 1000 + recentBoost) }
            if item.name.hasPrefix(query) { return (item, 800 + recentBoost) }
            if item.initials == query { return (item, 700 + recentBoost) }
            if item.name.contains(query) { return (item, 600 + recentBoost) }
            if tokens.allSatisfy({ item.terms.contains($0) }) { return (item, 400 + recentBoost) }
            let digits = query.filter(\.isNumber)
            if digits.count >= 3, query.allSatisfy({ $0.isNumber || "+()- .".contains($0) }),
               item.phoneNumbers.contains(where: { $0.contains(digits) }) {
                return (item, 400 + recentBoost)
            }
            // A short subsequence supports abbreviations without matching every single letter.
            guard query.count >= 2, !query.contains(" ") else { return nil }
            var remaining = query[...]
            for char in item.name where char == remaining.first {
                remaining = remaining.dropFirst()
                if remaining.isEmpty { return (item, 100 + recentBoost) }
            }
            return nil
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            let order = lhs.0.title.localizedStandardCompare(rhs.0.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.0.id < rhs.0.id
        }.prefix(max(0, limit)).map(\.0)
    }
}

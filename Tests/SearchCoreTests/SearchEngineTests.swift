import Foundation
import SearchCore

@main
struct SearchEngineTests {
    static func main() {
        let suite = SearchEngineTests()
        suite.testExactBeforePrefixBeforeFuzzyRegardlessOfRecents()
        suite.testCaseAndDiacritics()
        suite.testInitialsAndAbbreviations()
        suite.testContactFieldsAndUnorderedTerms()
        suite.testScopeExcludesOtherType()
        suite.testRecentsRankEmptyQueryAndLimitIsHonoured()
        suite.testNoMatchesAndEmptyIndex()
        print("PASS: 7 search behavior checks (16 assertions)")
    }

    private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, _ context: String = "",
                                             file: StaticString = #file, line: UInt = #line) {
        guard actual == expected else {
            fatalError("\(context): expected \(expected), got \(actual)", file: file, line: line)
        }
    }
    private func XCTAssertTrue(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError("Expected true", file: file, line: line) }
    }
    private let items = [
        SearchItem(id: "safari", title: "Safari", subtitle: "/Applications", kind: .application),
        SearchItem(id: "safari-tools", title: "Safari Tools", subtitle: "/Applications", kind: .application),
        SearchItem(id: "code", title: "Visual Studio Code", subtitle: "/Applications", kind: .application),
        SearchItem(id: "jose", title: "José Tremblay", subtitle: "Toyo", kind: .contact,
                   fields: [ContactField(label: "Email · work", value: "jose@example.com"),
                            ContactField(label: "Phone · mobile", value: "+1 (250) 555-0123")]),
        SearchItem(id: "sarah", title: "Sarah Chen", subtitle: "Example", kind: .contact)
    ]

    func testExactBeforePrefixBeforeFuzzyRegardlessOfRecents() {
        XCTAssertEqual(SearchEngine.search(items, query: "safari", recents: ["safari-tools"]).map(\.id),
                       ["safari", "safari-tools"])
    }
    func testCaseAndDiacritics() {
        XCTAssertEqual(SearchEngine.search(items, query: "  JOSE  ").first?.id, "jose")
    }
    func testInitialsAndAbbreviations() {
        XCTAssertEqual(SearchEngine.search(items, query: "vsc").first?.id, "code")
        XCTAssertEqual(SearchEngine.search(items, query: "sfri").first?.id, "safari")
    }
    func testContactFieldsAndUnorderedTerms() {
        for query in ["example.com", "Toyo José", "Tremblay Jose", "250555", "(250) 555-0123"] {
            XCTAssertEqual(SearchEngine.search(items, query: query).first?.id, "jose", query)
        }
    }
    func testScopeExcludesOtherType() {
        XCTAssertTrue(SearchEngine.search(items, query: "jose", kind: .application).isEmpty)
        XCTAssertTrue(SearchEngine.search(items, query: "safari", kind: .contact).isEmpty)
        XCTAssertEqual(SearchEngine.search(items, query: "", kind: .contact).count, 2)
    }
    func testRecentsRankEmptyQueryAndLimitIsHonoured() {
        XCTAssertEqual(SearchEngine.search(items, query: " ", recents: ["code"], limit: 1).map(\.id), ["code"])
        XCTAssertTrue(SearchEngine.search(items, query: "", limit: 0).isEmpty)
    }
    func testNoMatchesAndEmptyIndex() {
        XCTAssertTrue(SearchEngine.search(items, query: "zzzzzz").isEmpty)
        XCTAssertTrue(SearchEngine.search([], query: "safari").isEmpty)
    }
}

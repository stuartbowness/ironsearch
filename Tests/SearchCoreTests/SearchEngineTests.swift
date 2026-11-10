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
        suite.testChatTriggersRequireSpace()
        suite.testChatAliasesAndPastedPrompts()
        suite.testChatExitAndReset()
        suite.testCodexArgumentsAndEmptyPrompts()
        suite.testPromptRemainsLiteralThroughShell()
        print("PASS: 12 search and Codex behavior checks")
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

    func testChatTriggersRequireSpace() {
        for text in ["a", "as", "ask", "Asana", "Ashley", "asking", "ask@example.com", "task list"] {
            var input = LauncherInput()
            input.edit(text)
            XCTAssertTrue(!input.isChat)
            XCTAssertEqual(input.text, text)
        }
    }

    func testChatAliasesAndPastedPrompts() {
        for prefix in ["as ", "ask ", "AS ", "Ask "] {
            var input = LauncherInput()
            input.edit(prefix)
            XCTAssertTrue(input.isChat)
            XCTAssertEqual(input.text, "")
            input.edit("as a teacher, explain gravity")
            XCTAssertEqual(input.text, "as a teacher, explain gravity")
            input.edit("")
            XCTAssertTrue(input.isChat)
            input.reset()
            input.edit(prefix + "Explain gravity")
            XCTAssertTrue(input.isChat)
            XCTAssertEqual(input.text, "Explain gravity")
        }
    }

    func testChatExitAndReset() {
        var input = LauncherInput()
        input.edit("ask Asana")
        input.exitChat()
        XCTAssertTrue(!input.isChat)
        XCTAssertEqual(input.text, "Asana")
        input.edit("as question")
        input.reset()
        XCTAssertTrue(!input.isChat)
        XCTAssertEqual(input.text, "")
    }

    func testCodexArgumentsAndEmptyPrompts() {
        for prompt in [" \n\t", "bad\0prompt"] {
            XCTAssertTrue(CodexLaunch.arguments(prompt: prompt, executable: "/bin/codex", directory: "/tmp") == nil)
        }
        let prompt = "--help C++ & Swift? # café 👋\n100% + x=1"
        let args = CodexLaunch.arguments(prompt: prompt, executable: "/path with spaces/codex", directory: "/working folder")!
        XCTAssertEqual(args.count, 7)
        XCTAssertTrue(args.contains("--window-save-state=never"))
        XCTAssertTrue(args.contains("--initial-window=true"))
        XCTAssertTrue(args.contains("--window-inherit-working-directory=false"))
        XCTAssertEqual(args[0], "--working-directory=/working folder")
        XCTAssertTrue(args[1].hasPrefix("--initial-command=shell:"))
        XCTAssertTrue(args[1].contains("'/path with spaces/codex' '--search' '--cd' '/working folder' '--'"))
        XCTAssertTrue(args.allSatisfy { $0.hasPrefix("--") && $0.contains("=") })
    }

    func testPromptRemainsLiteralThroughShell() {
        let prompt = "--help 'quoted' \"double\" $(echo EXPANDED) `echo EXPANDED` $HOME; echo WRONG\nC++ café 👋 \\"
        // Exercise Ghostty's /bin/sh -c parsing plus the production login shell.
        let args = CodexLaunch.arguments(prompt: prompt, executable: "/bin/echo", directory: "/tmp/test folder")!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", String(args[1].dropFirst("--initial-command=shell:".count))]
        let output = Pipe()
        process.standardOutput = output
        do { try process.run() } catch { fatalError("Couldn’t test shell: \(error)") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "--search --cd /tmp/test folder -- \(prompt)\n")
    }
}

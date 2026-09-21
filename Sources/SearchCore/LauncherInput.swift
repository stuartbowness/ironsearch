import Foundation

/// The trigger is consumed once. After entering Codex mode, the entire input
/// is a prompt; words such as "as" inside it are never interpreted as commands.
public struct LauncherInput: Equatable, Sendable {
    public private(set) var text = ""
    public private(set) var isChat = false

    public init() {}

    public mutating func edit(_ value: String) {
        if !isChat, let prefix = ["as ", "ask "].first(where: { value.lowercased().hasPrefix($0) }) {
            isChat = true
            text = String(value.dropFirst(prefix.count))
        } else {
            text = value
        }
    }

    public mutating func exitChat() { isChat = false }
    public mutating func reset() { self = LauncherInput() }
}

public enum CodexLaunch {
    /// A login shell supplies the user's PATH (including Node for npm installs).
    /// Quote every argument for Ghostty's explicit shell command parser.
    /// Option=value arguments avoid AppKit treating executable paths as documents.
    public static func arguments(prompt: String, executable: String, directory: String) -> [String]? {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !prompt.contains("\0") else { return nil }
        let command = ["/bin/zsh", "-lc",
                "exec \"$@\"", "iron-search", executable,
                "--yolo", "--search", "--cd", directory, "--", prompt]
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            .joined(separator: " ")
        return ["--working-directory=\(directory)", "--initial-command=shell:\(command)",
                "--quit-after-last-window-closed=true", "--shell-integration=none",
                "--window-save-state=never", "--initial-window=true",
                "--window-inherit-working-directory=false"]
    }
}

# Iron Search

**A small native macOS launcher for applications and contacts.**

Press **⌘Space**, type a name, and launch an app or open a contact card. Iron
Search combines an AppKit floating panel with SwiftUI content and a pure Swift
ranking engine. Local search runs without an account, network service, or
third-party runtime dependencies.

<img src="Resources/AppIcon.png" width="112" alt="Iron Search: brushed metal magnifying glass">

Built by [Stuart Bowness](https://github.com/stuartbowness). Released under the
[MIT license](LICENSE).

## Why this exists

I wanted a focused launcher for two everyday actions: opening an application and
finding someone's contact details. The implementation keeps the search algorithm
small enough to inspect, permission handling explicit, and the desktop integration
native. An optional `ask ` prefix hands a question to Codex in Ghostty.

This repository is a source release for **macOS 27 or later**. It is not a
notarized download, and it does not support older macOS versions.

## Build and try it

Requirements: macOS 27+, a compatible Swift toolchain/macOS SDK, and Apple's
Command Line Tools or Xcode. There are no package dependencies to install.

```sh
git clone git@github.com:stuartbowness/ironsearch.git
cd ironsearch
bash scripts/test.sh
IRONSEARCH_SIGNING_IDENTITY=- bash scripts/build.sh
open "dist/Iron Search.app"
```

This explicitly selects ad-hoc signing for a local build. Contacts permissions
may reset after rebuilding. For regular use, configure a stable Apple signing
identity as described in [the usage guide](docs/usage.md#build-and-run).

Disable Spotlight's **Show Spotlight search** shortcut in System Settings before
using ⌘Space. Iron Search reports a conflict if another app owns the shortcut;
you can still open it from the menu bar. Contacts access is optional and requested
only when you choose **Enable contacts**.

## Everyday use

| Action | Input |
| --- | --- |
| Open search | ⌘Space or menu-bar item |
| Find an application | Name, initials, or abbreviation |
| Find a contact | Name, company, email, phone, or postal address |
| Move and open | ↑ / ↓, then Return |
| Filter All / Apps / Contacts | ⌥⌘0 / ⌥⌘1 / ⌥⌘2 |
| Ask Codex in a new Ghostty session | `ask ` or `as ` followed by a question |
| Go back or dismiss | Escape |

Search ignores case and accents. Exact matches outrank fuzzy matches, even when
a fuzzy match was launched recently. Empty input hides results. Contact cards
support copying individual fields and opening the original card in Contacts.

The Codex handoff requires Ghostty and an authenticated Codex CLI. It preserves
your sandbox and approval settings. Neither dependency is needed for local search.

## For engineers reviewing the code

Start with [the architecture guide](docs/architecture.md), then read
[`SearchEngine.swift`](Sources/SearchCore/SearchEngine.swift) and
[`LauncherInput.swift`](Sources/SearchCore/LauncherInput.swift). The main design
choices are:

- **Pure ranking core:** matching and input transitions can be checked without
  opening a window or accessing a real contact store.
- **Explicit concurrency:** scans run away from the main actor; stale contact
  results cannot overwrite a newer refresh.
- **Native window control:** AppKit owns focus, hotkeys, and geometry; SwiftUI
  owns the content.
- **Literal command arguments:** the terminal handoff is tested through a real
  shell with quotes, substitutions, newlines, and Unicode in the prompt.

The tests are a dependency-free executable rather than XCTest so they can run
with standalone Command Line Tools. CI compiles the Foundation-only core against
the runner’s host SDK using `bash scripts/test-core.sh`; it does not build the
macOS 27 application. [Verification](docs/verification.md) explains
what they cover and the remaining manual checks.

## Privacy and limits

Contact data stays in memory. The app persists only the last 20 launched
application IDs; it has no telemetry or contact export. Copying a field writes
to the macOS clipboard. The optional Codex integration passes your explicit
question only and is subject to Codex's own configuration and data handling.

The app rescans when search opens; it does not maintain a filesystem watcher or
benchmark large address books. There is no plugin system, file-content search,
or automatic updater. Builds target the current machine's architecture.

## Contributing

Small, focused improvements are welcome. Explain the behaviour being changed,
add a regression check for ranking or input changes, and run
`bash scripts/test.sh` plus a local build. For UI changes, include the relevant
manual checks from [verification.md](docs/verification.md). Use synthetic contact
data in reports. Keep the dependency-free core independent of AppKit and Contacts.

See [the full usage guide](docs/usage.md) for signing, indexing, permissions, and
terminal integration details.

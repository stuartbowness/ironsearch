# Iron Search

A small, native macOS launcher for **applications and contacts**, with an explicit Codex shortcut. Press **⌘Space** from any app to open a search panel using Apple's native Liquid Glass. Requires macOS 27.0 or later.

<img src="Resources/AppIcon.png" width="128" alt="Iron Search app icon: a brushed iron magnifying glass with warm highlights on a graphite tile">

## Build and run

```sh
security find-identity -v -p codesigning
git config --local ironsearch.signingIdentity <certificate-SHA1>
bash scripts/build.sh
open "dist/Iron Search.app"
```

The app lives in the menu bar. You can move the built app to Applications using Finder. To start it automatically, add it under System Settings → General → Login Items. Local search requires no dependencies, accounts, or network services. The optional Codex handoff requires Ghostty and an authenticated Codex CLI installation.

The build script uses standalone Apple Command Line Tools when installed, without changing your selected Xcode. Configure a consistent Apple Development identity for local builds using the commands above. The certificate and private key stay in Keychain; only its identifier is stored in this checkout's local Git configuration. Install Apple's WWDR G3 intermediate certificate if the development identity is missing its certificate chain. Builds fail on signing errors rather than falling back to ad-hoc signing. `IRONSEARCH_SIGNING_IDENTITY` can override the local setting; explicitly setting it to `-` produces an ad-hoc build whose Contacts permission may reset after updates. After switching from ad-hoc to certificate signing, approve Contacts once more. A Developer ID and notarization would be needed for normal distribution to other Macs. Build output matches the current Mac's architecture.

## Use

| Key | Action |
| --- | --- |
| ⌘Space | Show or hide search globally |
| ↑ / ↓ | Select a result |
| Return | Launch the app, show contact details, or start Codex in Ghostty |
| Escape | Exit Codex mode keeping the text, back from contact details, or dismiss search |
| `as ` / `ask ` | Enter Codex mode (include the trailing space) |
| ⌥⌘0 / ⌥⌘1 / ⌥⌘2 | Filter All / Apps / Contacts |

Search opens as a compact glass search box, horizontally centered about a quarter of the way down the active display's usable area. Results, filters, and keyboard hints appear only after you type, expanding smoothly below the stationary search field; clearing the query collapses the panel again. Expanded height is limited to the space above the Dock. The transition respects Reduce Motion. Whitespace alone does not reveal results. Click a result to open it. Contact details have copy buttons for email addresses, phone numbers, company names, and all available postal addresses. Addresses retain their home/work/custom labels and mailing format. **Open in Contacts** opens that person’s card in Apple Contacts. Clicking outside dismisses the panel.

⌘Space is reserved globally while Iron Search is running. First disable **Show Spotlight search** under System Settings → Keyboard → Keyboard Shortcuts → Spotlight. Iron Search does not change that system setting for you. Quit from the menu bar to release the shortcut. If another global shortcut already owns ⌘Space, Iron Search reports the conflict; you can still open search from its menu-bar icon.

## Search and privacy

- Applications are discovered recursively in `/Applications`, `~/Applications`, `/System/Applications`, and `/System/Library/CoreServices/Applications`. Safari's system Cryptex location and Finder are also included. Nested app bundles are skipped, and duplicate bundle identifiers are collapsed.
- Contacts are read from the macOS Contacts store, including accounts synced into that app. Click **Enable contacts** and grant macOS permission. Limited access searches only the allowed contacts. Denied access leaves application search usable.
- Search supports names, company names, email addresses, phone numbers, postal addresses, initials, and fuzzy app/name abbreviations. Accents and capitalization are ignored. Recently launched apps receive a small ranking boost; empty searches show nothing.
- Indices refresh whenever search opens and through **Refresh Apps & Contacts** in the menu bar. Contact-store changes also trigger a refresh.
- Contact data stays in memory. Only the identifiers of the last 20 apps launched through Iron Search are saved in local preferences. There is no telemetry, upload, or contact export. Copying a field writes it to the macOS clipboard at your request.

## Ask Codex in Ghostty

Type `as ` or `ask ` to replace the prefix with a Codex badge. Type your question and press Return to open a **new interactive Codex session in Ghostty**, submitting the question immediately. Continue the conversation in the terminal. An empty prompt does nothing. Escape returns to local search and keeps your text; reopening Iron Search starts in local search. Names like Ashley and Asana do not trigger Codex mode.

The command uses `codex --yolo --search --cd <home-folder> -- <question>`. **Full access is intentional: `--yolo` disables approval prompts and sandboxing. Codex can run commands and modify files without asking.** `--search` enables live web search. The starting folder is your home directory (`~/`); it is not a security boundary. Your existing Codex model, authentication, and other settings apply. Iron Search does not change folder-trust settings; Codex may ask you to approve your home folder on first use.

Ghostty is launched as a fresh application instance so existing terminal sessions are not reused or interrupted. Codex is discovered in `~/.npm-global/bin`, `~/.local/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`. A login shell supplies PATH for dependencies such as Node. A shell-quoted `--initial-command=shell:…` option avoids Ghostty 1.3.1's macOS bug that treats positional paths after `-e` as files to open. Every command argument is single-quoted with embedded quotes escaped; the question reaches Codex as literal text. New tabs use the normal shell rather than repeating the question. No clipboard or Accessibility automation is used. Missing applications and launch failures leave the prompt visible with an error; authentication or CLI startup errors appear in Ghostty. Only your explicit question is handed off, not the local contact index; Codex itself has full filesystem access and may retain session history.

## Verification

Iron Search's Ghostty instance disables window restoration and working-directory inheritance, and explicitly creates an initial window. This prevents old tabs (including tabs left by earlier launches) from replacing the intended Codex session. These are per-launch arguments; the regular Ghostty configuration is not edited.

```sh
bash scripts/test.sh
```

This runs dependency-free checks for ranking, abbreviations, accent normalization, contact field searches, phone normalization, scope filtering, recents, limits, empty results, Codex trigger boundaries, mode transitions, launch arguments, and literal prompt handling through the shell. Contacts permissions, global keyboard behavior, and the Ghostty handoff also need interactive verification on the target Mac.

## Structure

- `Sources/SearchCore`: searchable records and deterministic ranking.
- `Sources/IronSearch`: native SwiftUI search panel, AppKit lifecycle, global hotkey, application indexing, and Contacts integration.
- `Resources/Info.plist`: app identity and Contacts permission description.
- `Resources/AppIcon.icns`: native multi-resolution app icon; `scripts/make-icon.swift` generates standard and Retina sizes from the approved artwork in `Resources/AppIcon.png` during builds.
- `scripts/build.sh`: builds and signs `dist/Iron Search.app`.

Inspired by the quick keyboard-driven launcher interaction in [Alfred](https://www.alfredapp.com/) and Spotlight, with a deliberately small scope.

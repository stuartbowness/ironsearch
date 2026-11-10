# Architecture and tradeoffs

Iron Search keeps ranking independent of the desktop integration. There are no
third-party package dependencies and no service to deploy.

```text
AppKit panel + global hotkey
           │
     SwiftUI SearchView
           │
   @MainActor SearchModel
       ┌───┴─────────┐
ApplicationIndex  ContactIndex       Detached scans
       └───┬─────────┘
       SearchItem[]
           │
       SearchEngine                  Pure ranking
           │
    Ranked results → launch / contact details
```

## Where to start reading

| File | Responsibility |
| --- | --- |
| `Sources/SearchCore/SearchEngine.swift` | Normalization, matching, ranking, filtering |
| `Sources/SearchCore/LauncherInput.swift` | Search/chat state transitions and shell argument construction |
| `Sources/IronSearch/SearchModel.swift` | UI state, indexing, permissions, application and terminal launch |
| `Sources/IronSearch/App.swift` | Panel lifecycle, hotkey registration, focus, geometry |
| `Sources/IronSearch/SearchView.swift` | Search field, results, contact details, keyboard interaction |
| `Tests/SearchCoreTests/SearchEngineTests.swift` | Executable regression checks for ranking and command boundaries |

## Ranking is explicit

Each item caches normalized names, searchable fields, initials, and phone digits.
Exact names rank above prefixes, then initials, substrings, field matches, and
subsequences. Recency adds at most 20 points; the smallest gap between matching
tiers is 100, so a recently launched fuzzy match cannot displace an exact match.
Ties use localized title ordering, then stable IDs.

This is a linear scan followed by sorting, appropriate for a personal application
and contact index. It is not a large-corpus search engine. There are no latency
benchmarks in this repository. A larger index would warrant measurement before
adding a database, incremental indexing, or a more complex ranking model.

## Desktop work stays outside the ranking core

`SearchModel` owns observable state on the main actor. Application and contact
scans run in detached tasks; a generation counter prevents an older contact scan
from overwriting a newer permission or refresh result. Application refreshes
coalesce while indexing is already in progress.

Contacts have explicit not-requested, loading, ready, denied, restricted, and
failed states. Denial leaves app search available. Only recent application IDs
are persisted. Contact fields remain in memory and are copied to the clipboard
only at the user's request.

## AppKit owns the window; SwiftUI owns its contents

The launcher needs a floating panel, global shortcut, explicit focus, and window
geometry that stays anchored while results expand downward. AppKit handles those
responsibilities. SwiftUI renders the contents. The glass silhouette belongs to
`NSGlassEffectView` so its corners follow the AppKit resize rather than a separate
SwiftUI animation. This choice also deliberately limits OS compatibility.

## The terminal handoff is a trust boundary

Typing `ask ` or `as ` enters a distinct input mode. The prefix is consumed once;
words inside the resulting prompt are never reinterpreted as launcher commands.
The prompt is passed after `--`, with each shell argument quoted separately.
A regression test passes quotes, substitutions, newlines, and Unicode through
the actual shell chain and checks the resulting arguments.

Ghostty opens in a new instance. The launcher enables Codex web search, but does
not override sandbox or approval settings. It passes only the explicit prompt,
not the contact index. Codex remains a separate application with its own access
and retention settings.

## What the tests do not establish

The dependency-free `SearchChecks` executable tests the pure core, including the
shell handoff. It does not automate macOS Contacts permission dialogs, global
shortcut conflicts, multi-monitor focus, accessibility, or visual resizing.
Those require the manual checks in [verification.md](verification.md). There is
no claim of Linux support or a notarized binary release.

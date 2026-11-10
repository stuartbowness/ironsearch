# Verification

Run from the repository root:

```sh
bash -n scripts/*.sh
bash scripts/test.sh
IRONSEARCH_SIGNING_IDENTITY=- bash scripts/build.sh
```

The build verifies the resulting app signature. Ad-hoc signing is useful for
local evaluation; a stable signing identity is preferable for retained Contacts
permissions. Build success does not establish Gatekeeper distribution readiness.

## Manual acceptance checks

Use a test macOS account if you want to exercise permissions without your real
contacts. These are a checklist, not a claim of automated coverage.

- Open the built app; check menu-bar launch and ⌘Space. When Spotlight owns the
  shortcut, verify the conflict is visible and menu launch still works.
- Search an installed app by exact name, initials, and abbreviation. Launch it.
- Deny Contacts access; application search must remain usable.
- Grant access using synthetic contacts; search accents, phone digits, company,
  and postal address. Copy a field and open the card in Contacts.
- Revoke access; refresh and confirm contact results and details disappear.
- Clear input, expand results, and press Escape. Check focus and window corners
  on multiple displays and with Reduce Motion enabled.
- With Ghostty and Codex installed, submit a harmless question using `ask `.
  Confirm a fresh terminal session opens. Test missing-dependency errors too.

Do not include screenshots of personal contact information in issues or demos.

## CI scope

`bash scripts/test-core.sh` compiles the same core checks directly with `swiftc`
against the host SDK. GitHub Actions uses this path because the hosted runner
need not have the app’s macOS 27 SDK. A green core job does not establish that
the full application builds or its desktop interactions work.

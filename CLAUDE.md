# Burrow (Mole-GUI): agent instructions

Burrow is a native SwiftUI macOS app that gives a premium GUI to the Mole cleaner CLI
(github.com/tw93/Mole, GPL-3.0). Repo: github.com/khan-umirzakoff/Mole-GUI, public, GPL-3.0.
Everything about this project is written here or in this repository, never in other projects'
folders or memories.

## Shape
- `Sources/Burrow/Engine`: how Mole is run. `Mole.swift` (pipes: JSON and dry-run text, process
  tracking), `MoleSession.swift` (pseudo-terminal for real actions: Mole keeps its prompts, sudo and
  safety checks; the app answers prompts natively), `Reports.swift` (parsers), `TerminalText.swift`.
- `Sources/Burrow/Design`: the design system (glow cards, dot-matrix numerals, gauges, motion).
- `Sources/Burrow/Features`: one file per page; long-lived scans and stores live in `AppModel`.
- `Vendor/mole`: the bundled Mole engine (`VERSION` file). Do not edit it; update it as a whole.
- `scripts/bundle.sh` builds `build/Burrow.app` (release binary + Mole + icon, ad-hoc signed).

## Build rules
- Xcode Command Line Tools only, no Xcode: `swift build`, `swift test`, `scripts/bundle.sh`.
- The `@State` macro plugin ships only with Xcode, so use `@ViewState` (a typealias for
  `SwiftUI.State`) everywhere. Tests use Swift Testing (`import Testing`), not XCTest.
- No new package dependencies without a recorded reason.

## Safety (this runs on the owner's real Mac)
- Agents never run a real Mole action while testing: no `clean`, `uninstall`, `purge`, `slim`,
  `optimize`, `installer` without `--dry-run`, no `touchid enable/disable`, `remove`, `update`.
- In the running app, never press Clean now, Optimize, Uninstall, Remove selected, Move to Trash,
  Slim apps, Touch ID Turn on/off or Remove…, and never confirm a Mole prompt.
- Never write the owner's Mole config and state (`~/.config/mole`, `~/.cache/mole`,
  `~/Library/Logs/mole`); tests use a temporary directory.
- Quit Burrow after testing and make sure no `Burrow.app/Contents/Resources/mole` process remains.

## Design bar
Dark, premium, few large elements: squircle cards lit by one hue (rim or inner glow), dot-matrix
numerals, dotted meters, capsule buttons, white circular icon buttons; smooth, purposeful motion that
honours Reduce Motion. Reviews of UI, UX, visuals and motion are done by a Claude `"opus"` critic with
screenshots of every page and the diff, never by Codex (no design taste); Codex only reviews
engine/backend code.

## Releases
GitHub releases carry `Burrow.zip` (`ditto -c -k --keepParent build/Burrow.app`). Bump `VERSION`,
build, test, then `gh release create v<version>`.

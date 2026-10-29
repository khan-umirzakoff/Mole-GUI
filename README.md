# Burrow

A free, open-source macOS app for [Mole](https://github.com/tw93/Mole), the deep cleaner by tw93.
Everything Mole does in the terminal, in one window: clean, uninstall, optimize, map the disk,
remove project build folders and old installers, slim universal apps, and watch system health.

![Overview](docs/overview.jpg)

## Why

Mole is excellent but lives in the terminal, and its own app is paid. Burrow puts a native
SwiftUI window on top of the same engine. Every change still goes through Mole, so its safety
checks, protection rules and Trash-first deletes stay in charge.

## What is inside

| Page | Mole command | What you get |
|---|---|---|
| Overview | `mo status --watch` | Live free space, health score, CPU, memory, battery, network, busiest processes |
| Clean | `mo clean` | Dry-run preview by category, then one-click clean (system caches optional, asks for your password natively) |
| Uninstall | `mo uninstall` | All apps with sizes, multi-select, preview leftovers, Trash or permanent |
| Optimize | `mo optimize` | Pending maintenance steps and performance diagnosis |
| Disk Map | `mo analyze --json` | Treemap with drill-down, reveal in Finder, move to Trash |
| Projects | `mo purge` | Build folders grouped by project, remove all or a selection |
| Installers | (native, same folders as `mo installer`) | Old `.dmg`, `.pkg`, `.iso`, `.xip` files, move to Trash |
| Slim Apps | `mo slim` | Intel code in universal apps, pick which apps to slim |
| History | `mo history --json` | Every run and what it changed |
| Settings | config files, `mo touchid` | Protected paths, project scan folders, Touch ID for sudo, full removal |

## Install

Download `Burrow.zip` from [Releases](../../releases), unzip, move `Burrow.app` to Applications.
The app is ad-hoc signed, so the first time right-click it and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Burrow.app
```

Requires macOS 26 or later on Apple silicon.

## Nothing left behind

Mole ships inside the app (`Contents/Resources/mole`); nothing is installed into your system.
Mole keeps its settings and logs in `~/.config/mole`, `~/.cache/mole` and `~/Library/Logs/mole`.
**Settings → Remove Burrow completely** deletes those, the app's preferences, and moves the app
to the Trash.

## Build

Only the Xcode Command Line Tools are needed (no Xcode):

```bash
swift test
scripts/bundle.sh     # → build/Burrow.app
```

The Mole engine is vendored in `Vendor/mole` (version in `Vendor/mole/VERSION`). To update it,
replace that folder with a newer Mole release's `libexec` contents.

## License

GPL-3.0, the same as Mole. Mole © tw93 and contributors; source at
[github.com/tw93/Mole](https://github.com/tw93/Mole) (the bundled `analyze-go` and `status-go`
binaries are built from that source, tag `V1.65.0`).

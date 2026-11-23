# Yeoman 0.2.9

## Highlights

- **Finder Cut (`⌘X` → `⌘V`) Module:** Adds Windows-style file cut and move shortcuts (`⌘X` to cut, `⌘V` to move, `⌘C` / `Esc` to cancel) in macOS Finder without touching Finder's filesystem logic. Operations delegate natively via Finder's Accessibility menu actions (`Copy` / `Move Item Here`) with a `.privateState` synthetic fallback, preserving native Finder undo (`⌘Z`) and conflict prompts while automatically passing through text fields and all non-Finder applications.
- **Live Cut Highlight in Finder:** Draws a click-through dashed pill outline directly over cut items in Finder, merging contiguous selections into a single outer border, clipping cleanly beneath column headers, preserving horizontal overflow edges, and projecting live WindowServer window geometry at 120Hz during resize drags with zero background load when idle or outside Finder.
- **Missing-Permission Prompt:** Registers a Finder-only fallback `⌘X` hotkey when Accessibility permission is not yet granted so users receive an actionable prompt opening System Settings (with session mute and cooldown).
- **Web Widgets Post-Reboot & Network Recovery:** Automatically recovers web widgets that fail provisional navigation during macOS boot/login or sleep wake using `NWPathMonitor`, wake notifications, bounded retries, and presentation-time reload.

## Quality & Security

- Added comprehensive regression tests in `Tests/FinderCutTests.swift` and `Tests/WebPanelTests.swift` covering event-tap filtering, shortcut classification, text-field exclusion, state transitions, overlay geometry projection/merging/header clipping, and post-reboot recovery (`107/107` tests passing).
- Verified the complete test suite under ThreadSanitizer (`swift run --sanitize thread YeomanTests`, `107/107` passing) with zero warnings.

## System Requirements

- macOS 14.0 or newer
- Pre-built release targets Apple Silicon (`arm64`)

## SHA-256

- `Yeoman.zip`: `e803d561bc4c6582ea2842dc981c549a411434b11900b7e5eef392e0cf709083`
- `Yeoman.dmg`: `0245ab22d6109c309781c353528674aa1cb2791e390ee0689ff940493655631e`

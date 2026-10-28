# Yeoman 0.2.7

## Improvements

- **System Stats:** Added a new compact layout mode: "Vertical (Bar below)" (`verticalBarBottom`), placing metric labels and percentages side-by-side above a wide horizontal fill bar or sparkline.
- **System Stats:** Renamed vertical stacked layout to "Vertical (Bar right)" for clarity, with backwards-compatible configuration handling and updated localizations across English, German, Spanish, and French.
- **Scroll Reverser:** Event tap moved to `.tailAppendEventTap` at the tail of macOS's scroll-processing pipeline on a dedicated `userInteractive` thread and run loop, isolating event handling from UI work.
- **Scroll Reverser:** Devices configured for native scrolling now bypass mutation with a direct no-op path, and tap timeouts automatically recover without requiring app restarts.
- **Scroll Reverser:** Removed main-thread diagnostic dispatching from event callbacks for lower-latency scroll wheel translation.

## Quality & Security

- Added regression tests for `StatsLayoutMode` backward compatibility, localization, and width calculation across all supported locales (88/88 test suite passing).
- Verified concurrent scroll event tap worker and configuration changes under ThreadSanitizer with zero race conditions.

## System Requirements

- macOS 14.0 or newer
- Pre-built release targets Apple Silicon (`arm64`)

## SHA-256

- `Yeoman.zip`: `5ae30f9819629ac0788c75aa973079ec42fcc30ad48f8e5291516bdadae65766`
- `Yeoman.dmg`: `49534dacc6545c3a8740087d53ac5a70203e18d560d58c383d703ade44bff186`

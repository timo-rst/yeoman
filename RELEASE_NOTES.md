# Yeoman 0.2.8

## Improvements

- **Clipboard History:** Replaced the modal image preview sheet with a non-modal floating preview panel that respects the popover pin state (clicking outside dismisses both the preview and clipboard popover when unpinned, or keeps both open when pinned; closing via `X` or `Esc` restores popover focus and preserves transient outside-click dismissal).
- **Clipboard History:** Added a dedicated resizable full-image viewer window (`Open Image` button or clicking the preview image) with Fit-to-Window and 25%–400% zoom controls, rendered entirely in memory without writing plaintext files to disk.
- **Task Manager & UI Controls:** Replaced the segmented sort picker with a full-area hit-tested control (`CPU %`, `Memory`, `Name`), eliminated unwanted blue focus rings across popover and settings buttons, and restricted process list polling and icon lookups (`NSCache`) to when the task manager popover is open.

## Quality & Security

- Added unit tests for `ClipboardPreviewDismissalPolicy` outside-click behavior across pinned/unpinned states and `ClipboardFullImageWindowController` bounded initial window sizing (90/90 test suite passing).
- Verified the complete test suite under ThreadSanitizer (`swift run --sanitize thread YeomanTests`, 90/90 passing) with zero warnings.

## System Requirements

- macOS 14.0 or newer
- Pre-built release targets Apple Silicon (`arm64`)

## SHA-256

- `Yeoman.zip`: `dd5226fc00cadc23defb5b825fd644ca878c08586a6a5ea8533ef7097c8300f9`
- `Yeoman.dmg`: `259d09d8e7e2e5a0b96f79bc529a09d9a98f2b85c24bff846347d201eba7ac19`

# Yeoman 💂

**Yeoman** is a fast, modular, native menu bar companion and system customizer for macOS. Built with 100% pure Swift, AppKit, and SwiftUI with **zero external dependencies**.

---

## Features

- 📏 **Menu Bar Architecture & Spacing:**
  - Compact and custom spacing/padding between menu bar icons (e.g. 4 pt, 8 pt, or custom values).
  - Multi-display and MacBook notch inspection.
  - Live status item reordering and visibility management.
- 🌐 **Web Widgets (Micro-Web-Apps):**
  - Embed any web application directly into your menu bar (Gemini, Proton Calendar, ChatGPT, Jira, WhatsApp, etc.).
  - Automatic favicon discovery and caching.
  - Aggressive memory throttling and cache purging when closed for near-zero idle RAM consumption.
- 📋 **Privacy-First Clipboard Manager ("Clippy"):**
  - Full history with fast search across text, code snippets, URLs, images, and screenshots.
  - Pinning for persistent quick access.
  - Unconditional privacy protection ignoring transient and concealed pasteboard types from 1Password, Bitwarden, KeePass, Proton Pass, and Apple Keychain.
  - POSIX `0600` / `0700` local file permissions.
- 📊 **System Stats & Protected Task Manager:**
  - Live CPU, RAM, Network, and Disk activity in your menu bar.
  - Popover task manager with visual web-widget indicators and favicons.
  - Protected process termination preventing accidental killing of critical system daemons (`launchd`, `WindowServer`, `loginwindow`, PID <= 1).
- 🖱️ **Scroll Reverser:**
  - Independent scroll direction configuration for mouse wheel vs. trackpad without restarting macOS.
  - Smooth native event tap with low-level precision.
- 🧩 **Modular Architecture:**
  - Every feature is an isolated module that can be individually enabled, disabled, or customized.

---

## Development & Testing

### Run Automated Tests

Yeoman includes a zero-dependency native test harness covering version resolution, security whitelists, privacy filters, and module lifecycles:

```bash
swift run YeomanTests
```

### Build App Bundle Locally

```bash
# Compile and create signed dist/Yeoman.app bundle
./Scripts/build_app.sh

# Launch application
open dist/Yeoman.app
```

### Package for Release

To execute all tests, build the optimized release binary, and generate distribution archives (`.dmg` with `/Applications` drag-and-drop installer + `.zip`):

```bash
./Scripts/package_release.sh
```

---

## Project Structure

```
yeoman/
├── Package.swift                    # Swift Package Manager Manifest
├── LICENSE                          # MIT License
├── Resources/
│   ├── AppIcon.icns                 # Native macOS App Icon
│   └── AppIcon.png                  # High-res icon preview
├── Scripts/
│   ├── build_app.sh                 # Builds and signs the local .app bundle
│   ├── package_release.sh           # Runs tests, builds .app, and generates .dmg & .zip
│   ├── ci.yml                       # GitHub Actions CI workflow template
│   └── generate_yeoman_icon.swift   # Icon generation tool
├── Sources/
│   └── Yeoman/
│       ├── App/                     # App entry point & AppDelegate
│       ├── Core/                    # Module management, auto-updates & localization
│       ├── Modules/
│       │   ├── MenuBar/             # Spacing, item scanning & menu bar controller
│       │   ├── WebPanel/            # Web widgets, WKWebView controller & favicon manager
│       │   ├── Clipboard/           # Pasteboard monitor, image cache, history store & UI
│       │   ├── SystemStats/         # System metrics, process table & task manager
│       │   └── ScrollReverser/      # CGEventTap scroll direction controller
│       └── UI/                      # StatusItemController, settings & submenus
├── Tests/                           # Zero-dependency native unit & integration tests
│   ├── TestHarness.swift            # Lightweight assertion engine
│   ├── UpdateManagerTests.swift     # Semver & trusted host security tests
│   ├── ClipboardTests.swift         # Privacy & password manager detection tests
│   ├── WebPanelTests.swift          # Widget model serialization tests
│   ├── LocalizationTests.swift      # Multi-language coverage tests
│   ├── ModuleManagerTests.swift     # Module registry verification tests
│   └── main.swift                   # Test suite runner entry point
└── README.md
```

---

## License

Distributed under the [MIT License](LICENSE). Copyright © 2024-2026 Timo Richstein.


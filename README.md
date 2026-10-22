# Yeoman 🛡️

**Yeoman** is a modular, native all-in-one menu bar companion and system suite for macOS. Built with 100% pure Swift, AppKit, and SwiftUI with **zero external dependencies**.

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

## Build & Run

### Quickstart with Swift Package Manager:

```bash
# Debug build
swift build

# Build signed macOS application bundle (.app)
./Scripts/build_app.sh

# Launch application
open dist/Yeoman.app
```

---

## Project Structure

```
yeoman/
├── Package.swift                    # Swift Package Manager Manifest
├── Resources/
│   ├── AppIcon.icns                 # Native macOS App Icon
│   └── AppIcon.png                  # High-res icon preview
├── Scripts/
│   ├── build_app.sh                 # Builds and signs the release .app bundle
│   └── generate_yeoman_icon.swift   # Generates AppIcon.icns from source artwork
├── Sources/
│   └── Yeoman/
│       ├── App/                     # App entry point & AppDelegate
│       ├── Core/                    # Module management, updates, and localization
│       ├── Modules/
│       │   ├── MenuBar/             # Spacing, item scanning & menu bar controller
│       │   ├── WebPanel/            # Web widgets, WKWebView controller & favicon manager
│       │   ├── Clipboard/           # Pasteboard monitor, image cache, history store & UI
│       │   ├── SystemStats/         # System metrics, process table & task manager
│       │   └── ScrollReverser/      # CGEventTap scroll direction controller
│       └── UI/                      # StatusItemController, settings & submenus
├── IMPLEMENTATION_PLAN.md           # Architecture documentation
└── README.md
```

---

## License

Copyright © 2026 Timo Richstein. All rights reserved.
Distributed under the MIT License.

<p align="center">
  <img src="Resources/AppIcon.png" alt="Yeoman Icon" width="128" height="128" style="border-radius: 28px;" />
</p>

<h1 align="center">Yeoman</h1>

<p align="center">
  Modular macOS menu bar utility built with Swift and SwiftUI.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0%2B-black?style=flat-square&logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-6.0%20%2F%20SwiftUI-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/dependencies-0%20(Pure%20Native)-success?style=flat-square" alt="Zero Dependencies" />
  <img src="https://img.shields.io/badge/telemetry-none-blue?style=flat-square" alt="No Telemetry" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" />
</p>

<p align="center">
  <img src="Resources/Mockups/yeoman_settings_window.png" alt="Yeoman Settings Window" width="100%" />
</p>

---

## Overview

Yeoman is an open-source macOS menu bar tool that bundles several customization modules into a single native process. Each module can be enabled or disabled independently.

### Specifications & Resource Usage

- **Target OS:** macOS 14.0 (Sonoma) or newer (Apple Silicon & Intel)
- **Frameworks:** Apple AppKit & SwiftUI (0 external libraries or third-party dependencies)
- **Networking:** Local only. No telemetry, analytics, or background tracking requests
- **Disk Storage:** Standard macOS Application Support directory (`~/Library/Application Support/Yeoman`) with POSIX `0700` permissions
- **Idle Memory:** ~60 MB RAM (with WebKit views unloaded)
- **Idle CPU:** < 1%

---

## Motivation & Background

This project started because several utilities I relied on broke or became incompatible across newer macOS updates. Rather than searching for separate replacements, I decided to build the specific features I personally need into a single native menu bar app.

Nothing here is reinventing the wheel—it is simply a collection of tools tailored to my personal preferences and daily workflow.

> **AI Transparency:** This project was developed with the assistance of AI pair-programming tools for scaffolding, implementation, and test coverage, directed and reviewed by the author.

---

## Modules

### 1. Web Widgets
Displays websites inside floating panels accessible directly from menu bar icons.
- **Configurable Dimensions:** Freeform width and height sliders or presets (320×400, 375×667, 500×700).
- **User Agent Modes:** Auto, forced mobile (iPhone), or forced desktop.
- **Window Pinning:** Optional pin mode to keep windows open when clicking outside.
- **Lifecycle:** WebKit timers and cached pages are halted when panels are closed.

<p align="center">
  <img src="Resources/Mockups/yeoman_web_widgets.png" alt="Yeoman Web Widgets" width="92%" />
</p>

### 2. Clipboard History
Records copied text and images locally.
- **Privacy Filtering:** Automatically ignores pasteboard items flagged by password managers (1Password, Bitwarden, KeePass, Proton Pass, Apple Keychain) via `org.nspasteboard.TransientType` and `.ConcealedType`.
- **Search & Filter:** Search by text content or filter by category (text, images, pinned favorites).
- **Storage:** Persisted locally as JSON and PNG files in `~/Library/Application Support/Yeoman/`.

<p align="center">
  <img src="Resources/Mockups/yeoman_clipboard_popover.png" alt="Yeoman Clipboard Popover" width="55%" />
</p>

### 3. Menu Bar Spacing & Items
Adjusts layout and spacing of macOS menu bar items.
- **Item Spacing:** Adjust icon spacing from 0 to 32 pt (presets: 4 pt, 8 pt, 16 pt).
- **Item Scanner:** Lists detected system and third-party status bar items across connected displays.

<p align="center">
  <img src="Resources/Mockups/yeoman_menubar_spacing.png" alt="Yeoman Menu Bar Spacing" width="92%" />
</p>

### 4. Independent Scroll Reverser
Separates scroll direction handling between mouse wheels and trackpads.
- **Event Tap:** Inverts wheel deltas using a `CGEventTap` without altering system trackpad preferences.

### 5. System Stats
Shows hardware usage in the menu bar.
- **Metrics:** CPU utilization, memory allocation, and battery status.
- **Process List:** Inspects running processes with sorting by CPU and memory usage.

---

## Installation

### Pre-built Binary
Download `Yeoman.dmg` from [GitHub Releases](https://github.com/timo-rst/mac_customizer/releases). Open the disk image and move `Yeoman.app` to `/Applications`.

> If running without an Apple Developer ID signature, open via right-click → **Open**, or clear the quarantine flag:
> ```bash
> xattr -cr /Applications/Yeoman.app
> ```

### Building from Source
Requires Xcode 15+ or the Swift 6.0 command-line tools.

```bash
git clone https://github.com/timo-rst/mac_customizer.git
cd mac_customizer

./Scripts/build_app.sh
open dist/Yeoman.app
```

---

## Tests

The project includes unit tests covering version parsing, update host validation, clipboard privacy rules, and module lifecycles:

```bash
swift run YeomanTests
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.

# Yeoman – Architecture & Implementation Plan

## 1. Vision & Objectives

**Yeoman** is a modular, native macOS control center and menu bar companion that unites specialized system utilities into a single, high-performance, lightweight application:

1. **Menu Bar Optimizer:**
   - Custom menu bar item spacing and selection padding.
   - Robust multi-monitor and MacBook notch detection.
   - Clean ControlCenter process restart for instant system-wide rendering updates.

2. **Web Widgets (Micro-Web-Apps):**
   - Persistent web applications embedded directly into the menu bar.
   - Memory throttling and automatic cache eviction when closed.
   - Automatic favicon resolution and menu bar icon generation.

3. **Privacy-First Clipboard Manager ("Clippy"):**
   - Seamless clipboard history with instant search across text, code, and screenshots.
   - Pinning and favorites.
   - Unconditional exclusion of sensitive password managers and transient pasteboard types.
   - Restricted local file permissions (`0600`/`0700`).

4. **System Stats Monitor & Task Manager:**
   - Real-time CPU, RAM, Network, and Disk metrics in the menu bar.
   - Popover task manager with web-widget identification and safe process termination.

5. **Scroll Reverser:**
   - Independent reverse scrolling for mouse wheel vs. trackpad without macOS restarts.

6. **Modular Extensibility:**
   - Unified `CustomizerModule` lifecycle protocol allowing features to be toggled, configured, or extended cleanly.

---

## 2. Architecture Overview

```mermaid
graph TD
    App[Yeoman App / NSApplication] --> MM[ModuleManager]
    App --> SIC[StatusItemController (Menu Bar)]
    
    MM --> M1[MenuBarModule]
    MM --> M2[ClipboardModule]
    MM --> M3[SystemStatsModule]
    MM --> M4[WebPanelModule]
    MM --> M5[ScrollReverserModule]
    
    M1 --> MBSM[MenuBarSpacingManager]
    M1 --> MBSV[MenuBarSettingsView]
    
    M2 --> CM[ClipboardMonitor]
    M2 --> CHS[ClipboardHistoryStore]
    M2 --> CV[ClipboardView]
    
    SIC --> Menu[Menu Bar Dropdown & Quick Access]
    SIC --> Prefs[Settings Window (SwiftUI)]
```

### Core Components:
- **`CustomizerModule` Protocol:** Standardized lifecycle (`start()`, `stop()`, `isEnabled`, `settingsView()`).
- **`StatusItemController`:** Native status item controller with dynamic menu and quick access to modules.
- **`ModuleManager`:** Central coordinator managing all active modules and preferences.

---

## 3. Milestones & Status

| Phase | Focus | Status |
|---|---|---|
| Phase 1 | Project setup, module protocol & architecture | Completed |
| Phase 2 | Menu bar spacing & multi-monitor support | Completed |
| Phase 3 | Clipboard monitor, image caching & privacy guards | Completed |
| Phase 4 | System metrics & protected task manager | Completed |
| Phase 5 | Web widgets, WKWebView throttling & favicon manager | Completed |
| Phase 6 | Scroll reverser with low-level event tap | Completed |
| Phase 7 | Security audit, strict file permissions & hardening | Completed |
| Phase 8 | Rebranding to Yeoman & modern icon generation | Completed |

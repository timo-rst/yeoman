# MacCustomizer 🛠️

Eine modulare, native All-in-One Steuerzentrale für macOS Anpassungen. Entwickelt mit Swift & SwiftUI.

## Features

- 📏 **Menüleisten-Optimizer (Ice-Alternative):**
  - Kompaktere Abstände für Menüleisten-Symbole (z. B. 4 pt, 8 pt oder frei wählbar).
  - Multi-Monitor Erkennung und Notch-Inspektion.
  - Automatischer Neustart des ControlCenter zur sofortigen Übernahme.
- 📋 **Clipboard Manager ("Clippy"):**
  - Lückenlose Historie mit Suche nach Text, URLs und Code-Snippets.
  - Pinning für wichtige Einträge.
  - Automatisches Ausschließen sensibler Zwischenablagen (Passwort-Manager wie 1Password, Bitwarden etc.).
- 📊 **System-Monitor Vorbereitung:**
  - Grundgerüst für Menüleisten-Metriken (CPU, RAM, GPU).
- 🧩 **Modulare Architektur:**
  - Jedes Feature ist ein eigenständiges Modul (`CustomizerModule`), das nach Belieben aktiviert, deaktiviert oder erweitert werden kann.

---

## Projekt bauen & starten

### Schnellstart mit Swift PM:
```bash
# Debug-Build
swift build

# Als native macOS .app erstellen
./Scripts/build_app.sh

# App starten
open dist/MacCustomizer.app
```

---

## Projektstruktur

```
mac_customizer/
├── Package.swift                    # Swift Package Manager Manifest
├── Scripts/
│   └── build_app.sh                 # Erstellt das releasefähige .app Bundle
├── Sources/
│   └── MacCustomizer/
│       ├── App/                     # App-Einstiegspunkt & AppDelegate
│       ├── Core/                    # Modul-System, DisplayManager, Event Handling
│       ├── Modules/
│       │   ├── MenuBar/             # Spacing Manager, Multi-Display & UI
│       │   ├── Clipboard/           # Pasteboard Monitor, Historie, Suche & UI
│       │   └── SystemStats/         # CPU/RAM/GPU Metriken
│       └── UI/                      # StatusItemController, Einstellungen & Menüs
├── IMPLEMENTATION_PLAN.md           # Architektur & Roadmap
└── README.md
```

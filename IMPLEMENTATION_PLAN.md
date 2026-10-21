# MacCustomizer – Implementierungsplan & Architektur

## 1. Vision & Zielsetzung

**MacCustomizer** ist eine modulare, native macOS-Steuerzentrale (Menüleisten-Applikation), die mehrere spezialisierte Einzel-Apps in einer schlanken, hochgradig konfigurierbaren Anwendung vereint:

1. **Menüleisten-Optimizer (Ice / Bartender Alternative):**
   - Anpassen der Menüleisten-Abstände (Kompakter Look wie im Ice Dock).
   - Sauberes Beheben des bekannten **Multi-Monitor-Bugs** (verschiedene Monitorauflösungen, Notch-Diskrepanzen zwischen MacBook-Display und externen Monitoren).
   - Ausblenden/Einblenden von sekundären Menüleisten-Symbolen.

2. **Clipboard Manager ("Clippy" / Maccy Alternative):**
   - Lückenlose Historie der Zwischenablage mit Instant-Suche.
   - Favoriten/Pinning-Funktion.
   - Intelligenter Schutz vor dem Speichern sensibler Passwörter (1Password, Bitwarden, KeePass etc.).
   - Globaler Hotkey (`Cmd + Shift + V`) für ein Spotlight-ähnliches Floating Panel.

3. **System Stats Monitor (Menüleisten-Metriken):**
   - Kompakte GPU-, RAM- und CPU-Metriken direkt in der Menüleiste (wie im Screenshot).

4. **Modulare Erweiterbarkeit:**
   - Klare Schnittstelle (`CustomizerModule`), über die zukünftige Features (Window Tiling, Quick Launcher, Audio Switcher etc.) ohne Eingriff in den App-Kern ergänzt werden können.

---

## 2. Architekturübersicht

```mermaid
graph TD
    App[MacCustomizer App / NSApplication] --> MM[ModuleManager]
    App --> DM[DisplayManager]
    App --> SIC[StatusItemController (Menüleiste)]
    
    MM --> M1[MenuBarModule]
    MM --> M2[ClipboardModule]
    MM --> M3[SystemStatsModule]
    MM --> M4[Zukünftige Module...]
    
    M1 --> MBSM[MenuBarSpacingManager]
    M1 --> MBSV[MenuBarSettingsView]
    DM -. Event-Benachrichtigung .-> M1
    
    M2 --> CM[ClipboardMonitor]
    M2 --> CHS[ClipboardHistoryStore]
    M2 --> CV[ClipboardView]
    
    SIC --> Menu[Menüleisten-Dropdown & Quick-Access]
    SIC --> Prefs[Settings Window (SwiftUI)]
```

### Kernkomponenten:
- **`CustomizerModule` Protocol:** Einheitlicher Lebenszyklus (`start()`, `stop()`, `isEnabled`, `settingsView()`).
- **`DisplayManager`:** Reagiert auf `NSApplication.didChangeScreenParametersNotification`, erfasst Display-Geometrie, Skalierung und Notch-Präsenz.
- **`StatusItemController`:** Das native Menüleisten-Symbol mit dynamischem Statusmenü und Schnellzugriff auf alle Module.

---

## 3. Die Multi-Monitor-Problematik & Lösung

### Warum scheitert Ice oft bei externen Monitoren?
1. **Notch vs. Flat Bezel:** Das MacBook-Display besitzt eine Aussparung (Notch), die Menüleisten-Elemente nach links und rechts trennt. Externe Displays haben keine Notch.
2. **Display Re-ordering:** Beim Anstecken/Abziehen ändern sich die absoluten CoreGraphics-Koordinaten. Feste Offset-Berechnungen treffen dann die falsche Position.
3. **Displays have separate Spaces:** Je nachdem, ob macOS "Displays have separate Spaces" aktiviert hat, existieren Menüleisten mehrfach oder nur auf dem Hauptbildschirm.

### MacCustomizer-Lösungsansatz:
- **Event-basierte Neukalibrierung:** Überwachung von `NSApplication.didChangeScreenParametersNotification`.
- **Host-Präferenzen:** Nutzen von systemweiten `-currentHost write -globalDomain NSStatusItemSpacing` und `NSStatusItemSelectionPadding`, die Display-unabhängig die native Apple-Menüleisten-Engine steuern, anstatt zerbrechliche Overlay-Tricks zu verwenden.
- **Automatischer ControlCenter-Restart:** Aktualisiert die Menüleisten-Renderer sofort auf allen angeschlossenen Displays.

---

## 4. Meilensteine & Roadmap

| Phase | Fokus | Status |
|---|---|---|
| **Phase 1: Grundlagen & Setup** | • Swift Package Manager Struktur<br>• Git Repository & GitHub CLI Setup (privat)<br>• Modul-Protokoll & Lebenszyklus<br>• App Bundle Packaging Script (`build_app.sh`) | ✅ Abgeschlossen |
| **Phase 2: Menüleisten-Optimizer** | • `NSStatusItemSpacing` Presets & Slider<br>• `DisplayManager` mit Notch-Erkennung<br>• ControlCenter Restart Trigger<br>• Menüleisten-UI & Settings | ✅ Abgeschlossen |
| **Phase 3: Clipboard Manager** | • `NSPasteboard` Überwachung & ChangeCount<br>• Filterung von Passwort-Managern (Transient Types)<br>• JSON-Persistenz im Application Support Verzeichnis<br>• Suchfenster & Pinning | ✅ Abgeschlossen |
| **Phase 4: Erweiterte Menüleisten-Steuerung** | • Verstecken/Ausblenden ungenutzter Icons (Secondary Bar)<br>• Globaler Hotkey / Klick auf Trenn-Icon zum Ein-/Ausklappen | ⏳ Geplant |
| **Phase 5: System Stats & Dashboard** | • Mach Kernel CPU & Speicher-Abfrage<br>• GPU Utilization Abfrage via IOKit/Metal<br>• Miniatur-Graphen direkt im Menüleisten-Item | ⏳ Geplant |
| **Phase 6: Global Shortcuts & Window Tiling** | • Global Hotkey Registration (Carbon Events / CGEventTap)<br>• Tastenkürzel für Clipboard (`Cmd+Shift+V`)<br>• Optional: Window Snapping Shortcuts | ⏳ Geplant |

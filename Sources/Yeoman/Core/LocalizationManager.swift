import SwiftUI
import Combine
import AppKit

public enum AppLanguage: String, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"

    public var id: String { rawValue }

    public var code: String {
        switch self {
        case .german: return "DE"
        case .english: return "EN"
        case .spanish: return "ES"
        case .french: return "FR"
        }
    }

    public var flatFlagImage: NSImage {
        FlatFlagRenderer.flagImage(for: self)
    }

    public func displayName(in language: AppLanguage) -> String {
        switch self {
        case .german:
            return "Deutsch"
        case .english:
            return "English"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        }
    }

    public var nativeName: String {
        displayName(in: self)
    }
}

// MARK: - Clean Flat Flag Vector Graphics
public final class FlatFlagRenderer {
    private static var cache: [String: NSImage] = [:]

    public static func flagImage(for language: AppLanguage, size: CGSize = CGSize(width: 22, height: 15)) -> NSImage {
        let key = "\(language.rawValue)_\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] {
            return cached
        }
        let img = render(language: language, size: size)
        cache[key] = img
        return img
    }

    private static func render(language: AppLanguage, size: CGSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let cornerRadius: CGFloat = 3.0
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.addClip()

            switch language {
            case .german:
                // Germany: 3 equal horizontal stripes (Black, Red, Gold)
                let h = rect.height / 3.0
                NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1.0).setFill()
                NSRect(x: 0, y: 2 * h, width: rect.width, height: h).fill()

                NSColor(srgbRed: 0.86, green: 0.15, blue: 0.15, alpha: 1.0).setFill()
                NSRect(x: 0, y: h, width: rect.width, height: h).fill()

                NSColor(srgbRed: 1.0, green: 0.78, blue: 0.15, alpha: 1.0).setFill()
                NSRect(x: 0, y: 0, width: rect.width, height: h).fill()

            case .english:
                // UK Flag (Union Jack) - clean mathematical geometry
                // 1. Royal Navy Blue field
                NSColor(srgbRed: 0.01, green: 0.14, blue: 0.45, alpha: 1.0).setFill()
                rect.fill()

                let cx = rect.width / 2.0
                let cy = rect.height / 2.0
                let h = rect.height
                let w = rect.width

                // 2. White Saltire (St. Andrew diagonals)
                let whiteDiag = NSBezierPath()
                whiteDiag.lineWidth = round(h * 0.24)
                whiteDiag.lineCapStyle = .square
                whiteDiag.move(to: NSPoint(x: 0, y: 0))
                whiteDiag.line(to: NSPoint(x: w, y: h))
                whiteDiag.move(to: NSPoint(x: 0, y: h))
                whiteDiag.line(to: NSPoint(x: w, y: 0))
                NSColor.white.setStroke()
                whiteDiag.stroke()

                // 3. Red Saltire (St. Patrick rays to center)
                let redDiag = NSBezierPath()
                redDiag.lineWidth = max(1.2, round(h * 0.10))
                redDiag.lineCapStyle = .square
                redDiag.move(to: NSPoint(x: 0, y: 0))
                redDiag.line(to: NSPoint(x: cx, y: cy))
                redDiag.move(to: NSPoint(x: w, y: 0))
                redDiag.line(to: NSPoint(x: cx, y: cy))
                redDiag.move(to: NSPoint(x: 0, y: h))
                redDiag.line(to: NSPoint(x: cx, y: cy))
                redDiag.move(to: NSPoint(x: w, y: h))
                redDiag.line(to: NSPoint(x: cx, y: cy))
                NSColor(srgbRed: 0.82, green: 0.10, blue: 0.15, alpha: 1.0).setStroke()
                redDiag.stroke()

                // 4. White St. George Cross
                let whiteCrossW = round(h * 0.34)
                NSColor.white.setFill()
                NSRect(x: round(cx - whiteCrossW / 2.0), y: 0, width: whiteCrossW, height: h).fill()
                NSRect(x: 0, y: round(cy - whiteCrossW / 2.0), width: w, height: whiteCrossW).fill()

                // 5. Red St. George Cross
                let redCrossW = max(2.0, round(h * 0.20))
                NSColor(srgbRed: 0.82, green: 0.10, blue: 0.15, alpha: 1.0).setFill()
                NSRect(x: round(cx - redCrossW / 2.0), y: 0, width: redCrossW, height: h).fill()
                NSRect(x: 0, y: round(cy - redCrossW / 2.0), width: w, height: redCrossW).fill()

            case .spanish:
                // Spain (La Rojigualda): Red (25%), Yellow (50%), Red (25%)
                let hRed = round(rect.height * 0.25)
                let hYellow = rect.height - (hRed * 2.0)

                // Top Red
                NSColor(srgbRed: 0.80, green: 0.08, blue: 0.15, alpha: 1.0).setFill()
                NSRect(x: 0, y: rect.height - hRed, width: rect.width, height: hRed).fill()

                // Middle Yellow
                NSColor(srgbRed: 1.00, green: 0.77, blue: 0.00, alpha: 1.0).setFill()
                NSRect(x: 0, y: hRed, width: rect.width, height: hYellow).fill()

                // Bottom Red
                NSColor(srgbRed: 0.80, green: 0.08, blue: 0.15, alpha: 1.0).setFill()
                NSRect(x: 0, y: 0, width: rect.width, height: hRed).fill()

                // Stylized Spanish Coat of Arms
                let crestX = round(rect.width * 0.26)
                let crestY = hRed + round(hYellow * 0.10)
                let crestH = round(hYellow * 0.80)
                let crestW = round(crestH * 0.82)

                // Pillars of Hercules
                let pillarW = max(0.8, round(crestW * 0.15))
                let pillarH = crestH * 0.85
                let pillarY = crestY + (crestH - pillarH) / 2.0
                NSColor(srgbRed: 0.75, green: 0.55, blue: 0.10, alpha: 0.9).setFill()
                NSRect(x: crestX - pillarW - 1.2, y: pillarY, width: pillarW, height: pillarH).fill()
                NSRect(x: crestX + crestW + 1.2, y: pillarY, width: pillarW, height: pillarH).fill()

                // Crown on top
                let crownH = round(crestH * 0.28)
                let crownY = crestY + crestH - crownH
                let crown = NSBezierPath()
                crown.move(to: NSPoint(x: crestX, y: crownY))
                crown.line(to: NSPoint(x: crestX, y: crownY + crownH))
                crown.line(to: NSPoint(x: crestX + crestW * 0.5, y: crownY + crownH * 0.4))
                crown.line(to: NSPoint(x: crestX + crestW, y: crownY + crownH))
                crown.line(to: NSPoint(x: crestX + crestW, y: crownY))
                crown.close()
                NSColor(srgbRed: 0.90, green: 0.70, blue: 0.10, alpha: 1.0).setFill()
                crown.fill()

                // Shield
                let shieldH = crestH - crownH - 0.5
                let shieldRect = NSRect(x: crestX, y: crestY, width: crestW, height: shieldH)
                let r = shieldRect.width / 2.0
                let shield = NSBezierPath()
                shield.move(to: NSPoint(x: shieldRect.minX, y: shieldRect.maxY))
                shield.line(to: NSPoint(x: shieldRect.maxX, y: shieldRect.maxY))
                shield.line(to: NSPoint(x: shieldRect.maxX, y: shieldRect.minY + r))
                shield.appendArc(
                    withCenter: NSPoint(x: shieldRect.minX + r, y: shieldRect.minY + r),
                    radius: r,
                    startAngle: 0,
                    endAngle: 180,
                    clockwise: true
                )
                shield.close()
                NSColor(srgbRed: 0.80, green: 0.08, blue: 0.15, alpha: 1.0).setFill()
                shield.fill()

                // Gold inner charge / emblem on shield
                let innerW = shieldRect.width * 0.45
                let innerH = shieldH * 0.45
                let innerRect = NSRect(
                    x: shieldRect.midX - innerW / 2.0,
                    y: shieldRect.midY - innerH / 2.0 + 0.3,
                    width: innerW,
                    height: innerH
                )
                NSColor(srgbRed: 1.00, green: 0.85, blue: 0.20, alpha: 1.0).setFill()
                innerRect.fill()

            case .french:
                // France: 3 equal vertical stripes (Blue, White, Red)
                let w = rect.width / 3.0
                NSColor(srgbRed: 0.08, green: 0.28, blue: 0.72, alpha: 1.0).setFill()
                NSRect(x: 0, y: 0, width: w, height: rect.height).fill()

                NSColor.white.setFill()
                NSRect(x: w, y: 0, width: w, height: rect.height).fill()

                NSColor(srgbRed: 0.90, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
                NSRect(x: 2 * w, y: 0, width: w, height: rect.height).fill()
            }

            // Crisp 0.5pt subtle border for clean contrast on any background
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: cornerRadius, yRadius: cornerRadius)
            border.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.18).setStroke()
            border.stroke()

            return true
        }
        return image
    }
}

public struct FlatFlagView: View {
    public let language: AppLanguage
    public var size: CGSize

    public init(language: AppLanguage, size: CGSize = CGSize(width: 22, height: 15)) {
        self.language = language
        self.size = size
    }

    public var body: some View {
        Image(nsImage: FlatFlagRenderer.flagImage(for: language, size: size))
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
            .overlay(
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 0.5)
    }
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private let storageKey = "app_language"

    /// Resolves the default language matching the macOS system setting.
    /// German for German, Spanish for Spanish, French for French, otherwise English as fallback.
    public static var defaultLanguageForSystem: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let code = preferred.prefix(2).lowercased()
        switch code {
        case "de": return .german
        case "es": return .spanish
        case "fr": return .french
        default: return .english
        }
    }

    @Published public var selectedLanguage: AppLanguage {
        didSet {
            defaults.set(selectedLanguage.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: stored) {
            self.selectedLanguage = lang
        } else {
            self.selectedLanguage = Self.defaultLanguageForSystem
        }
    }

    public var systemLanguage: AppLanguage {
        Self.defaultLanguageForSystem
    }

    public var effectiveLanguage: AppLanguage {
        selectedLanguage
    }

    public func localized(_ key: String, for language: AppLanguage? = nil) -> String {
        let lang = language ?? effectiveLanguage
        if let table = translations[key], let val = table[lang] ?? table[.english] ?? table[.german] {
            return val
        }
        return key
    }

    // MARK: - Translation Dictionary
    private let translations: [String: [AppLanguage: String]] = [
        // Language Display
        "lang.system": [
            .german: "Systemstandard",
            .english: "System Default",
            .spanish: "Predeterminado del sistema",
            .french: "Par défaut du système"
        ],

        // Window Title
        "window.settings_title": [
            .german: "Yeoman Einstellungen",
            .english: "Yeoman Settings",
            .spanish: "Configuración de Yeoman",
            .french: "Paramètres de Yeoman"
        ],

        // Settings Tabs
        "tab.general": [
            .german: "Allgemein",
            .english: "General",
            .spanish: "General",
            .french: "Général"
        ],
        "tab.menuBar": [
            .german: "Menüleiste",
            .english: "Menu Bar",
            .spanish: "Barra de menús",
            .french: "Barre des menus"
        ],
        "tab.scrollReverser": [
            .german: "Scroll-Richtung",
            .english: "Scroll Direction",
            .spanish: "Dirección de desplazamiento",
            .french: "Sens de défilement"
        ],
        "tab.webPanel": [
            .german: "Web-Widgets",
            .english: "Web Widgets",
            .spanish: "Widgets web",
            .french: "Widgets Web"
        ],
        "tab.clipboard": [
            .german: "Zwischenablage",
            .english: "Clipboard",
            .spanish: "Portapapeles",
            .french: "Presse-papiers"
        ],
        "tab.systemStats": [
            .german: "System-Monitor",
            .english: "System Monitor",
            .spanish: "Monitor del sistema",
            .french: "Moniteur système"
        ],
        "tab.about": [
            .german: "Über Yeoman",
            .english: "About Yeoman",
            .spanish: "Acerca de Yeoman",
            .french: "À propos de Yeoman"
        ],

        // General Settings View
        "general.title": [
            .german: "Allgemeine Einstellungen",
            .english: "General Settings",
            .spanish: "Configuración general",
            .french: "Paramètres généraux"
        ],
        "general.subtitle": [
            .german: "Grundkonfiguration für Startverhalten und Systemintegration.",
            .english: "Basic configuration for startup behavior and system integration.",
            .spanish: "Configuración básica para inicio e integración con el sistema.",
            .french: "Configuration de base pour le démarrage et l'intégration système."
        ],
        "general.language_section": [
            .german: "Sprache",
            .english: "Language",
            .spanish: "Idioma",
            .french: "Langue"
        ],
        "general.language_label": [
            .german: "App-Sprache",
            .english: "App Language",
            .spanish: "Idioma de la aplicación",
            .french: "Langue de l'application"
        ],
        "general.language_tooltip": [
            .german: "Wähle zwischen der automatischen Systemsprache oder einer festen Sprache (Deutsch, Englisch, Spanisch, Französisch).",
            .english: "Choose between automatic system language or a fixed language (German, English, Spanish, French).",
            .spanish: "Elige entre el idioma del sistema automático o un idioma fijo (alemán, inglés, español, francés).",
            .french: "Choisissez entre la langue système automatique ou une langue fixe (allemand, anglais, espagnol, français)."
        ],
        "general.startup_appearance": [
            .german: "Start & Darstellung",
            .english: "Startup & Appearance",
            .spanish: "Inicio y apariencia",
            .french: "Démarrage et apparence"
        ],
        "general.launch_at_login": [
            .german: "Beim Mac-Start automatisch öffnen",
            .english: "Launch automatically at Mac startup",
            .spanish: "Abrir automáticamente al iniciar el Mac",
            .french: "Ouvrir automatiquement au démarrage du Mac"
        ],
        "general.launch_at_login_tooltip": [
            .german: "Startet Yeoman automatisch beim Hochfahren deines Macs (Launch at Login).",
            .english: "Starts Yeoman automatically when your Mac boots up (Launch at Login).",
            .spanish: "Inicia Yeoman automáticamente cuando tu Mac se enciende (Launch at Login).",
            .french: "Lance Yeoman automatiquement au démarrage de votre Mac (Launch at Login)."
        ],
        "general.show_dock_icon": [
            .german: "Dock-Symbol anzeigen",
            .english: "Show Dock icon",
            .spanish: "Mostrar icono en el Dock",
            .french: "Afficher l'icône dans le Dock"
        ],
        "general.show_dock_icon_tooltip": [
            .german: "Bestimmt, ob Yeoman im Dock sichtbar ist. Wenn deaktiviert, läuft die App rein in der Menüleiste.",
            .english: "Determines whether Yeoman is visible in the Dock. When disabled, the app runs purely in the menu bar.",
            .spanish: "Determina si Yeoman es visible en el Dock. Si se desactiva, la aplicación solo se ejecuta en la barra de menús.",
            .french: "Détermine si Yeoman est visible dans le Dock. Si désactivé, l'application fonctionne uniquement dans la barre des menus."
        ],
        "general.show_main_status_item": [
            .german: "Haupt-Symbol in der Menüleiste anzeigen",
            .english: "Show main icon in menu bar",
            .spanish: "Mostrar icono principal en la barra de menús",
            .french: "Afficher l'icône principale dans la barre des menus"
        ],
        "general.show_main_status_item_tooltip": [
            .german: "Zeigt das Yeoman Hauptsymbol (Launcher) in der Menüleiste an, über das du schnellen Zugriff auf alle Module hast.",
            .english: "Shows the Yeoman main launcher icon in the menu bar for quick access to all modules.",
            .spanish: "Muestra el icono principal de Yeoman en la barra de menús para acceder rápidamente a todos los módulos.",
            .french: "Affiche l'icône principale de Yeoman dans la barre des menus pour un accès rapide à tous les modules."
        ],
        "general.active_modules": [
            .german: "Aktive Module",
            .english: "Active Modules",
            .spanish: "Módulos activos",
            .french: "Modules actifs"
        ],
        "general.menu_bar_opt_title": [
            .german: "Menüleisten-Optimizer",
            .english: "Menu Bar Optimizer",
            .spanish: "Optimizador de barra de menús",
            .french: "Optimiseur de barre des menus"
        ],
        "general.menu_bar_opt_sub": [
            .german: "Icon-Abstand und Menüleisten-Konfiguration",
            .english: "Icon spacing and menu bar configuration",
            .spanish: "Espaciado de iconos y configuración de la barra de menús",
            .french: "Espacement des icônes et configuration de la barre des menus"
        ],
        "general.scroll_reverser_title": [
            .german: "Scroll-Richtung (Maus)",
            .english: "Scroll Direction (Mouse)",
            .spanish: "Dirección de desplazamiento (Ratón)",
            .french: "Sens de défilement (Souris)"
        ],
        "general.scroll_reverser_sub": [
            .german: "Kehrt die Scrollrichtung der Maus um, während das Trackpad unverändert bleibt",
            .english: "Inverts mouse scroll direction while keeping trackpad scrolling natural",
            .spanish: "Invierte la dirección del ratón manteniendo el trackpad natural",
            .french: "Inverse le sens de défilement de la souris tout en conservant le trackpad naturel"
        ],
        "general.web_panel_title": [
            .german: "Web-Widgets (Popups)",
            .english: "Web Widgets (Popups)",
            .spanish: "Widgets web (Ventanas emergentes)",
            .french: "Widgets Web (Popups)"
        ],
        "general.web_panel_sub": [
            .german: "Schnellzugriff auf Webseiten wie Kalender oder Notizen direkt aus der Menüleiste",
            .english: "Quick access to websites like calendar or notes directly from the menu bar",
            .spanish: "Acceso rápido a sitios web como calendarios o notas directamente desde la barra de menús",
            .french: "Accès rapide aux sites Web comme calendriers ou notes directement depuis la barre des menus"
        ],
        "general.clipboard_title": [
            .german: "Zwischenablage-Manager",
            .english: "Clipboard Manager",
            .spanish: "Gestor de portapapeles",
            .french: "Gestionnaire de presse-papiers"
        ],
        "general.clipboard_sub": [
            .german: "Erfasst kopierte Texte und Bilder mit Suchfunktion und Schnellzugriff per Menüleiste",
            .english: "Captures copied texts and images with search and quick menu bar access",
            .spanish: "Captura textos e imágenes copiados con búsqueda y acceso rápido en la barra de menús",
            .french: "Capture les textes et images copiés avec recherche et accès rapide dans la barre des menus"
        ],
        "general.system_stats_title": [
            .german: "System-Monitor",
            .english: "System Monitor",
            .spanish: "Monitor del sistema",
            .french: "Moniteur système"
        ],
        "general.system_stats_sub": [
            .german: "Live-Auslastung von CPU, RAM und GPU direkt in der Menüleiste",
            .english: "Live monitoring of CPU, RAM, and GPU directly in the menu bar",
            .spanish: "Supervisión en tiempo real de CPU, RAM y GPU directamente en la barra de menús",
            .french: "Surveillance en temps réel du processeur, de la mémoire et du GPU dans la barre des menus"
        ],
        "general.status_icon_label": [
            .german: "Symbol in Menüleiste anzeigen",
            .english: "Show icon in menu bar",
            .spanish: "Mostrar icono en la barra de menús",
            .french: "Afficher l'icône dans la barre des menus"
        ],

        // Menu Bar Menu
        "menu.settings": [
            .german: "Einstellungen...",
            .english: "Settings...",
            .spanish: "Configuración...",
            .french: "Paramètres..."
        ],
        "menu.check_updates": [
            .german: "Nach Updates suchen...",
            .english: "Check for Updates...",
            .spanish: "Buscar actualizaciones...",
            .french: "Rechercher des mises à jour..."
        ],
        "menu.quit": [
            .german: "Yeoman beenden",
            .english: "Quit Yeoman",
            .spanish: "Salir de Yeoman",
            .french: "Quitter Yeoman"
        ],
        "menu.clipboard_recent": [
            .german: "Neueste Zwischenablage",
            .english: "Recent Clipboard",
            .spanish: "Portapapeles reciente",
            .french: "Presse-papiers récent"
        ],
        "menu.clipboard_search": [
            .german: "Verlauf durchsuchen...",
            .english: "Search History...",
            .spanish: "Buscar en el historial...",
            .french: "Rechercher dans l'historique..."
        ],
        "menu.empty": [
            .german: "(Keine Einträge)",
            .english: "(No entries)",
            .spanish: "(Sin entradas)",
            .french: "(Aucune entrée)"
        ],
        "menu.clear_all": [
            .german: "Verlauf leeren",
            .english: "Clear History",
            .spanish: "Borrar historial",
            .french: "Effacer l'historique"
        ],

        // Update Manager
        "updates.title": [
            .german: "Software-Aktualisierung",
            .english: "Software Update",
            .spanish: "Actualización de software",
            .french: "Mise à jour logicielle"
        ],
        "updates.auto_check": [
            .german: "Automatisch nach Updates suchen",
            .english: "Check for updates automatically",
            .spanish: "Buscar actualizaciones automáticamente",
            .french: "Rechercher automatiquement les mises à jour"
        ],
        "updates.auto_check_tooltip": [
            .german: "Sucht im Hintergrund regelmäßig auf GitHub nach neuen Versionen und informiert dich, sobald ein Update bereitsteht.",
            .english: "Periodically checks GitHub in the background for new releases and notifies you when an update is available.",
            .spanish: "Busca periódicamente nuevas versiones en GitHub en segundo plano y te notifica cuando haya una actualización disponible.",
            .french: "Recherche régulièrement de nouvelles versions sur GitHub en arrière-plan et vous avertit lorsqu'une mise à jour est disponible."
        ],
        "updates.current_version": [
            .german: "Installierte Version:",
            .english: "Installed Version:",
            .spanish: "Versión instalada:",
            .french: "Version installée :"
        ],
        "updates.check_button": [
            .german: "Jetzt suchen",
            .english: "Check Now",
            .spanish: "Buscar ahora",
            .french: "Vérifier maintenant"
        ],
        "updates.install_button": [
            .german: "Jetzt installieren & neu starten",
            .english: "Install Now & Relaunch",
            .spanish: "Instalar ahora y reiniciar",
            .french: "Installer maintenant et redémarrer"
        ],
        "updates.popup_title": [
            .german: "Neues Update verfügbar",
            .english: "New Update Available",
            .spanish: "Nueva actualización disponible",
            .french: "Nouvelle mise à jour disponible"
        ],
        "updates.popup_subtitle": [
            .german: "Ein neues Update für Yeoman steht bereit.",
            .english: "A new update for Yeoman is available.",
            .spanish: "Una nueva actualización para Yeoman está disponible.",
            .french: "Une nouvelle mise à jour pour Yeoman est disponible."
        ],
        "updates.ignore_button": [
            .german: "Ignorieren",
            .english: "Ignore",
            .spanish: "Ignorar",
            .french: "Ignorer"
        ],
        "updates.remind_later": [
            .german: "Später",
            .english: "Later",
            .spanish: "Más tarde",
            .french: "Plus tard"
        ],
        "updates.up_to_date": [
            .german: "Yeoman ist auf dem neuesten Stand",
            .english: "Yeoman is up to date",
            .spanish: "Yeoman está actualizado",
            .french: "Yeoman est à jour"
        ],
        "updates.available": [
            .german: "Neue Version verfügbar:",
            .english: "New version available:",
            .spanish: "Nueva versión disponible:",
            .french: "Nouvelle version disponible :"
        ],
        "updates.last_checked": [
            .german: "Zuletzt gesucht:",
            .english: "Last checked:",
            .spanish: "Última búsqueda:",
            .french: "Dernière vérification :"
        ],
        "updates.never_checked": [
            .german: "Noch nie",
            .english: "Never",
            .spanish: "Nunca",
            .french: "Jamais"
        ],
        "updates.checking": [
            .german: "Suche nach Updates...",
            .english: "Checking for updates...",
            .spanish: "Buscando actualizaciones...",
            .french: "Recherche de mises à jour..."
        ],
        "updates.downloading": [
            .german: "Update wird geladen...",
            .english: "Downloading update...",
            .spanish: "Descargando actualización...",
            .french: "Téléchargement de la mise à jour..."
        ],
        "updates.release_notes": [
            .german: "Änderungsprotokoll (Release Notes):",
            .english: "Release Notes:",
            .spanish: "Notas de la versión:",
            .french: "Notes de version :"
        ],
        "updates.view_on_github": [
            .german: "Auf GitHub ansehen",
            .english: "View on GitHub",
            .spanish: "Ver en GitHub",
            .french: "Voir sur GitHub"
        ],
        "updates.badge_current": [
            .german: "Aktuell",
            .english: "Current",
            .spanish: "Actual",
            .french: "À jour"
        ],
        "updates.badge_new": [
            .german: "Neu",
            .english: "New",
            .spanish: "Nuevo",
            .french: "Nouveau"
        ],
        "updates.error_invalid_response": [
            .german: "Ungültige oder unerwartete Update-Antwort vom Server.",
            .english: "Invalid or unexpected update response from server.",
            .spanish: "Respuesta de actualización no válida o inesperada del servidor.",
            .french: "Réponse de mise à jour non valide ou inattendue du serveur."
        ],
        "updates.error_not_found_or_private": [
            .german: "Kein Update gefunden oder Repository ist privat (HTTP 404).",
            .english: "No update found or repository is private (HTTP 404).",
            .spanish: "No se encontró ninguna actualización o el repositorio es privado (HTTP 404).",
            .french: "Aucune mise à jour trouvée ou le dépôt est privé (HTTP 404)."
        ],
        "updates.error_forbidden": [
            .german: "GitHub-Zugriff verweigert oder Rate-Limit erreicht (HTTP 403).",
            .english: "GitHub access denied or rate limit exceeded (HTTP 403).",
            .spanish: "Acceso a GitHub denegado o límite de tasa excedido (HTTP 403).",
            .french: "Accès à GitHub refusé ou limite de taux dépassée (HTTP 403)."
        ],
        "updates.error_invalid_version": [
            .german: "Ungültige Versionsnummer im Release.",
            .english: "Invalid version number in release.",
            .spanish: "Número de versión no válido en la versión publicada.",
            .french: "Numéro de version non valide dans la version publiée."
        ],
        "updates.error_redirect_rejected": [
            .german: "Update-Weiterleitung aus Sicherheitsgründen abgewiesen.",
            .english: "Update redirect rejected for security reasons.",
            .spanish: "Redirección de actualización rechazada por seguridad.",
            .french: "Redirection de mise à jour rejetée pour des raisons de sécurité."
        ],
        "updates.error_archive_tampered": [
            .german: "Update-Archiv wurde verändert oder ist beschädigt.",
            .english: "Update archive was modified or is corrupt.",
            .spanish: "El archivo de actualización fue modificado o está dañado.",
            .french: "L'archive de mise à jour a été modifiée ou est corrompue."
        ],
        "updates.error_integrity_failed": [
            .german: "Integritätsprüfung der App-Signatur fehlgeschlagen.",
            .english: "App signature integrity verification failed.",
            .spanish: "Error en la verificación de integridad de la firma.",
            .french: "Échec de la vérification de l'intégrité de la signature."
        ],
        "updates.error_network": [
            .german: "Verbindung zu GitHub fehlgeschlagen. Bitte Internetverbindung prüfen.",
            .english: "Connection to GitHub failed. Please check your internet connection.",
            .spanish: "Error al conectar con GitHub. Compruebe la conexión a Internet.",
            .french: "Échec de connexion à GitHub. Veuillez vérifier votre connexion Internet."
        ],

        // Menu Bar Optimizer
        "menubar.title": [
            .german: "Menüleisten-Optimizer",
            .english: "Menu Bar Optimizer",
            .spanish: "Optimizador de barra de menús",
            .french: "Optimiseur de barre des menus"
        ],
        "menubar.subtitle": [
            .german: "Passe die Abstände zwischen den Menüleisten-Symbolen an, um Platz zu sparen.",
            .english: "Adjust spacing between menu bar icons to save space.",
            .spanish: "Ajusta el espaciado entre los iconos de la barra de menús para ahorrar espacio.",
            .french: "Ajustez l'espacement entre les icônes de la barre des menus pour gagner de la place."
        ],
        "menubar.status_item_toggle": [
            .german: "Eigenes Menüleisten-Widget für Schnell-Presets anzeigen",
            .english: "Show dedicated menu bar widget for quick presets",
            .spanish: "Mostrar widget dedicado en la barra de menús para ajustes rápidos",
            .french: "Afficher le widget dédié dans la barre des menus pour préréglages rapides"
        ],
        "menubar.spacing_section": [
            .german: "Menüleisten-Abstände anpassen",
            .english: "Adjust Menu Bar Spacing",
            .spanish: "Ajustar espaciado de la barra de menús",
            .french: "Ajuster l'espacement de la barre des menus"
        ],
        "menubar.spacing_slider": [
            .german: "Symbol-Abstand (NSStatusItemSpacing)",
            .english: "Icon Spacing (NSStatusItemSpacing)",
            .spanish: "Espaciado de iconos (NSStatusItemSpacing)",
            .french: "Espacement des icônes (NSStatusItemSpacing)"
        ],
        "menubar.padding_slider": [
            .german: "Auswahl-Polsterung (NSStatusItemSelectionPadding)",
            .english: "Selection Padding (NSStatusItemSelectionPadding)",
            .spanish: "Relleno de selección (NSStatusItemSelectionPadding)",
            .french: "Rembourrage de sélection (NSStatusItemSelectionPadding)"
        ],
        "menubar.preset_standard": [
            .german: "Standard",
            .english: "Standard",
            .spanish: "Estándar",
            .french: "Standard"
        ],
        "menubar.preset_compact": [
            .german: "Kompakt",
            .english: "Compact",
            .spanish: "Compacto",
            .french: "Compact"
        ],
        "menubar.preset_ultra_compact": [
            .german: "Ultra-Kompakt",
            .english: "Ultra-Compact",
            .spanish: "Ultra compacto",
            .french: "Ultra-compact"
        ],
        "menubar.preset_zero": [
            .german: "Kein Abstand",
            .english: "Zero Spacing",
            .spanish: "Sin espacio",
            .french: "Sans espacement"
        ],
        "menubar.restart_cc": [
            .german: "Menüleiste jetzt aktualisieren",
            .english: "Update Menu Bar Now",
            .spanish: "Actualizar barra de menús ahora",
            .french: "Actualiser la barre des menus maintenant"
        ],
        "menubar.reset_defaults": [
            .german: "Auf Standard zurücksetzen",
            .english: "Reset to Defaults",
            .spanish: "Restablecer valores predeterminados",
            .french: "Rétablir les paramètres par défaut"
        ],

        // Clipboard View
        "clipboard.search": [
            .german: "Zwischenablage durchsuchen...",
            .english: "Search clipboard...",
            .spanish: "Buscar en el portapapeles...",
            .french: "Rechercher dans le presse-papiers..."
        ],
        "clipboard.all": [
            .german: "Alle",
            .english: "All",
            .spanish: "Todo",
            .french: "Tout"
        ],
        "clipboard.texts": [
            .german: "Texte",
            .english: "Text",
            .spanish: "Texto",
            .french: "Texte"
        ],
        "clipboard.images": [
            .german: "Bilder",
            .english: "Images",
            .spanish: "Imágenes",
            .french: "Images"
        ],
        "clipboard.favorites": [
            .german: "Favoriten",
            .english: "Favorites",
            .spanish: "Favoritos",
            .french: "Favoris"
        ],
        "clipboard.copied": [
            .german: "Kopiert!",
            .english: "Copied!",
            .spanish: "¡Copiado!",
            .french: "Copié !"
        ],
        "clipboard.footer_hint": [
            .german: "Klick zum Kopieren in Zwischenablage",
            .english: "Click to copy to clipboard",
            .spanish: "Clic para copiar al portapapeles",
            .french: "Cliquer pour copier dans le presse-papiers"
        ],
        "common.pin_window": [
            .german: "Fenster anpinnen",
            .english: "Pin window",
            .spanish: "Fijar ventana",
            .french: "Épingler la fenêtre"
        ],
        "common.unpin_window": [
            .german: "Fenster lösen",
            .english: "Unpin window",
            .spanish: "Desfijar ventana",
            .french: "Désépingler la fenêtre"
        ],
        "common.keep_window_pinned": [
            .german: "Fenster angepinnt lassen",
            .english: "Keep window pinned",
            .spanish: "Mantener la ventana fijada",
            .french: "Garder la fenêtre épinglée"
        ],
        "clipboard.clear_unpinned": [
            .german: "Nicht angepinnte löschen",
            .english: "Clear unpinned items",
            .spanish: "Borrar elementos no fijados",
            .french: "Effacer les éléments non épinglés"
        ],
        "clipboard.clear_all": [
            .german: "Gesamten Verlauf löschen",
            .english: "Clear entire history",
            .spanish: "Borrar todo el historial",
            .french: "Effacer tout l'historique"
        ],
        "clipboard.zoom": [
            .german: "Vergrößern",
            .english: "Zoom",
            .spanish: "Ampliar",
            .french: "Agrandir"
        ],
        "clipboard.pin": [
            .german: "Anpinnen",
            .english: "Pin",
            .spanish: "Fijar",
            .french: "Épingler"
        ],
        "clipboard.unpin": [
            .german: "Lösen",
            .english: "Unpin",
            .spanish: "Desfijar",
            .french: "Détacher"
        ],
        "clipboard.delete": [
            .german: "Löschen",
            .english: "Delete",
            .spanish: "Eliminar",
            .french: "Supprimer"
        ],
        "clipboard.characters": [
            .german: "Zeichen",
            .english: "chars",
            .spanish: "caracteres",
            .french: "caractères"
        ],
        "clipboard.items_count_format": [
            .german: "%d von %d Einträgen",
            .english: "%d of %d items",
            .spanish: "%d de %d elementos",
            .french: "%d sur %d éléments"
        ],
        "clipboard.empty_images_title": [
            .german: "Keine Bilder im Zwischenspeicher",
            .english: "No images in clipboard",
            .spanish: "No hay imágenes en el portapapeles",
            .french: "Aucune image dans le presse-papiers"
        ],
        "clipboard.empty_images_sub": [
            .german: "Kopiere ein Bild im Browser, erstelle einen Screenshot oder kopiere eine Bilddatei im Finder – sie erscheint sofort hier.",
            .english: "Copy an image in the browser, take a screenshot, or copy an image file in Finder – it will appear here instantly.",
            .spanish: "Copia una imagen en el navegador, haz una captura o copia un archivo de imagen en Finder: aparecerá aquí al instante.",
            .french: "Copiez une image dans le navigateur, faites une capture d'écran ou copiez un fichier image dans le Finder : elle apparaîtra instantanément ici."
        ],
        "clipboard.empty_pinned_title": [
            .german: "Keine Favoriten vorhanden",
            .english: "No favorites saved",
            .spanish: "No hay favoritos guardados",
            .french: "Aucun favori enregistré"
        ],
        "clipboard.empty_pinned_sub": [
            .german: "Bewege die Maus über einen Eintrag und klicke auf das Pin-Symbol, um ihn dauerhaft oben zu behalten.",
            .english: "Hover over an entry and click the pin icon to keep it pinned at the top.",
            .spanish: "Pasa el ratón sobre un elemento y haz clic en el icono de chincheta para mantenerlo fijado arriba.",
            .french: "Survolez un élément et cliquez sur l'épingle pour le garder en haut."
        ],
        "clipboard.empty_history_title": [
            .german: "Zwischenablage ist leer",
            .english: "Clipboard is empty",
            .spanish: "El portapapeles está vacío",
            .french: "Le presse-papiers est vide"
        ],
        "clipboard.empty_no_results": [
            .german: "Keine Treffer gefunden",
            .english: "No results found",
            .spanish: "No se encontraron resultados",
            .french: "Aucun résultat trouvé"
        ],
        "clipboard.empty_history_sub": [
            .german: "Kopierte Texte, Links und Bilder werden hier automatisch erfasst.",
            .english: "Copied text, links, and images will be captured here automatically.",
            .spanish: "Los textos, enlaces e imágenes copiados se guardarán aquí automáticamente.",
            .french: "Les textes, liens et images copiés seront automatiquement enregistrés ici."
        ],

        // Common
        "common.enabled": [
            .german: "Aktiviert",
            .english: "Enabled",
            .spanish: "Activado",
            .french: "Activé"
        ],
        "common.disabled": [
            .german: "Deaktiviert",
            .english: "Disabled",
            .spanish: "Desactivado",
            .french: "Désactivé"
        ],
        "common.close": [
            .german: "Schließen",
            .english: "Close",
            .spanish: "Cerrar",
            .french: "Fermer"
        ],
        "common.cancel": [
            .german: "Abbrechen",
            .english: "Cancel",
            .spanish: "Cancelar",
            .french: "Annuler"
        ],
        "common.save": [
            .german: "Speichern",
            .english: "Save",
            .spanish: "Guardar",
            .french: "Enregistrer"
        ],
        "common.delete": [
            .german: "Löschen",
            .english: "Delete",
            .spanish: "Eliminar",
            .french: "Supprimer"
        ],
        "common.done": [
            .german: "Fertig",
            .english: "Done",
            .spanish: "Listo",
            .french: "Terminé"
        ],
        "common.edit": [
            .german: "Bearbeiten",
            .english: "Edit",
            .spanish: "Editar",
            .french: "Modifier"
        ],
        "common.open": [
            .german: "Öffnen",
            .english: "Open",
            .spanish: "Abrir",
            .french: "Ouvrir"
        ],
        "module.disabled_hint": [
            .german: "Dieses Modul ist deaktiviert. Aktiviere den Schalter oben rechts, um es einzuschalten.",
            .english: "This module is disabled. Turn on the switch in the top right to enable it.",
            .spanish: "Este módulo está desactivado. Activa el interruptor en la esquina superior derecha para habilitarlo.",
            .french: "Ce module est désactivé. Activez l'interrupteur en haut à droite pour l'activer."
        ],

        // About View
        "about.tagline": [
            .german: "Die modulare All-in-One Steuerzentrale für deine macOS Anpassungen.",
            .english: "The modular all-in-one control center for your macOS customizations.",
            .spanish: "El centro de control modular todo en uno para tus personalizaciones de macOS.",
            .french: "Le centre de contrôle modulaire tout-en-un pour vos personnalisations macOS."
        ],
        "about.developed_for": [
            .german: "Entwickelt für macOS mit Swift & SwiftUI",
            .english: "Developed for macOS with Swift & SwiftUI",
            .spanish: "Desarrollado para macOS con Swift y SwiftUI",
            .french: "Développé pour macOS avec Swift & SwiftUI"
        ],
        "about.github_repo": [
            .german: "GitHub Repository",
            .english: "GitHub Repository",
            .spanish: "Repositorio GitHub",
            .french: "Dépôt GitHub"
        ],
        "about.releases_changelog": [
            .german: "Releases & Changelog",
            .english: "Releases & Changelog",
            .spanish: "Versiones y registro de cambios",
            .french: "Versions et journal des modifications"
        ],
        "about.language_title": [
            .german: "Sprache",
            .english: "Language",
            .spanish: "Idioma",
            .french: "Langue"
        ],
        "about.language_subtitle": [
            .german: "Wähle deine bevorzugte Sprache für die Benutzeroberfläche.",
            .english: "Choose your preferred interface language.",
            .spanish: "Elige tu idioma preferido para la interfaz.",
            .french: "Choisissez votre langue préférée pour l'interface."
        ],
        "about.lang_system_desc": [
            .german: "Verwendet automatisch die macOS-Systemsprache",
            .english: "Automatically uses macOS system language",
            .spanish: "Utiliza automáticamente el idioma del sistema macOS",
            .french: "Utilise automatiquement la langue du système macOS"
        ],

        // Menu Bar Sub-Tabs
        "menubar.tab_items": [
            .german: "Symbole & Sichtbarkeit",
            .english: "Icons & Visibility",
            .spanish: "Iconos y visibilidad",
            .french: "Icônes et visibilité"
        ],
        "menubar.tab_spacing": [
            .german: "Symbol-Abstände",
            .english: "Icon Spacing",
            .spanish: "Espaciado de iconos",
            .french: "Espacement des icônes"
        ],

        // Scroll Reverser
        "scroll_reverser.title": [
            .german: "Scroll-Richtung (Maus)",
            .english: "Scroll Direction (Mouse)",
            .spanish: "Dirección de desplazamiento (Ratón)",
            .french: "Sens de défilement (Souris)"
        ],
        "scroll_reverser.subtitle": [
            .german: "Kehrt die Scrollrichtung der Maus um, während das Trackpad unverändert bleibt.",
            .english: "Inverts mouse scroll direction while keeping trackpad scrolling natural.",
            .spanish: "Invierte la dirección del ratón manteniendo el trackpad natural.",
            .french: "Inverse le sens de défilement de la souris tout en conservant le trackpad naturel."
        ],
        "scroll_reverser.mouse_header": [
            .german: "Maus (Klassisches Scrollrad)",
            .english: "Mouse (Classic Scroll Wheel)",
            .spanish: "Ratón (Rueda de desplazamiento clásica)",
            .french: "Souris (Molette de défilement classique)"
        ],
        "scroll_reverser.mouse_tooltip": [
            .german: "Gilt für herkömmliche USB-, Funk- und Bluetooth-Mäuse mit physischem Scrollrad.",
            .english: "Applies to standard USB, wireless, and Bluetooth mice with a physical scroll wheel.",
            .spanish: "Se aplica a ratones estándar USB, inalámbricos y Bluetooth con rueda física.",
            .french: "S'applique aux souris standard USB, sans fil et Bluetooth avec molette physique."
        ],
        "scroll_reverser.trackpad_header": [
            .german: "Trackpad",
            .english: "Trackpad",
            .spanish: "Trackpad",
            .french: "Trackpad"
        ],
        "scroll_reverser.trackpad_tooltip": [
            .german: "Gilt für das integrierte MacBook-Trackpad und Apple Magic Trackpad.",
            .english: "Applies to built-in MacBook trackpads and Apple Magic Trackpads.",
            .spanish: "Se aplica al trackpad integrado de MacBook y al Apple Magic Trackpad.",
            .french: "S'applique au trackpad intégré du MacBook et à l'Apple Magic Trackpad."
        ],
        "scroll_reverser.reverse_vertical": [
            .german: "Vertikales Scrollen umkehren",
            .english: "Reverse vertical scrolling",
            .spanish: "Invertir desplazamiento vertical",
            .french: "Inverser le défilement vertical"
        ],
        "scroll_reverser.reverse_horizontal": [
            .german: "Horizontales Scrollen umkehren",
            .english: "Reverse horizontal scrolling",
            .spanish: "Invertir desplazamiento horizontal",
            .french: "Inverser le défilement horizontal"
        ],

        // System Stats
        "system_stats.title": [
            .german: "System-Monitor",
            .english: "System Monitor",
            .spanish: "Monitor del sistema",
            .french: "Moniteur système"
        ],
        "system_stats.subtitle": [
            .german: "Live-Auslastung von Prozessor, Arbeitsspeicher und Grafik in der Menüleiste.",
            .english: "Live monitoring of processor, memory, and graphics in the menu bar.",
            .spanish: "Supervisión en tiempo real del procesador, la memoria y los gráficos en la barra de menús.",
            .french: "Surveillance en temps réel du processeur, de la mémoire et des graphiques dans la barre des menus."
        ],

        // Web Panel (full page & editor)
        "web_panel.title": [
            .german: "Web-Widgets",
            .english: "Web Widgets",
            .spanish: "Widgets web",
            .french: "Widgets Web"
        ],
        "web_panel.subtitle": [
            .german: "Web-Apps direkt als Menüleisten-Symbole mit Live-Fenster nutzen.",
            .english: "Use web apps directly as menu bar icons with a live window.",
            .spanish: "Usa aplicaciones web directamente como iconos en la barra de menús con ventana interactiva.",
            .french: "Utilisez des applications Web directement comme icônes de barre de menus avec fenêtre dynamique."
        ],
        "web_panel.status_count": [
            .german: "%d Web-Widget(s) eingerichtet • %d aktiv in der Menüleiste",
            .english: "%d web widget(s) configured • %d active in menu bar",
            .spanish: "%d widget(s) web configurado(s) • %d activo(s) en la barra de menús",
            .french: "%d widget(s) Web configuré(s) • %d actif(s) dans la barre des menus"
        ],
        "web_panel.add_button": [
            .german: "Neues Web-Widget hinzufügen",
            .english: "Add New Web Widget",
            .spanish: "Añadir nuevo widget web",
            .french: "Ajouter un nouveau widget Web"
        ],
        "web_panel.active_widgets": [
            .german: "Deine aktiven Web-Widgets",
            .english: "Your Active Web Widgets",
            .spanish: "Tus widgets web activos",
            .french: "Vos widgets Web actifs"
        ],
        "web_panel.empty_title": [
            .german: "Noch keine Web-Widgets erstellt",
            .english: "No web widgets created yet",
            .spanish: "Aún no se han creado widgets web",
            .french: "Aucun widget Web créé pour le moment"
        ],
        "web_panel.empty_subtitle": [
            .german: "Klicke auf den Button oben, um dein erstes Web-Widget anzulegen.",
            .english: "Click the button above to create your first web widget.",
            .spanish: "Haz clic en el botón de arriba para crear tu primer widget web.",
            .french: "Cliquez sur le bouton ci-dessus pour créer votre premier widget Web."
        ],
        "web_panel.btn_open": [
            .german: "Öffnen",
            .english: "Open",
            .spanish: "Abrir",
            .french: "Ouvrir"
        ],
        "web_panel.btn_icon": [
            .german: "Icon",
            .english: "Icon",
            .spanish: "Icono",
            .french: "Icône"
        ],
        "web_panel.btn_edit": [
            .german: "Bearbeiten",
            .english: "Edit",
            .spanish: "Editar",
            .french: "Modifier"
        ],
        "web_panel.menubar_label": [
            .german: "Menüleiste",
            .english: "Menu Bar",
            .spanish: "Barra de menús",
            .french: "Barre des menus"
        ],
        "web_panel.badge_web_icon": [
            .german: "Web-Icon",
            .english: "Web Icon",
            .spanish: "Icono web",
            .french: "Icône Web"
        ],
        "web_panel.badge_symbol": [
            .german: "Symbol",
            .english: "Symbol",
            .spanish: "Símbolo",
            .french: "Symbole"
        ],
        "web_panel.badge_smartphone": [
            .german: "Smartphone",
            .english: "Smartphone",
            .spanish: "Móvil",
            .french: "Mobile"
        ],
        "web_panel.cache_title": [
            .german: "Sitzungen & Cache",
            .english: "Sessions & Cache",
            .spanish: "Sesiones y caché",
            .french: "Sessions et cache"
        ],
        "web_panel.cache_tooltip": [
            .german: "Löscht Cookies, Local Storage und temporäre WebKit-Caches aller Web-Widgets. Du wirst danach auf Webseiten abgemeldet.",
            .english: "Clears cookies, local storage, and temporary WebKit caches for all web widgets. You will be logged out of websites.",
            .spanish: "Borra cookies, almacenamiento local y caché temporal de WebKit de todos los widgets web. Se cerrará tu sesión en los sitios web.",
            .french: "Efface les cookies, le stockage local et les caches WebKit temporaires de tous les widgets Web. Vous serez déconnecté des sites Web."
        ],
        "web_panel.cache_clear_btn": [
            .german: "Alle Cache- und Website-Daten löschen",
            .english: "Clear All Cache & Website Data",
            .spanish: "Borrar toda la caché y datos de sitios web",
            .french: "Effacer toutes les données de cache et de sites Web"
        ],
        "web_panel.cache_alert_title": [
            .german: "Alle Web-Daten löschen?",
            .english: "Clear all web data?",
            .spanish: "¿Borrar todos los datos web?",
            .french: "Effacer toutes les données Web ?"
        ],
        "web_panel.cache_alert_message": [
            .german: "Dies meldet dich von allen Webseiten ab und löscht gespeicherte Browserdaten aller Widgets.",
            .english: "This will log you out of all websites and delete stored browsing data for all widgets.",
            .spanish: "Esto cerrará tu sesión en todos los sitios web y eliminará los datos de navegación almacenados de todos los widgets.",
            .french: "Cela vous déconnectera de tous les sites Web et supprimera les données de navigation stockées pour tous les widgets."
        ],
        "web_panel.delete_alert_title": [
            .german: "Web-Widget löschen?",
            .english: "Delete Web Widget?",
            .spanish: "¿Eliminar widget web?",
            .french: "Supprimer le widget Web ?"
        ],
        "web_panel.delete_alert_message": [
            .german: "Möchtest du das Web-Widget „%@“ wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.",
            .english: "Are you sure you want to delete the web widget \"%@\"? This action cannot be undone.",
            .spanish: "¿Seguro que deseas eliminar el widget web \"%@\"? Esta acción no se puede deshacer.",
            .french: "Voulez-vous vraiment supprimer le widget Web « %@ » ? Cette action est irréversible."
        ],
        "web_panel.logo_picker_title": [
            .german: "Symbol & Logo wählen",
            .english: "Choose Symbol & Logo",
            .spanish: "Elegir símbolo y logotipo",
            .french: "Choisir un symbole et un logo"
        ],
        "web_panel.logo_picker_auto": [
            .german: "Favicon der Webseite automatisch als Icon nutzen",
            .english: "Automatically use website favicon as icon",
            .spanish: "Usar automáticamente el favicon del sitio web como icono",
            .french: "Utiliser automatiquement le favicon du site comme icône"
        ],
        "web_panel.logo_picker_transparent": [
            .german: "Weißen Hintergrund bei Favicons transparent machen",
            .english: "Make white background in favicons transparent",
            .spanish: "Hacer transparente el fondo blanco en los favicons",
            .french: "Rendre le fond blanc des favicons transparent"
        ],
        "web_panel.logo_picker_available": [
            .german: "Verfügbare Logos (%d):",
            .english: "Available logos (%d):",
            .spanish: "Logotipos disponibles (%d):",
            .french: "Logos disponibles (%d) :"
        ],
        "web_panel.logo_picker_symbols": [
            .german: "Oder wähle ein System-Symbol:",
            .english: "Or choose a system symbol:",
            .spanish: "O elige un símbolo del sistema:",
            .french: "Ou choisissez un symbole système :"
        ],
        "web_panel.editor_edit_title": [
            .german: "Web-Widget bearbeiten",
            .english: "Edit Web Widget",
            .spanish: "Editar widget web",
            .french: "Modifier le widget Web"
        ],
        "web_panel.editor_new_title": [
            .german: "Neues Web-Widget anlegen",
            .english: "Create New Web Widget",
            .spanish: "Crear nuevo widget web",
            .french: "Créer un nouveau widget Web"
        ],
        "web_panel.editor_subtitle": [
            .german: "Passe Namen, URL, Icon und Fenstergröße an.",
            .english: "Customize name, URL, icon, and window dimensions.",
            .spanish: "Personaliza el nombre, URL, icono y tamaño de ventana.",
            .french: "Personnalisez le nom, l'URL, l'icône et la taille de la fenêtre."
        ],
        "web_panel.editor_sec1": [
            .german: "Name & Ziel-Webseite (URL)",
            .english: "Name & Target Website (URL)",
            .spanish: "Nombre y sitio web de destino (URL)",
            .french: "Nom et site Web cible (URL)"
        ],
        "web_panel.editor_name_label": [
            .german: "Name des Web-Widgets:",
            .english: "Web Widget Name:",
            .spanish: "Nombre del widget web:",
            .french: "Nom du widget Web :"
        ],
        "web_panel.editor_name_placeholder": [
            .german: "z. B. Proton Kalender",
            .english: "e.g. Proton Calendar",
            .spanish: "p. ej. Proton Calendar",
            .french: "ex. Calendrier Proton"
        ],
        "web_panel.editor_url_label": [
            .german: "Website-Adresse (URL):",
            .english: "Website Address (URL):",
            .spanish: "Dirección del sitio web (URL):",
            .french: "Adresse du site Web (URL) :"
        ],
        "web_panel.editor_templates": [
            .german: "Schnellvorlagen:",
            .english: "Quick Templates:",
            .spanish: "Plantillas rápidas:",
            .french: "Modèles rapides :"
        ],
        "web_panel.editor_logo_section": [
            .german: "Menüleisten-Symbol & Logo anpassen",
            .english: "Customize Menu Bar Icon & Logo",
            .spanish: "Personalizar icono y logotipo de la barra de menús",
            .french: "Personnaliser l'icône et le logo de la barre des menus"
        ],
        "web_panel.editor_rescan": [
            .german: "Neu scannen",
            .english: "Rescan",
            .spanish: "Reescanear",
            .french: "Analyser à nouveau"
        ],
        "web_panel.editor_sec2": [
            .german: "Fenstergröße & Ansicht",
            .english: "Window Size & View",
            .spanish: "Tamaño de ventana y vista",
            .french: "Taille de fenêtre et affichage"
        ],
        "web_panel.editor_width": [
            .german: "Breite:",
            .english: "Width:",
            .spanish: "Ancho:",
            .french: "Largeur :"
        ],
        "web_panel.editor_height": [
            .german: "Höhe:",
            .english: "Height:",
            .spanish: "Alto:",
            .french: "Hauteur :"
        ],
        "web_panel.editor_zoom": [
            .german: "Seiten-Skalierung (Zoom):",
            .english: "Page Scale (Zoom):",
            .spanish: "Escala de página (Zoom):",
            .french: "Mise à l'échelle (Zoom) :"
        ],
        "web_panel.editor_appearance": [
            .german: "Darstellung:",
            .english: "Appearance:",
            .spanish: "Aspecto:",
            .french: "Apparence :"
        ],
        "web_panel.editor_sec3": [
            .german: "Weitere Optionen",
            .english: "Additional Options",
            .spanish: "Opciones adicionales",
            .french: "Options supplémentaires"
        ],
        "web_panel.editor_pin": [
            .german: "Fenster anheften (Pin)",
            .english: "Pin Window",
            .spanish: "Fijar ventana (Pin)",
            .french: "Épingler la fenêtre"
        ],
        "web_panel.editor_pin_tooltip": [
            .german: "Hält das Widget-Fenster dauerhaft geöffnet, auch wenn du in eine andere App klickst oder außerhalb des Fensters tippst.",
            .english: "Keeps the widget window open permanently, even when clicking into another app or outside the window.",
            .spanish: "Mantiene la ventana del widget abierta de forma permanente, incluso al hacer clic en otra app.",
            .french: "Maintient la fenêtre du widget ouverte en permanence, même en cliquant dans une autre application."
        ],
        "web_panel.editor_nav_bar": [
            .german: "Navigationsleiste",
            .english: "Navigation Bar",
            .spanish: "Barra de navegación",
            .french: "Barre de navigation"
        ],
        "web_panel.editor_nav_bar_tooltip": [
            .german: "Blendet eine Leiste mit Vor-, Zurück-, Neuladen- und Zoom-Buttons am unteren Rand des Widgets ein.",
            .english: "Shows a bar with back, forward, reload, and zoom buttons at the bottom of the widget.",
            .spanish: "Muestra una barra con botones de retroceso, avance, recarga y zoom en la parte inferior del widget.",
            .french: "Affiche une barre avec les boutons précédent, suivant, recharger et zoom en bas du widget."
        ],
        "web_panel.editor_top_bar": [
            .german: "Obere Adressleiste",
            .english: "Top Address Bar",
            .spanish: "Barra de dirección superior",
            .french: "Barre d'adresse supérieure"
        ],
        "web_panel.editor_top_bar_tooltip": [
            .german: "Zeigt die Web-Adresse (URL) am oberen Rand des Widgets an. Deaktivieren für eine komplett rahmenlose Ansicht.",
            .english: "Displays the web address (URL) at the top of the widget. Disable for a completely frameless view.",
            .spanish: "Muestra la dirección web (URL) en la parte superior del widget. Desactívalo para una vista sin marcos.",
            .french: "Affiche l'adresse Web (URL) en haut du widget. Désactivez pour une vue totalement sans cadre."
        ],
        "web_panel.preview_title": [
            .german: "Live-Vorschau (%d × %d pt)",
            .english: "Live Preview (%d × %d pt)",
            .spanish: "Vista previa en vivo (%d × %d pt)",
            .french: "Aperçu en direct (%d × %d pt)"
        ],
        "web_panel.preview_reload": [
            .german: "Neu laden",
            .english: "Reload",
            .spanish: "Recargar",
            .french: "Recharger"
        ],
        "web_panel.preview_empty_title": [
            .german: "Noch keine Webseite geladen",
            .english: "No website loaded yet",
            .spanish: "Ningún sitio web cargado aún",
            .french: "Aucun site Web chargé"
        ],
        "web_panel.preview_empty_sub": [
            .german: "Gib links eine URL ein oder wähle eine Vorlage, um die Live-Vorschau zu starten.",
            .english: "Enter a URL on the left or select a template to start the live preview.",
            .spanish: "Introduce una URL a la izquierda o elige una plantilla para iniciar la vista previa en vivo.",
            .french: "Entrez une URL à gauche ou choisissez un modèle pour lancer l'aperçu en direct."
        ],
        "web_panel.editor_create_btn": [
            .german: "Widget erstellen",
            .english: "Create Widget",
            .spanish: "Crear widget",
            .french: "Créer le widget"
        ],

        // Menu Bar Additional Keys
        "menubar.integration_title": [
            .german: "Menüleisten-Integration",
            .english: "Menu Bar Integration",
            .spanish: "Integración de barra de menús",
            .french: "Intégration de la barre des menus"
        ],
        "menubar.integration_toggle": [
            .german: "Eigenes Symbol in der Menüleiste anzeigen",
            .english: "Show dedicated icon in menu bar",
            .spanish: "Mostrar icono dedicado en la barra de menús",
            .french: "Afficher une icône dédiée dans la barre des menus"
        ],
        "menubar.integration_tooltip": [
            .german: "Ermöglicht das schnelle Wechseln der Abstands-Presets direkt über ein Menüleisten-Symbol.",
            .english: "Allows quick switching of spacing presets directly from a menu bar icon.",
            .spanish: "Permite cambiar rápidamente los ajustes de espaciado desde un icono en la barra de menús.",
            .french: "Permet de basculer rapidement entre les préréglages d'espacement directement depuis la barre des menus."
        ],
        "menubar.spacing_presets_title": [
            .german: "Abstand-Presets",
            .english: "Spacing Presets",
            .spanish: "Ajustes de espaciado",
            .french: "Préréglages d'espacement"
        ],
        "menubar.applying": [
            .german: "Wird angewendet...",
            .english: "Applying...",
            .spanish: "Aplicando...",
            .french: "Application en cours..."
        ],
        "menubar.fine_tuning": [
            .german: "Feinabstimmung (Pixel-genau)",
            .english: "Fine Tuning (Pixel-precise)",
            .spanish: "Ajuste fino (precisión de píxel)",
            .french: "Réglage fin (au pixel près)"
        ],
        "menubar.preset_generous": [
            .german: "Großzügig",
            .english: "Generous",
            .spanish: "Generoso",
            .french: "Généreux"
        ],
        "menubar.items_header": [
            .german: "Menüleisten-Elemente & Icons",
            .english: "Menu Bar Items & Icons",
            .spanish: "Elementos e iconos de la barra de menús",
            .french: "Éléments et icônes de la barre des menus"
        ],
        "menubar.items_status_count": [
            .german: "%d Symbole gefunden • %d aktiv in der Menüleiste",
            .english: "%d icons found • %d active in menu bar",
            .spanish: "%d iconos encontrados • %d activos en la barra de menús",
            .french: "%d icônes trouvées • %d actives dans la barre des menus"
        ],
        "menubar.rescan": [
            .german: "Neu scannen",
            .english: "Rescan",
            .spanish: "Reescanear",
            .french: "Analyser à nouveau"
        ],
        "menubar.control_center": [
            .german: "Kontrollzentrum...",
            .english: "Control Center...",
            .spanish: "Centro de control...",
            .french: "Centre de contrôle..."
        ],
        "menubar.no_matching_items": [
            .german: "Keine passenden Menüleisten-Elemente gefunden.",
            .english: "No matching menu bar items found.",
            .spanish: "No se encontraron elementos de la barra de menús que coincidan.",
            .french: "Aucun élément de la barre des menus correspondant trouvé."
        ],

        // Clipboard Options Keys
        "clipboard.options_monitoring_title": [
            .german: "Überwachung & Sicherheit",
            .english: "Monitoring & Security",
            .spanish: "Supervisión y seguridad",
            .french: "Surveillance et sécurité"
        ],
        "clipboard.options_max_items": [
            .german: "Maximale Anzahl gespeicherter Elemente:",
            .english: "Maximum number of saved items:",
            .spanish: "Número máximo de elementos guardados:",
            .french: "Nombre maximal d'éléments enregistrés :"
        ],
        "clipboard.options_items_count_format": [
            .german: "%d Einträge",
            .english: "%d items",
            .spanish: "%d elementos",
            .french: "%d éléments"
        ],
        "clipboard.options_manage_title": [
            .german: "Verlauf verwalten",
            .english: "Manage History",
            .spanish: "Gestionar historial",
            .french: "Gérer l'historique"
        ],
        "clipboard.options_current_items_format": [
            .german: "Aktuell gespeicherte Einträge: %d",
            .english: "Currently saved items: %d",
            .spanish: "Elementos guardados actualmente: %d",
            .french: "Éléments actuellement enregistrés : %d"
        ],
        "clipboard.options_pinned_format": [
            .german: "%d angepinnt",
            .english: "%d pinned",
            .spanish: "%d fijados",
            .french: "%d épinglés"
        ],
        "clipboard.options_images_format": [
            .german: "%d Bilder",
            .english: "%d images",
            .spanish: "%d imágenes",
            .french: "%d images"
        ],
        "clipboard.options_texts_format": [
            .german: "%d Texte",
            .english: "%d texts",
            .spanish: "%d textos",
            .french: "%d textes"
        ],
        "clipboard.options_clear_all_btn": [
            .german: "Gesamten Verlauf löschen",
            .english: "Clear Entire History",
            .spanish: "Borrar todo el historial",
            .french: "Effacer tout l'historique"
        ],
        "clipboard.options_clear_confirm_title": [
            .german: "Verlauf wirklich löschen?",
            .english: "Clear history?",
            .spanish: "¿Borrar historial?",
            .french: "Effacer l'historique ?"
        ],
        "clipboard.options_clear_confirm_msg": [
            .german: "Möchtest du den gesamten Zwischenablage-Verlauf wirklich löschen? Angepinnte Favoriten bleiben erhalten.",
            .english: "Are you sure you want to clear the entire clipboard history? Pinned favorites will be kept.",
            .spanish: "¿Seguro que deseas borrar todo el historial del portapapeles? Los favoritos fijados se conservarán.",
            .french: "Voulez-vous vraiment effacer tout l'historique du presse-papiers ? Les favoris épinglés seront conservés."
        ],

        // Clipboard Subtabs & Subtitle
        "clipboard.subtab_history": [
            .german: "Inhalte & Verlauf",
            .english: "Contents & History",
            .spanish: "Contenido e historial",
            .french: "Contenu et historique"
        ],
        "clipboard.subtab_options": [
            .german: "Optionen & Sicherheit",
            .english: "Options & Security",
            .spanish: "Opciones y seguridad",
            .french: "Options et sécurité"
        ],
        "clipboard.subtitle": [
            .german: "Verlauf kopierter Texte, Links und Bilder mit Such- und Filterfunktion.",
            .english: "History of copied texts, links, and images with search and filter.",
            .spanish: "Historial de textos, enlaces e imágenes copiados con búsqueda y filtro.",
            .french: "Historique des textes, liens et images copiés avec recherche et filtres."
        ],
        "clipboard.pause_recording": [
            .german: "Aufzeichnung pausieren",
            .english: "Pause recording",
            .spanish: "Pausar grabación",
            .french: "Mettre en pause l'enregistrement"
        ],
        "clipboard.excluded_bundle_ids": [
            .german: "Ausgeschlossene Bundle-IDs, durch Kommas getrennt",
            .english: "Excluded Bundle IDs, comma separated",
            .spanish: "IDs de bundle excluidos, separados por comas",
            .french: "Identifiants de paquet exclus, séparés par des virgules"
        ],
        "clipboard.save_encrypted": [
            .german: "Verlauf verschlüsselt auf diesem Mac speichern",
            .english: "Save history encrypted on this Mac",
            .spanish: "Guardar historial cifrado en este Mac",
            .french: "Enregistrer l'historique chiffré sur ce Mac"
        ],
        "clipboard.ignore_passwords": [
            .german: "Passwörter und sensible Daten nicht speichern",
            .english: "Do not save passwords and sensitive data",
            .spanish: "No guardar contraseñas ni datos confidenciales",
            .french: "Ne pas enregistrer les mots de passe et données sensibles"
        ],
        "clipboard.ignore_passwords_tooltip": [
            .german: "Kopierte Passwörter aus Passwort-Managern und Browser-Erweiterungen werden automatisch erkannt und vom Verlauf ausgeschlossen.",
            .english: "Copied passwords from password managers and browser extensions are automatically detected and excluded from history.",
            .spanish: "Las contraseñas copiadas de gestores de contraseñas y extensiones de navegador se detectan automáticamente y se excluyen del historial.",
            .french: "Les mots de passe copiés depuis des gestionnaires de mots de passe et extensions sont automatiquement détectés et exclus de l'historique."
        ],

        // Menu Bar Extra Keys
        "menubar.item_spacing": [
            .german: "Abstand zwischen Symbolen:",
            .english: "Spacing between icons:",
            .spanish: "Espacio entre iconos:",
            .french: "Espacement entre les icônes :"
        ],
        "menubar.click_area": [
            .german: "Klickbereich um Symbole:",
            .english: "Click area around icons:",
            .spanish: "Área de clic alrededor de iconos:",
            .french: "Zone de clic autour des icônes :"
        ],
        "menubar.auto_restart": [
            .german: "Änderungen automatisch anwenden",
            .english: "Apply changes automatically",
            .spanish: "Aplicar cambios automáticamente",
            .french: "Appliquer les modifications automatiquement"
        ],
        "menubar.auto_restart_tooltip": [
            .german: "Startet das macOS ControlCenter bei Abstandsänderungen automatisch im Hintergrund neu.",
            .english: "Automatically restarts macOS Control Center in the background when spacing changes.",
            .spanish: "Reinicia automáticamente el Centro de Control de macOS en segundo plano cuando cambia el espaciado.",
            .french: "Redémarre automatiquement le Centre de contrôle de macOS en arrière-plan lors des modifications d'espacement."
        ],
        "menubar.apply_now": [
            .german: "Menüleiste jetzt aktualisieren",
            .english: "Restart menu bar now",
            .spanish: "Reiniciar barra de menús ahora",
            .french: "Redémarrer la barre des menus maintenant"
        ],
        "menubar.system_symbols_changed": [
            .german: "System-Symbole geändert. Klicke auf 'Übernehmen', um die Menüleiste zu aktualisieren:",
            .english: "System icons changed. Click 'Apply' to update menu bar:",
            .spanish: "Iconos del sistema modificados. Haz clic en 'Aplicar' para actualizar la barra de menús:",
            .french: "Icônes système modifiées. Cliquez sur 'Appliquer' pour mettre à jour la barre des menus :"
        ],
        "menubar.apply_changes_btn": [
            .german: "Jetzt übernehmen",
            .english: "Apply Now",
            .spanish: "Aplicar ahora",
            .french: "Appliquer maintenant"
        ],
        "menubar.search_placeholder": [
            .german: "Elemente suchen...",
            .english: "Search items...",
            .spanish: "Buscar elementos...",
            .french: "Rechercher des éléments..."
        ],
        "menubar.status_running": [
            .german: "• Läuft im Hintergrund",
            .english: "• Running in background",
            .spanish: "• Ejecutándose en segundo plano",
            .french: "• En cours d'exécution en arrière-plan"
        ],
        "menubar.status_stopped": [
            .german: "• Beendet",
            .english: "• Terminated",
            .spanish: "• Finalizado",
            .french: "• Arrêté"
        ],
        "menubar.status_in_menubar": [
            .german: "In Menüleiste",
            .english: "In Menu Bar",
            .spanish: "En barra de menús",
            .french: "Dans la barre des menus"
        ],
        "menubar.status_hidden": [
            .german: "Ausgeblendet",
            .english: "Hidden",
            .spanish: "Oculto",
            .french: "Masqué"
        ],

        // Scroll Reverser Extra Keys
        "scroll_reverser.permission_required": [
            .german: "Bedienungshilfen-Berechtigung erforderlich",
            .english: "Accessibility permission required",
            .spanish: "Permiso de accesibilidad requerido",
            .french: "Autorisation d'accessibilité requise"
        ],
        "scroll_reverser.permission_description": [
            .german: "macOS erfordert die Erlaubnis für Bedienungshilfen, damit die Scrollrichtung der Maus angepasst werden kann.",
            .english: "macOS requires accessibility permission to adjust the scroll direction of your mouse.",
            .spanish: "macOS requiere permiso de accesibilidad para ajustar la dirección de desplazamiento del ratón.",
            .french: "macOS nécessite l'autorisation d'accessibilité pour ajuster le sens de défilement de la souris."
        ],
        "scroll_reverser.check_again": [
            .german: "Erneut prüfen",
            .english: "Check Again",
            .spanish: "Comprobar de nuevo",
            .french: "Vérifier à nouveau"
        ],
        "scroll_reverser.open_settings": [
            .german: "In Systemeinstellungen öffnen",
            .english: "Open System Settings",
            .spanish: "Abrir ajustes del sistema",
            .french: "Ouvrir les réglages système"
        ],
        "scroll_reverser.permission_hint": [
            .german: "Hinweis: Falls Yeoman in den Systemeinstellungen bereits auf AN steht, bitte den Schalter dort einmal kurz **AUS und wieder AN** schalten (oder mit '-' entfernen und neu hinzufügen), damit macOS die Signatur des App-Updates übernimmt.",
            .english: "Note: If Yeoman is already toggled ON in System Settings, please toggle it **OFF and ON again** (or remove with '-' and re-add) so macOS applies the updated app signature.",
            .spanish: "Nota: Si Yeoman ya está activado en Ajustes del Sistema, **desactívalo y vuelve a activarlo** (o elimínalo con '-' y agrégalo de nuevo) para que macOS aplique la firma actualizada.",
            .french: "Remarque : Si Yeoman est déjà activé dans les Réglages Système, veuillez le **désactiver puis le réactiver** (ou le supprimer avec '-' et le réajouter) pour que macOS applique la nouvelle signature."
        ],
        "scroll_reverser.step_multiplier": [
            .german: "Scrollrad-Schrittmultiplikator:",
            .english: "Scroll wheel step multiplier:",
            .spanish: "Multiplicador de pasos de la rueda:",
            .french: "Multiplicateur de pas de la molette :"
        ],
        "scroll_reverser.step_multiplier_tooltip": [
            .german: "Erhöht die Scroll-Geschwindigkeit pro Mausrad-Rasterung.",
            .english: "Increases the scroll speed per mouse wheel notch.",
            .spanish: "Aumenta la velocidad de desplazamiento por paso de la rueda.",
            .french: "Augmente la vitesse de défilement par cran de la molette."
        ],
        "scroll_reverser.step_standard": [
            .german: "1x (Standard)",
            .english: "1x (Standard)",
            .spanish: "1x (Estándar)",
            .french: "1x (Standard)"
        ],
        "scroll_reverser.step_faster": [
            .german: "2x (Schneller)",
            .english: "2x (Faster)",
            .spanish: "2x (Más rápido)",
            .french: "2x (Plus rapide)"
        ],
        "scroll_reverser.step_max": [
            .german: "5x (Maximum)",
            .english: "5x (Maximum)",
            .spanish: "5x (Máximo)",
            .french: "5x (Maximum)"
        ],
        "scroll_reverser.menubar_integration": [
            .german: "Menüleisten-Integration",
            .english: "Menu Bar Integration",
            .spanish: "Integración de barra de menús",
            .french: "Intégration de la barre des menus"
        ],
        "scroll_reverser.menubar_toggle": [
            .german: "Eigenes Symbol in der Menüleiste anzeigen",
            .english: "Show dedicated icon in menu bar",
            .spanish: "Mostrar icono dedicado en la barra de menús",
            .french: "Afficher une icône dédiée dans la barre des menus"
        ],
        "scroll_reverser.menubar_tooltip": [
            .german: "Zeigt ein separates Maus-Symbol in der Menüleiste an, über das du die Richtung per Klick umschalten kannst.",
            .english: "Shows a separate mouse icon in the menu bar to toggle direction with a click.",
            .spanish: "Muestra un icono de ratón independiente en la barra de menús para alternar la dirección con un clic.",
            .french: "Affiche une icône de souris distincte dans la barre des menus pour inverser la direction d'un clic."
        ],
        "scroll_reverser.status": [
            .german: "Status",
            .english: "Status",
            .spanish: "Estado",
            .french: "État"
        ],
        "scroll_reverser.status_active": [
            .german: "Aktiv",
            .english: "Active",
            .spanish: "Activo",
            .french: "Actif"
        ],
        "scroll_reverser.status_paused": [
            .german: "Angehalten",
            .english: "Paused",
            .spanish: "Pausado",
            .french: "En pause"
        ],
        "scroll_reverser.last_device": [
            .german: "Zuletzt erkanntes Gerät:",
            .english: "Last detected device:",
            .spanish: "Último dispositivo detectado:",
            .french: "Dernier appareil détecté :"
        ],
        "scroll_reverser.action": [
            .german: "Aktion:",
            .english: "Action:",
            .spanish: "Acción:",
            .french: "Action :"
        ],

        // System Stats Extra Keys
        "system_stats.configure_header": [
            .german: "Menüleisten-Anzeige konfigurieren",
            .english: "Configure Menu Bar Display",
            .spanish: "Configurar visualización en la barra de menús",
            .french: "Configurer l'affichage dans la barre des menus"
        ],
        "system_stats.live_preview": [
            .german: "Live-Vorschau:",
            .english: "Live Preview:",
            .spanish: "Vista previa en vivo:",
            .french: "Aperçu en direct :"
        ],
        "system_stats.active_metrics": [
            .german: "Aktive Messwerte in der Menüleiste:",
            .english: "Active metrics in menu bar:",
            .spanish: "Métricas activas en la barra de menús:",
            .french: "Métriques actives dans la barre des menus :"
        ],
        "system_stats.layout_alignment": [
            .german: "Layout & Text-Ausrichtung:",
            .english: "Layout & Alignment:",
            .spanish: "Diseño y alineación:",
            .french: "Disposition et alignement :"
        ],
        "system_stats.layout_style": [
            .german: "Layout-Stil:",
            .english: "Layout Style:",
            .spanish: "Estilo de diseño:",
            .french: "Style de disposition :"
        ],
        "system_stats.graph_type": [
            .german: "Graph-Typ:",
            .english: "Graph Type:",
            .spanish: "Tipo de gráfico:",
            .french: "Type de graphique :"
        ],
        "system_stats.display_options": [
            .german: "Darstellungs-Optionen:",
            .english: "Display Options:",
            .spanish: "Opciones de visualización:",
            .french: "Options d'affichage :"
        ],
        "system_stats.opt_show_labels": [
            .german: "Text-Bezeichnung anzeigen (z.B. „CPU“, „RAM“, „GPU“)",
            .english: "Show text label (e.g. 'CPU', 'RAM', 'GPU')",
            .spanish: "Mostrar etiqueta de texto (ej. 'CPU', 'RAM', 'GPU')",
            .french: "Afficher le libellé texte (ex. « CPU », « RAM », « GPU »)"
        ],
        "system_stats.opt_show_percentage": [
            .german: "Prozentwert als Text anzeigen (z.B. „10%“, „61%“)",
            .english: "Show percentage as text (e.g. '10%', '61%')",
            .spanish: "Mostrar porcentaje como texto (ej. '10%', '61%')",
            .french: "Afficher le pourcentage sous forme de texte (ex. « 10 % », « 61 % »)"
        ],
        "system_stats.opt_show_graphs": [
            .german: "Mini-Graphen & Balken anzeigen",
            .english: "Show mini graphs & bars",
            .spanish: "Mostrar minigráficos y barras",
            .french: "Afficher les mini-graphiques et barres"
        ],
        "system_stats.opt_subtle_background": [
            .german: "Dezenter Kapsel-Hintergrund (Pill)",
            .english: "Subtle pill background",
            .spanish: "Fondo de cápsula sutil",
            .french: "Arrière-plan capsule discret"
        ],
        "system_stats.current_usage": [
            .german: "Aktuelle System-Auslastung",
            .english: "Current System Usage",
            .spanish: "Uso actual del sistema",
            .french: "Utilisation actuelle du système"
        ],
        "system_stats.task_manager_header": [
            .german: "Laufende Prozesse & Task-Manager",
            .english: "Running Processes & Task Manager",
            .spanish: "Procesos en ejecución y Administrador de tareas",
            .french: "Processus en cours et Gestionnaire des tâches"
        ],
        "system_stats.task_manager_tooltip": [
            .german: "Über das Menüleisten-Symbol kannst du Prozesse einsehen und nicht reagierende Apps direkt beenden.",
            .english: "View running processes and terminate unresponsive apps directly from the menu bar icon.",
            .spanish: "Consulta procesos en ejecución y finaliza apps que no responden directamente desde la barra de menús.",
            .french: "Affichez les processus et fermez les applications bloquées directement depuis la barre des menus."
        ],
        "system_stats.active_processes_count": [
            .german: "%d Prozesse aktiv",
            .english: "%d processes active",
            .spanish: "%d procesos activos",
            .french: "%d processus actifs"
        ],
        "system_stats.open_activity_monitor": [
            .german: "Aktivitätsanzeige öffnen",
            .english: "Open Activity Monitor",
            .spanish: "Abrir Monitor de Actividad",
            .french: "Ouvrir le Moniteur d'activité"
        ],
        "system_stats.search_processes": [
            .german: "Prozess suchen...",
            .english: "Search process...",
            .spanish: "Buscar proceso...",
            .french: "Rechercher un processus..."
        ],
        "system_stats.col_process": [
            .german: "PROZESS",
            .english: "PROCESS",
            .spanish: "PROCESO",
            .french: "PROCESSUS"
        ],
        "system_stats.col_cpu": [
            .german: "CPU",
            .english: "CPU",
            .spanish: "CPU",
            .french: "CPU"
        ],
        "system_stats.col_ram": [
            .german: "RAM",
            .english: "RAM",
            .spanish: "RAM",
            .french: "RAM"
        ],
        "system_stats.col_action": [
            .german: "AKTION",
            .english: "ACTION",
            .spanish: "ACCIÓN",
            .french: "ACTION"
        ],
        "system_stats.kill_hint": [
            .german: "%d Prozesse • Klick auf ✕ beendet Prozess sofort",
            .english: "%d processes • Click ✕ to kill immediately",
            .spanish: "%d procesos • Clic en ✕ finaliza el proceso",
            .french: "%d processus • Clic sur ✕ termine le processus"
        ],
        "system_stats.activity_monitor_short": [
            .german: "Aktivitätsanzeige",
            .english: "Activity Monitor",
            .spanish: "Monitor de Actividad",
            .french: "Moniteur d'activité"
        ],
        "system_stats.cores_format": [
            .german: "%d Kerne",
            .english: "%d Cores",
            .spanish: "%d Núcleos",
            .french: "%d Cœurs"
        ],
        "system_stats.graphics_engine": [
            .german: "Grafik-Engine",
            .english: "Graphics Engine",
            .spanish: "Motor gráfico",
            .french: "Moteur graphique"
        ],

        // Updates Extra Keys
        "updates.popup_version_info": [
            .german: "Yeoman **%@** ist verfügbar (installiert: %@).",
            .english: "Yeoman **%@** is available (installed: %@).",
            .spanish: "Yeoman **%@** está disponible (instalado: %@).",
            .french: "Yeoman **%@** est disponible (installé : %@)."
        ],
        "updates.no_release_notes": [
            .german: "Keine weiteren Versionshinweise vorhanden.",
            .english: "No additional release notes available.",
            .spanish: "No hay notas de la versión adicionales disponibles.",
            .french: "Aucune note de version supplémentaire disponible."
        ],
        "updates.verifying_installing": [
            .german: "Update wird verifiziert und installiert...",
            .english: "Verifying and installing update...",
            .spanish: "Verificando e instalando actualización...",
            .french: "Vérification et installation de la mise à jour..."
        ],
        "updates.installing": [
            .german: "Update wird installiert & Yeoman neu gestartet...",
            .english: "Installing update & restarting Yeoman...",
            .spanish: "Instalando actualización y reiniciando Yeoman...",
            .french: "Installation de la mise à jour et redémarrage de Yeoman..."
        ],

        // Web Widget Extra Keys
        "web_panel.empty_btn": [
            .german: "Jetzt erstes Widget anlegen",
            .english: "Create first widget now",
            .spanish: "Crear primer widget ahora",
            .french: "Créer le premier widget maintenant"
        ],
        "web_panel.logo_picker_header": [
            .german: "Symbol & Logo wählen",
            .english: "Select Symbol & Logo",
            .spanish: "Elegir icono y logotipo",
            .french: "Choisir le symbole et le logo"
        ],
        "web_panel.logo_picker_website_logo": [
            .german: "Website-Logo verwenden",
            .english: "Use website logo",
            .spanish: "Usar logotipo del sitio",
            .french: "Utiliser le logo du site Web"
        ],
        "web_panel.logo_picker_website_logo_tooltip": [
            .german: "Verwendet das farbige Original-Logo der Website direkt in der Menüleiste.",
            .english: "Uses the website's original colored logo directly in the menu bar.",
            .spanish: "Usa el logotipo original a color en la barra de menús.",
            .french: "Utilise le logo en couleur d'origine dans la barre des menus."
        ],
        "web_panel.logo_picker_transparent_bg": [
            .german: "Weißer Hintergrund transparent machen",
            .english: "Make white background transparent",
            .spanish: "Hacer transparente el fondo blanco",
            .french: "Rendre le fond blanc transparent"
        ],
        "web_panel.logo_picker_transparent_bg_tooltip": [
            .german: "Entfernt automatisch weiße Flächen aus quadratischen Logos.",
            .english: "Automatically removes white areas from square logos.",
            .spanish: "Elimina automáticamente las áreas blancas de los logotipos cuadrados.",
            .french: "Supprime automatiquement les zones blanches des logos carrés."
        ],
        "web_panel.logo_picker_fallback_symbol": [
            .german: "Ersatz-Symbol (Fallback):",
            .english: "Fallback Symbol:",
            .spanish: "Icono de respaldo (Fallback):",
            .french: "Symbole de secours (Fallback) :"
        ],
        "web_panel.logo_picker_select_symbol": [
            .german: "Symbol auswählen:",
            .english: "Select Symbol:",
            .spanish: "Seleccionar icono:",
            .french: "Sélectionner un symbole :"
        ],
        "web_panel.editor_load_btn": [
            .german: "Laden",
            .english: "Load",
            .spanish: "Cargar",
            .french: "Charger"
        ],
        "web_panel.editor_templates_tooltip": [
            .german: "Klicke auf eine Vorlage, um Name, Ziel-Adresse und optimale Fenstergröße sofort zu übernehmen.",
            .english: "Click a template to apply name, URL, and optimal window size immediately.",
            .spanish: "Haz clic en una plantilla para aplicar nombre, URL y tamaño de ventana óptimo.",
            .french: "Cliquez sur un modèle pour appliquer immédiatement le nom, l'URL et la taille de fenêtre optimale."
        ],
        "web_panel.editor_auto_logo": [
            .german: "Website-Logo automatisch verwenden",
            .english: "Use website logo automatically",
            .spanish: "Usar logotipo web automáticamente",
            .french: "Utiliser automatiquement le logo du site Web"
        ],
        "web_panel.editor_auto_logo_tooltip": [
            .german: "Verwendet das farbige Original-Logo der Website. Transparente Symbole werden bevorzugt.",
            .english: "Uses the original colored logo of the website. Transparent symbols are preferred.",
            .spanish: "Usa el logotipo original a color de la web. Se prefieren iconos transparentes.",
            .french: "Utilise le logo original en couleur du site Web. Les symboles transparents sont préférés."
        ],
        "web_panel.editor_selected_logo_active": [
            .german: "Ausgewähltes Logo aktiv",
            .english: "Selected logo active",
            .spanish: "Logotipo seleccionado activo",
            .french: "Logo sélectionné actif"
        ],
        "web_panel.editor_best_logo_active": [
            .german: "Bestes transparentes Logo aktiv",
            .english: "Best transparent logo active",
            .spanish: "Mejor logotipo transparente activo",
            .french: "Meilleur logo transparent actif"
        ],
        "web_panel.editor_enter_url_hint": [
            .german: "Gib oben eine URL ein",
            .english: "Enter a URL above",
            .spanish: "Introduce una URL arriba",
            .french: "Entrez une URL ci-dessus"
        ],
        "web_panel.editor_searching_logos": [
            .german: "Logos werden gesucht...",
            .english: "Searching logos...",
            .spanish: "Buscando logotipos...",
            .french: "Recherche des logos en cours..."
        ],
        "web_panel.editor_options_tooltip": [
            .german: "Gefundene Favicon- und App-Icon-Varianten. Klicke ein Logo an, um es festzulegen.",
            .english: "Discovered favicon and app icon variants. Click a logo to select it.",
            .spanish: "Variantes de favicon e iconos de app encontrados. Haz clic para seleccionar.",
            .french: "Variantes de favicons et d'icônes d'application trouvées. Cliquez pour sélectionner."
        ],
        "web_panel.editor_auto_select": [
            .german: "Automatisch wählen",
            .english: "Choose automatically",
            .spanish: "Elegir automáticamente",
            .french: "Choisir automatiquement"
        ],
        "web_panel.editor_badge_transparent": [
            .german: "Transparent",
            .english: "Transparent",
            .spanish: "Transparente",
            .french: "Transparent"
        ],
        "web_panel.editor_badge_background": [
            .german: "Mit Hintergrund",
            .english: "With background",
            .spanish: "Con fondo",
            .french: "Avec arrière-plan"
        ],
        "web_panel.editor_remove_white_tooltip": [
            .german: "Entfernt automatisch weiße Flächen aus Logos (z. B. bei quadratischen iOS-Kacheln).",
            .english: "Automatically removes white areas from logos (e.g. square iOS tiles).",
            .spanish: "Elimina automáticamente áreas blancas de logos (ej. iconos cuadrados de iOS).",
            .french: "Supprime automatiquement les zones blanches des logos (ex. tuiles iOS carrées)."
        ],
        "web_panel.editor_fallback_symbol_label": [
            .german: "Ersatz-Symbol:",
            .english: "Fallback Symbol:",
            .spanish: "Icono de respaldo:",
            .french: "Symbole de secours :"
        ],
        "web_panel.editor_menubar_symbol_label": [
            .german: "Symbol für Menüleiste:",
            .english: "Menu Bar Symbol:",
            .spanish: "Icono para barra de menús:",
            .french: "Symbole pour barre des menus :"
        ],
        "web_panel.editor_fallback_symbol_tooltip": [
            .german: "Wird in der Menüleiste angezeigt, falls die Website kein Web-Logo liefert.",
            .english: "Shown in the menu bar if the website provides no web logo.",
            .spanish: "Se muestra en la barra de menús si el sitio no ofrece logotipo web.",
            .french: "Affiché dans la barre des menus si le site Web ne fournit aucun logo."
        ],
        "web_panel.editor_size_label": [
            .german: "Größe:",
            .english: "Size:",
            .spanish: "Tamaño:",
            .french: "Taille :"
        ],
        "scroll_reverser.mouse_vertical_tooltip": [
            .german: "Empfohlen: Aktiviert. Wenn macOS auf 'Natürliches Scrollen' steht, scrollt die Maus hiermit gewohnt nach unten, während das Trackpad unverändert bleibt.",
            .english: "Recommended: Enabled. When macOS is set to 'Natural scrolling', this keeps traditional mouse wheel scrolling down while leaving the trackpad unchanged.",
            .spanish: "Recomendado: Activado. Cuando macOS está configurado en 'Desplazamiento natural', esto mantiene el desplazamiento tradicional hacia abajo con el ratón sin alterar el trackpad.",
            .french: "Recommandé : Activé. Lorsque macOS est réglé sur 'Défilement naturel', cela conserve le défilement traditionnel vers le bas de la souris tout en laissant le trackpad inchangé."
        ],
        "scroll_reverser.trackpad_vertical_tooltip": [
            .german: "Empfohlen: Deaktiviert. Das Trackpad behält so das native macOS-Verhalten (Zwei-Finger-Wischgeste wie auf Touchscreens).",
            .english: "Recommended: Disabled. The trackpad retains native macOS behavior (two-finger swipe like touchscreens).",
            .spanish: "Recomendado: Desactivado. El trackpad conserva el comportamiento nativo de macOS (gesto de deslizar con dos dedos como en pantallas táctiles).",
            .french: "Recommandé : Désactivé. Le trackpad conserve le comportement natif de macOS (glissement à deux doigts comme sur écran tactile)."
        ],
        "web_panel.preset_custom": [
            .german: "Benutzerdefiniert",
            .english: "Custom",
            .spanish: "Personalizado",
            .french: "Personnalisé"
        ],
        "web_panel.preset_widget": [
            .german: "320 × 400 (Widget)",
            .english: "320 × 400 (Widget)",
            .spanish: "320 × 400 (Widget)",
            .french: "320 × 400 (Widget)"
        ],
        "web_panel.preset_smartphone": [
            .german: "375 × 667 (Smartphone)",
            .english: "375 × 667 (Smartphone)",
            .spanish: "375 × 667 (Smartphone)",
            .french: "375 × 667 (Smartphone)"
        ],
        "web_panel.preset_large": [
            .german: "500 × 700 (Großes Fenster)",
            .english: "500 × 700 (Large Window)",
            .spanish: "500 × 700 (Ventana grande)",
            .french: "500 × 700 (Grande fenêtre)"
        ],
        "web_panel.ua_auto": [
            .german: "Automatisch (nach Größe)",
            .english: "Automatic (by size)",
            .spanish: "Automático (por tamaño)",
            .french: "Automatique (selon taille)"
        ],
        "web_panel.ua_mobile": [
            .german: "Immer Mobil (iPhone)",
            .english: "Always Mobile (iPhone)",
            .spanish: "Siempre Móvil (iPhone)",
            .french: "Toujours Mobile (iPhone)"
        ],
        "web_panel.ua_desktop": [
            .german: "Immer Desktop",
            .english: "Always Desktop",
            .spanish: "Siempre Escritorio",
            .french: "Toujours Bureau"
        ],
        "web_panel.editor_zoom_tooltip": [
            .german: "Skaliert Webseiten herunter, damit sie im Widget optimal ohne horizontales Scrollen lesbar sind.",
            .english: "Scales web pages down to fit nicely in the widget without horizontal scrolling.",
            .spanish: "Reduce las páginas web para que quepan bien en el widget sin desplazamiento horizontal.",
            .french: "Met à l'échelle les pages web pour les adapter au widget sans défilement horizontal."
        ],
        "web_panel.editor_appearance_tooltip": [
            .german: "Mobil erzwingt ein schmales Smartphone-Layout (ideal für Widgets). Desktop lädt die Standard-Website.",
            .english: "Mobile forces a narrow smartphone layout (ideal for widgets). Desktop loads the standard website.",
            .spanish: "Móvil fuerza un diseño estrecho de teléfono (ideal para widgets). Escritorio carga el sitio web estándar.",
            .french: "Mobile force une disposition étroite de smartphone (idéal pour les widgets). Bureau charge le site web standard."
        ],
        "web_panel.template_proton_cal": [
            .german: "Proton Kalender",
            .english: "Proton Calendar",
            .spanish: "Proton Calendar",
            .french: "Calendrier Proton"
        ],
        "web_panel.template_google_cal": [
            .german: "Google Kalender",
            .english: "Google Calendar",
            .spanish: "Google Calendar",
            .french: "Google Agenda"
        ],
        "web_panel.popup_url_placeholder": [
            .german: "URL eingeben...",
            .english: "Enter URL...",
            .spanish: "Introducir URL...",
            .french: "Saisir l'URL..."
        ],
        "web_panel.popup_show_toolbar": [
            .german: "Navigationsleiste einblenden",
            .english: "Show navigation bar",
            .spanish: "Mostrar barra de navegación",
            .french: "Afficher la barre de navigation"
        ],
        "web_panel.popup_close_toolbar": [
            .german: "Navigationsleiste schließen",
            .english: "Close navigation bar",
            .spanish: "Cerrar barra de navegación",
            .french: "Fermer la barre de navigation"
        ],
        "web_panel.popup_home": [
            .german: "Zur Startseite (%@)",
            .english: "To home page (%@)",
            .spanish: "A la página de inicio (%@)",
            .french: "À la page d'accueil (%@)"
        ],
        "web_panel.popup_back": [
            .german: "Zurück",
            .english: "Back",
            .spanish: "Atrás",
            .french: "Retour"
        ],
        "web_panel.popup_forward": [
            .german: "Vorwärts",
            .english: "Forward",
            .spanish: "Adelante",
            .french: "Suivant"
        ],
        "web_panel.popup_reload": [
            .german: "Neu laden",
            .english: "Reload",
            .spanish: "Recargar",
            .french: "Recharger"
        ],
        "web_panel.popup_window_size": [
            .german: "Fenstergröße",
            .english: "Window Size",
            .spanish: "Tamaño de ventana",
            .french: "Taille de fenêtre"
        ],
        "web_panel.popup_user_agent": [
            .german: "User Agent (Smartphone / Desktop)",
            .english: "User Agent (Smartphone / Desktop)",
            .spanish: "User Agent (Smartphone / Escritorio)",
            .french: "User Agent (Smartphone / Bureau)"
        ],
        "web_panel.popup_hide_toolbar_default": [
            .german: "Navigationsleiste standardmäßig ausblenden",
            .english: "Hide navigation bar by default",
            .spanish: "Ocultar barra de navegación por defecto",
            .french: "Masquer la barre de navigation par défaut"
        ],
        "web_panel.popup_show_toolbar_default": [
            .german: "Navigationsleiste standardmäßig einblenden",
            .english: "Show navigation bar by default",
            .spanish: "Mostrar barra de navegación por defecto",
            .french: "Afficher la barre de navigation par défaut"
        ],
        "web_panel.popup_hide_topbar": [
            .german: "Obere Adressleiste ausblenden",
            .english: "Hide top address bar",
            .spanish: "Ocultar barra de direcciones superior",
            .french: "Masquer la barre d'adresse supérieure"
        ],
        "web_panel.popup_show_topbar": [
            .german: "Obere Adressleiste einblenden",
            .english: "Show top address bar",
            .spanish: "Mostrar barra de direcciones superior",
            .french: "Afficher la barre d'adresse supérieure"
        ],
        "web_panel.popup_open_browser": [
            .german: "Im Browser öffnen",
            .english: "Open in Browser",
            .spanish: "Abrir en navegador",
            .french: "Ouvrir dans le navigateur"
        ],
        "web_panel.popup_settings": [
            .german: "Einstellungen...",
            .english: "Settings...",
            .spanish: "Ajustes...",
            .french: "Réglages..."
        ],
        "web_panel.popup_adjust_size": [
            .german: "Fenstergröße anpassen",
            .english: "Adjust window size",
            .spanish: "Ajustar tamaño de ventana",
            .french: "Ajuster la taille de la fenêtre"
        ],
        "web_panel.popup_autofit_format": [
            .german: "Konfiguriert: %d × %d pt (automatisch an Bildschirm angepasst)",
            .english: "Configured: %d × %d pt (automatically adjusted to screen)",
            .spanish: "Configurado: %d × %d pt (ajustado automáticamente a la pantalla)",
            .french: "Configuré : %d × %d pt (automatiquement ajusté à l'écran)"
        ],
        "web_panel.popup_zoom_section": [
            .german: "Seiten-Skalierung (Zoom)",
            .english: "Page Scaling (Zoom)",
            .spanish: "Escala de página (Zoom)",
            .french: "Mise à l'échelle (Zoom)"
        ],
        "web_panel.popup_edit_url": [
            .german: "URL bearbeiten",
            .english: "Edit URL",
            .spanish: "Editar URL",
            .french: "Modifier l'URL"
        ],
        "web_panel.popup_unpin": [
            .german: "Fenster lösen",
            .english: "Unpin window",
            .spanish: "Desanclar ventana",
            .french: "Détacher la fenêtre"
        ],
        "web_panel.popup_pin": [
            .german: "Fenster anheften (offen halten)",
            .english: "Pin window (keep open)",
            .spanish: "Anclar ventana (mantener abierta)",
            .french: "Épingler la fenêtre (garder ouverte)"
        ],
        "web_panel.popup_open_default_browser": [
            .german: "Im Standard-Browser öffnen",
            .english: "Open in default browser",
            .spanish: "Abrir en navegador predeterminado",
            .french: "Ouvrir dans le navigateur par défaut"
        ],
        "system_stats.layout_vertical": [
            .german: "Vertikal gestapelt",
            .english: "Vertically stacked",
            .spanish: "Apilado verticalmente",
            .french: "Empilé verticalement"
        ],
        "system_stats.layout_horizontal": [
            .german: "Horizontal nebeneinander",
            .english: "Horizontally side by side",
            .spanish: "Horizontal uno al lado del otro",
            .french: "Horizontalement côte à côte"
        ],
        "system_stats.graph_minibar": [
            .german: "Vertikaler Füllbalken",
            .english: "Vertical Fill Bar",
            .spanish: "Barra de llenado vertical",
            .french: "Barre de remplissage verticale"
        ],
        "system_stats.graph_sparkline": [
            .german: "Mini-Verlaufskurve",
            .english: "Mini Trend Curve",
            .spanish: "Mini curva de tendencia",
            .french: "Mini courbe de tendance"
        ],
        "system_stats.graph_none": [
            .german: "Kein Graph",
            .english: "No Graph",
            .spanish: "Sin gráfico",
            .french: "Aucun graphique"
        ],
        "system_stats.sort_cpu": [
            .german: "CPU %",
            .english: "CPU %",
            .spanish: "CPU %",
            .french: "CPU %"
        ],
        "system_stats.sort_memory": [
            .german: "Arbeitsspeicher",
            .english: "Memory",
            .spanish: "Memoria",
            .french: "Mémoire"
        ],
        "system_stats.sort_name": [
            .german: "Name",
            .english: "Name",
            .spanish: "Nombre",
            .french: "Nom"
        ],
        "system_stats.metric_ram_label": [
            .german: "RAM (Speicher)",
            .english: "RAM (Memory)",
            .spanish: "RAM (Memoria)",
            .french: "RAM (Mémoire)"
        ],
        "system_stats.metric_gpu_label": [
            .german: "GPU (Grafik)",
            .english: "GPU (Graphics)",
            .spanish: "GPU (Gráficos)",
            .french: "GPU (Graphiques)"
        ],
        "system_stats.search_tooltip": [
            .german: "Nach Prozessen suchen",
            .english: "Search processes",
            .spanish: "Buscar procesos",
            .french: "Rechercher des processus"
        ],
        "system_stats.kill_tooltip": [
            .german: "Prozess '%@' sofort beenden",
            .english: "Kill process '%@' immediately",
            .spanish: "Finalizar proceso '%@' de inmediato",
            .french: "Arrêter immédiatement le processus '%@'"
        ]
    ]
}

public extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

public func l10n(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}

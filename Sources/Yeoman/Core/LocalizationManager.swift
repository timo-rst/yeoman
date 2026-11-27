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
        "tab.finderCut": [
            .german: "Finder Ausschneiden",
            .english: "Finder Cut",
            .spanish: "Cortar en Finder",
            .french: "Couper dans le Finder"
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
            .german: "Startet Yeoman automatisch beim Hochfahren deines Macs.",
            .english: "Starts Yeoman automatically when your Mac boots up.",
            .spanish: "Inicia Yeoman automáticamente cuando tu Mac se enciende.",
            .french: "Lance Yeoman automatiquement au démarrage de votre Mac."
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
            .german: "Zeigt das Hauptsymbol von Yeoman in der Menüleiste an, über das du schnellen Zugriff auf alle Module hast.",
            .english: "Shows the main Yeoman icon in the menu bar for quick access to all modules.",
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
            .german: "Scroll-Richtung",
            .english: "Scroll Direction",
            .spanish: "Desplazamiento",
            .french: "Défilement"
        ],
        "general.scroll_reverser_sub": [
            .german: "Kehrt die Scrollrichtung der Maus um, während das Trackpad unverändert bleibt",
            .english: "Inverts mouse scroll direction while keeping trackpad scrolling natural",
            .spanish: "Invierte la dirección del ratón manteniendo el trackpad natural",
            .french: "Inverse le sens de défilement de la souris tout en conservant le trackpad naturel"
        ],
        "general.finder_cut_title": [
            .german: "Finder Ausschneiden",
            .english: "Finder Cut",
            .spanish: "Cortar en Finder",
            .french: "Couper dans le Finder"
        ],
        "general.finder_cut_sub": [
            .german: "Dateien im Finder mit ⌘X ausschneiden und mit ⌘V verschieben",
            .english: "Cut files in Finder with ⌘X and move them with ⌘V",
            .spanish: "Corta archivos en Finder con ⌘X y muévelos con ⌘V",
            .french: "Coupez des fichiers dans le Finder avec ⌘X et déplacez-les avec ⌘V"
        ],
        "general.web_panel_title": [
            .german: "Web-Widgets",
            .english: "Web Widgets",
            .spanish: "Widgets web",
            .french: "Widgets Web"
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
            .german: "Änderungsprotokoll:",
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
            .german: "Symbol-Abstand",
            .english: "Icon Spacing",
            .spanish: "Espaciado de iconos",
            .french: "Espacement des icônes"
        ],
        "menubar.padding_slider": [
            .german: "Klickbereich",
            .english: "Click Area",
            .spanish: "Área de clic",
            .french: "Zone de clic"
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
        "clipboard.preview_title_screenshot": [
            .german: "Screenshot-Vorschau",
            .english: "Screenshot Preview",
            .spanish: "Vista previa de captura",
            .french: "Aperçu de la capture"
        ],
        "clipboard.preview_title_image": [
            .german: "Bild-Vorschau",
            .english: "Image Preview",
            .spanish: "Vista previa de imagen",
            .french: "Aperçu de l’image"
        ],
        "clipboard.copied_from_format": [
            .german: "Kopiert aus: %@",
            .english: "Copied from: %@",
            .spanish: "Copiado de: %@",
            .french: "Copié depuis : %@"
        ],
        "clipboard.copy_to_clipboard": [
            .german: "In Zwischenablage kopieren",
            .english: "Copy to Clipboard",
            .spanish: "Copiar al portapapeles",
            .french: "Copier dans le presse-papiers"
        ],
        "clipboard.open_full_image": [
            .german: "Bild öffnen",
            .english: "Open Image",
            .spanish: "Abrir imagen",
            .french: "Ouvrir l’image"
        ],
        "clipboard.fit_to_window": [
            .german: "Anpassen",
            .english: "Fit",
            .spanish: "Ajustar",
            .french: "Ajuster"
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
            .german: "Scroll-Richtung",
            .english: "Scroll Direction",
            .spanish: "Desplazamiento",
            .french: "Défilement"
        ],
        "scroll_reverser.subtitle": [
            .german: "Kehrt die Scrollrichtung der Maus um, während das Trackpad unverändert bleibt.",
            .english: "Inverts mouse scroll direction while keeping trackpad scrolling natural.",
            .spanish: "Invierte la dirección del ratón manteniendo el trackpad natural.",
            .french: "Inverse le sens de défilement de la souris tout en conservant le trackpad naturel."
        ],
        "scroll_reverser.mouse_header": [
            .german: "Maus",
            .english: "Mouse",
            .spanish: "Ratón",
            .french: "Souris"
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
            .german: "%d eingerichtet • %d aktiv",
            .english: "%d configured • %d active",
            .spanish: "%d configurados • %d activos",
            .french: "%d configurés • %d actifs"
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
            .german: "Name & Adresse",
            .english: "Name & Address",
            .spanish: "Nombre y dirección",
            .french: "Nom et adresse"
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
            .german: "Adresse:",
            .english: "Address:",
            .spanish: "Dirección:",
            .french: "Adresse :"
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
            .german: "Zoom:",
            .english: "Zoom:",
            .spanish: "Zoom:",
            .french: "Zoom :"
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
            .german: "Fenster anpinnen",
            .english: "Pin Window",
            .spanish: "Fijar ventana",
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
            .german: "Feinabstimmung",
            .english: "Fine Tuning",
            .spanish: "Ajuste fino",
            .french: "Réglage fin"
        ],
        "menubar.fine_tuning_tooltip": [
            .german: "Passt Symbol-Abstand und Klickbereich punktgenau an.",
            .english: "Adjusts icon spacing and click area down to the point.",
            .spanish: "Ajusta el espaciado y el área de clic con precisión.",
            .french: "Ajuste l'espacement et la zone de clic au point près."
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
            .german: "Verlaufsgröße:",
            .english: "History Limit:",
            .spanish: "Límite:",
            .french: "Limite :"
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
            .german: "Ausgeschlossene Apps",
            .english: "Excluded Apps",
            .spanish: "Apps excluidas",
            .french: "Apps exclues"
        ],
        "clipboard.excluded_bundle_ids_tooltip": [
            .german: "Kommagetrennte Bundle-IDs von Apps, deren Kopien nicht gespeichert werden.",
            .english: "Comma-separated bundle IDs of apps whose copies are ignored.",
            .spanish: "IDs de bundle separados por comas de apps cuyas copias se ignoran.",
            .french: "Identifiants de paquet séparés par des virgules dont les copies sont ignorées."
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
            .german: "Scroll-Tempo:",
            .english: "Scroll Speed:",
            .spanish: "Velocidad:",
            .french: "Vitesse :"
        ],
        "scroll_reverser.step_multiplier_tooltip": [
            .german: "Erhöht die Scroll-Geschwindigkeit pro Mausrad-Rasterung.",
            .english: "Increases the scroll speed per mouse wheel notch.",
            .spanish: "Aumenta la velocidad de desplazamiento por paso de la rueda.",
            .french: "Augmente la vitesse de défilement par cran de la molette."
        ],
        "scroll_reverser.step_standard": [
            .german: "1×",
            .english: "1×",
            .spanish: "1×",
            .french: "1×"
        ],
        "scroll_reverser.step_faster": [
            .german: "2×",
            .english: "2×",
            .spanish: "2×",
            .french: "2×"
        ],
        "scroll_reverser.step_max": [
            .german: "5×",
            .english: "5×",
            .spanish: "5×",
            .french: "5×"
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
            .german: "Bezeichnungen anzeigen",
            .english: "Show labels",
            .spanish: "Mostrar etiquetas",
            .french: "Afficher les libellés"
        ],
        "system_stats.opt_show_labels_tooltip": [
            .german: "Zeigt kurze Namen wie CPU, RAM und GPU in der Menüleiste an.",
            .english: "Shows short labels like CPU, RAM, and GPU in the menu bar.",
            .spanish: "Muestra etiquetas como CPU, RAM y GPU en la barra de menús.",
            .french: "Affiche les libellés CPU, RAM et GPU dans la barre des menus."
        ],
        "system_stats.opt_show_percentage": [
            .german: "Prozentwerte anzeigen",
            .english: "Show percentages",
            .spanish: "Mostrar porcentajes",
            .french: "Afficher les pourcentages"
        ],
        "system_stats.opt_show_graphs": [
            .german: "Graphen anzeigen",
            .english: "Show graphs",
            .spanish: "Mostrar gráficos",
            .french: "Afficher les graphiques"
        ],
        "system_stats.opt_subtle_background": [
            .german: "Dezenter Hintergrund",
            .english: "Subtle background",
            .spanish: "Fondo sutil",
            .french: "Arrière-plan discret"
        ],
        "system_stats.opt_subtle_background_tooltip": [
            .german: "Legt eine dezente abgerundete Fläche hinter die Anzeige in der Menüleiste.",
            .english: "Adds a subtle rounded backdrop behind the menu bar indicator.",
            .spanish: "Añade un fondo redondeado sutil detrás del indicador.",
            .french: "Ajoute un léger fond arrondi derrière l'indicateur."
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
            .german: "Ersatz-Symbol:",
            .english: "Fallback Symbol:",
            .spanish: "Icono de respaldo:",
            .french: "Symbole de secours :"
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
            .german: "Kompakt · 320 × 400",
            .english: "Compact · 320 × 400",
            .spanish: "Compacto · 320 × 400",
            .french: "Compact · 320 × 400"
        ],
        "web_panel.preset_smartphone": [
            .german: "Mobil · 375 × 667",
            .english: "Mobile · 375 × 667",
            .spanish: "Móvil · 375 × 667",
            .french: "Mobile · 375 × 667"
        ],
        "web_panel.preset_large": [
            .german: "Groß · 500 × 700",
            .english: "Large · 500 × 700",
            .spanish: "Grande · 500 × 700",
            .french: "Grand · 500 × 700"
        ],
        "web_panel.ua_auto": [
            .german: "Automatisch",
            .english: "Automatic",
            .spanish: "Automático",
            .french: "Automatique"
        ],
        "web_panel.ua_mobile": [
            .german: "Mobil",
            .english: "Mobile",
            .spanish: "Móvil",
            .french: "Mobile"
        ],
        "web_panel.ua_desktop": [
            .german: "Desktop",
            .english: "Desktop",
            .spanish: "Escritorio",
            .french: "Bureau"
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
            .german: "Darstellung",
            .english: "View Mode",
            .spanish: "Modo de vista",
            .french: "Mode d'affichage"
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
            .german: "Zoom",
            .english: "Zoom",
            .spanish: "Zoom",
            .french: "Zoom"
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
            .german: "Fenster anpinnen",
            .english: "Pin window",
            .spanish: "Fijar ventana",
            .french: "Épingler la fenêtre"
        ],
        "web_panel.popup_open_default_browser": [
            .german: "Im Standard-Browser öffnen",
            .english: "Open in default browser",
            .spanish: "Abrir en navegador predeterminado",
            .french: "Ouvrir dans le navigateur par défaut"
        ],
        "web_panel.load_failed_title": [
            .german: "Seite konnte nicht geladen werden",
            .english: "Page could not be loaded",
            .spanish: "No se pudo cargar la página",
            .french: "Impossible de charger la page"
        ],
        "web_panel.retry_load": [
            .german: "Erneut laden",
            .english: "Reload",
            .spanish: "Recargar",
            .french: "Recharger"
        ],
        "system_stats.layout_vertical": [
            .german: "Balken rechts",
            .english: "Bar Right",
            .spanish: "Barra derecha",
            .french: "Barre à droite"
        ],
        "system_stats.layout_vertical_bar_bottom": [
            .german: "Balken unten",
            .english: "Bar Below",
            .spanish: "Barra abajo",
            .french: "Barre en bas"
        ],
        "system_stats.layout_horizontal": [
            .german: "Nebeneinander",
            .english: "Side by Side",
            .spanish: "En línea",
            .french: "Côte à côte"
        ],
        "system_stats.graph_minibar": [
            .german: "Füllbalken",
            .english: "Fill Bar",
            .spanish: "Barra de llenado",
            .french: "Barre de remplissage"
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
            .german: "RAM",
            .english: "RAM",
            .spanish: "RAM",
            .french: "RAM"
        ],
        "system_stats.metric_gpu_label": [
            .german: "GPU",
            .english: "GPU",
            .spanish: "GPU",
            .french: "GPU"
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
        ],
        "finder_cut.title": [
            .german: "Finder Ausschneiden",
            .english: "Finder Cut",
            .spanish: "Cortar en Finder",
            .french: "Couper dans le Finder"
        ],
        "finder_cut.subtitle": [
            .german: "Dateien und Ordner im Finder wie unter Windows mit ⌘X ausschneiden und mit ⌘V verschieben.",
            .english: "Cut files and folders in Finder with ⌘X and move them with ⌘V, just like on Windows.",
            .spanish: "Corta archivos y carpetas en Finder con ⌘X y muévelos con ⌘V, como en Windows.",
            .french: "Coupez des fichiers et dossiers dans le Finder avec ⌘X et déplacez-les avec ⌘V, comme sous Windows."
        ],
        "finder_cut.permission_required": [
            .german: "Bedienungshilfen-Berechtigung erforderlich",
            .english: "Accessibility Permission Required",
            .spanish: "Se requiere permiso de accesibilidad",
            .french: "Autorisation d'accessibilité requise"
        ],
        "finder_cut.permission_description": [
            .german: "Damit Yeoman ⌘X und ⌘V ausschließlich im Finder umwandeln kann, wird die Bedienungshilfen-Freigabe benötigt.",
            .english: "Yeoman needs Accessibility permission to intercept ⌘X and ⌘V shortcuts strictly inside Finder.",
            .spanish: "Yeoman necesita permiso de accesibilidad para interceptar ⌘X y ⌘V únicamente en Finder.",
            .french: "Yeoman a besoin de l'autorisation d'accessibilité pour intercepter ⌘X et ⌘V uniquement dans le Finder."
        ],
        "finder_cut.how_it_works": [
            .german: "Tastenkürzel im Finder",
            .english: "Finder Shortcuts",
            .spanish: "Atajos en Finder",
            .french: "Raccourcis dans le Finder"
        ],
        "finder_cut.shortcut_cut": [
            .german: "Markierte Dateien oder Ordner zum Verschieben vormerken",
            .english: "Mark selected files or folders for moving",
            .spanish: "Marcar archivos o carpetas seleccionados para mover",
            .french: "Marquer les fichiers ou dossiers sélectionnés pour le déplacement"
        ],
        "finder_cut.shortcut_paste": [
            .german: "Ausgeschnittene Objekte im Zielordner einfügen",
            .english: "Move cut items into the target folder",
            .spanish: "Mover los elementos cortados a la carpeta de destino",
            .french: "Déplacer les éléments coupés vers le dossier cible"
        ],
        "finder_cut.shortcut_cancel": [
            .german: "Ausgeschnitten-Markierung sicher verwerfen",
            .english: "Cancel the pending cut state safely",
            .spanish: "Cancelar el estado de corte pendiente de forma segura",
            .french: "Annuler l'état de coupe en attente en toute sécurité"
        ],
        "finder_cut.text_safe_note": [
            .german: "Beim Umbenennen von Dateien oder in Such-/Textfeldern bleibt ⌘X normales Text-Ausschneiden.",
            .english: "When renaming files or typing in search/text fields, ⌘X continues to act as normal text cut.",
            .spanish: "Al renombrar archivos o escribir en campos de texto o búsqueda, ⌘X sigue funcionando como corte de texto normal.",
            .french: "Lors du renommage de fichiers ou dans les champs texte/recherche, ⌘X reste un couper de texte normal."
        ],
        "finder_cut.options_header": [
            .german: "Optionen",
            .english: "Options",
            .spanish: "Opciones",
            .french: "Options"
        ],
        "finder_cut.play_sound": [
            .german: "Dezentes Klick-Feedback beim Ausschneiden",
            .english: "Play subtle sound when cutting files",
            .spanish: "Reproducir un sonido sutil al cortar archivos",
            .french: "Jouer un son discret lors de la coupe"
        ],
        "finder_cut.play_sound_tooltip": [
            .german: "Spielt einen kurzen Systemton ab, sobald der Finder die Dateien zum Ausschneiden übernommen hat.",
            .english: "Plays a subtle system sound once Finder confirms the selected files are staged for moving.",
            .spanish: "Reproduce un breve sonido del sistema cuando Finder confirma los archivos listos para mover.",
            .french: "Joue un bref son système dès que le Finder confirme les fichiers prêts à être déplacés."
        ],
        "finder_cut.cancel_on_escape": [
            .german: "Mit Esc-Taste Ausschneiden abbrechen",
            .english: "Cancel pending cut with Escape key",
            .spanish: "Cancelar el corte pendiente con la tecla Esc",
            .french: "Annuler la coupe en attente avec la touche Échap"
        ],
        "finder_cut.cancel_on_escape_tooltip": [
            .german: "Setzt ein vorgemerktes Ausschneiden im Finder zurück, wenn Escape gedrückt wird.",
            .english: "Clears the pending Finder cut state when pressing Escape.",
            .spanish: "Limpia el estado de corte pendiente en Finder al pulsar Escape.",
            .french: "Réinitialise l'état de coupe dans le Finder lorsque vous appuyez sur Échap."
        ],
        "finder_cut.menubar_toggle": [
            .german: "Symbol in der Menüleiste anzeigen",
            .english: "Show icon in the menu bar",
            .spanish: "Mostrar icono en la barra de menús",
            .french: "Afficher l'icône dans la barre des menus"
        ],
        "finder_cut.menubar_tooltip": [
            .german: "Zeigt eine Schere in der Menüleiste für Schnellstatus und Abbruch eines aktiven Ausschneidens.",
            .english: "Shows a scissors icon in the menu bar for quick status and cancelling an active cut.",
            .spanish: "Muestra unas tijeras en la barra de menús para ver el estado rápido y cancelar un corte activo.",
            .french: "Affiche une icône de ciseaux dans la barre des menus pour voir l'état et annuler une coupe active."
        ],
        "finder_cut.status": [
            .german: "Status",
            .english: "Status",
            .spanish: "Estado",
            .french: "État"
        ],
        "finder_cut.status_active": [
            .german: "Aktiv",
            .english: "Active",
            .spanish: "Activo",
            .french: "Actif"
        ],
        "finder_cut.status_paused": [
            .german: "Pausiert",
            .english: "Paused",
            .spanish: "En pausa",
            .french: "En pause"
        ],
        "finder_cut.pending_active": [
            .german: "Ausschneiden aktiv – mit ⌘V im Zielordner verschieben",
            .english: "Cut pending – press ⌘V in destination folder to move",
            .spanish: "Corte pendiente: pulsa ⌘V en la carpeta de destino para mover",
            .french: "Coupe en attente – appuyez sur ⌘V dans le dossier cible pour déplacer"
        ],
        "finder_cut.pending_count_format": [
            .german: "%d Objekte zum Verschieben bereit",
            .english: "%d items ready to move",
            .spanish: "%d elementos listos para mover",
            .french: "%d éléments prêts à déplacer"
        ],
        "finder_cut.cancel_pending": [
            .german: "Ausschneiden verwerfen",
            .english: "Cancel Cut",
            .spanish: "Cancelar corte",
            .french: "Annuler la coupe"
        ],
        "finder_cut.prompt_window_title": [
            .german: "Bedienungshilfen erforderlich",
            .english: "Accessibility Permission Required",
            .spanish: "Permiso de accesibilidad requerido",
            .french: "Autorisation d'accessibilité requise"
        ],
        "finder_cut.prompt_title": [
            .german: "Finder Ausschneiden benötigt Berechtigung",
            .english: "Finder Cut Needs Permission",
            .spanish: "Cortar en Finder necesita permiso",
            .french: "Couper dans le Finder nécessite une autorisation"
        ],
        "finder_cut.prompt_message": [
            .german: "Du hast gerade ⌘X im Finder gedrückt, aber macOS blockiert aktuell den Zugriff auf Bedienungshilfen für Yeoman.",
            .english: "You just pressed ⌘X in Finder, but macOS is currently blocking Accessibility access for Yeoman.",
            .spanish: "Acabas de pulsar ⌘X en Finder, pero macOS está bloqueando actualmente el acceso de accesibilidad para Yeoman.",
            .french: "Vous venez d'appuyer sur ⌘X dans le Finder, mais macOS bloque actuellement l'accès d'accessibilité pour Yeoman."
        ],
        "finder_cut.prompt_steps": [
            .german: "Öffne Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen und aktiviere den Schalter neben Yeoman. Danach funktioniert ⌘X → ⌘V im Finder sofort.",
            .english: "Open System Settings → Privacy & Security → Accessibility and enable the toggle next to Yeoman. Afterwards, ⌘X → ⌘V in Finder works immediately.",
            .spanish: "Abre Ajustes del Sistema → Privacidad y seguridad → Accesibilidad y activa el interruptor junto a Yeoman. Después, ⌘X → ⌘V funcionará de inmediato.",
            .french: "Ouvrez Réglages Système → Confidentialité et sécurité → Accessibilité et activez Yeoman. Ensuite, ⌘X → ⌘V fonctionnera immédiatement."
        ],
        "finder_cut.prompt_disable": [
            .german: "Modul deaktivieren",
            .english: "Disable Module",
            .spanish: "Desactivar módulo",
            .french: "Désactiver le module"
        ],
        "finder_cut.prompt_later": [
            .german: "Später",
            .english: "Later",
            .spanish: "Más tarde",
            .french: "Plus tard"
        ],
        "finder_cut.show_hud": [
            .german: "Ausgeschnittene Dateien im Finder markieren",
            .english: "Highlight cut files in Finder",
            .spanish: "Resaltar archivos cortados en Finder",
            .french: "Surligner les fichiers coupés dans le Finder"
        ],
        "finder_cut.show_hud_tooltip": [
            .german: "Zeigt einen gestrichelten Rahmen direkt um ausgeschnittene Dateien im Finder an, bis sie eingefügt oder abgebrochen werden.",
            .english: "Draws a dashed pill outline directly around cut items in Finder until they are moved or cancelled.",
            .spanish: "Muestra un borde discontinuo alrededor de los archivos cortados en Finder hasta que se muevan o cancelen.",
            .french: "Affiche un contour en pointillés autour des fichiers coupés dans le Finder jusqu'à leur déplacement ou annulation."
        ],
        "general.terminal_saver_sub": [
            .german: "ASCII-Animationen im Terminal nach Inaktivität",
            .english: "ASCII animations in your terminal when idle",
            .spanish: "Animaciones ASCII en tu terminal al estar inactivo",
            .french: "Animations ASCII dans le terminal après inactivité"
        ],
        "terminal_saver.title": [
            .english: "Terminal Saver"
        ],
        "terminal_saver.subtitle": [
            .german: "Zeigt bei Inaktivität ASCII-Animationen im Terminal.",
            .english: "Displays ASCII animations in your terminal when idle.",
            .spanish: "Muestra animaciones ASCII en el terminal al estar inactivo.",
            .french: "Affiche des animations ASCII dans le terminal inactif."
        ],
        "terminal_saver.preview_header": [
            .german: "Live-Vorschau",
            .english: "Live Preview",
            .spanish: "Vista previa",
            .french: "Aperçu en direct"
        ],
        "terminal_saver.copy_test_command": [
            .german: "Test-Befehl kopieren",
            .english: "Copy Test Command",
            .spanish: "Copiar comando",
            .french: "Copier la commande"
        ],
        "terminal_saver.copied": [
            .german: "Kopiert!",
            .english: "Copied!",
            .spanish: "¡Copiado!",
            .french: "Copié !"
        ],
        "terminal_saver.media_header": [
            .german: "Szenen & Medien",
            .english: "Scenes & Media",
            .spanish: "Escenas y medios",
            .french: "Scènes et médias"
        ],
        "terminal_saver.shuffle_active_badge": [
            .german: "Zufällig · %d",
            .english: "Shuffle · %d",
            .spanish: "Aleatorio · %d",
            .french: "Aléatoire · %d"
        ],
        "terminal_saver.builtin_scenes": [
            .german: "Szenen",
            .english: "Scenes",
            .spanish: "Escenas",
            .french: "Scènes"
        ],
        "terminal_saver.scene_bonfire": [
            .german: "Lagerfeuer",
            .english: "Bonfire",
            .spanish: "Hoguera",
            .french: "Feu de camp"
        ],
        "terminal_saver.scene_bouncing_dvd": [
            .german: "Springendes DVD-Logo",
            .english: "Bouncing DVD Logo",
            .spanish: "Logo de DVD rebotante",
            .french: "Logo DVD rebondissant"
        ],
        "terminal_saver.scene_starfield": [
            .german: "Sternenhimmel",
            .english: "Starfield",
            .spanish: "Estrellas",
            .french: "Étoiles"
        ],
        "terminal_saver.scene_wind_meadow": [
            .german: "Gras im Wind",
            .english: "Wind Meadow",
            .spanish: "Pradera",
            .french: "Prairie"
        ],
        "terminal_saver.scene_matrix": [
            .german: "Matrix",
            .english: "Matrix",
            .spanish: "Matrix",
            .french: "Matrix"
        ],
        "terminal_saver.scene_game_of_life": [
            .german: "Game of Life",
            .english: "Game of Life",
            .spanish: "Juego de la vida",
            .french: "Jeu de la vie"
        ],
        "terminal_saver.scene_pipes": [
            .german: "Rohre",
            .english: "Pipes",
            .spanish: "Tuberías",
            .french: "Tuyaux"
        ],
        "terminal_saver.scene_spinning_donut": [
            .german: "3D-Donut",
            .english: "3D Donut",
            .spanish: "Donut 3D",
            .french: "Donut 3D"
        ],
        "terminal_saver.custom_media": [
            .german: "Eigene Medien",
            .english: "Custom Media",
            .spanish: "Medios propios",
            .french: "Médias"
        ],
        "terminal_saver.custom_media_tooltip": [
            .german: "Unterstützt GIF, PNG, JPG, WebP, HEIC sowie kurze MP4- und MOV-Clips.",
            .english: "Supports GIF, PNG, JPG, WebP, HEIC, and short MP4 or MOV clips.",
            .spanish: "Compatible con GIF, PNG, JPG, WebP, HEIC y clips MP4 o MOV cortos.",
            .french: "Prend en charge GIF, PNG, JPG, WebP, HEIC et les courts clips MP4 ou MOV."
        ],
        "terminal_saver.add_media": [
            .german: "Hinzufügen",
            .english: "Add Media",
            .spanish: "Añadir",
            .french: "Ajouter"
        ],
        "terminal_saver.no_media_hint": [
            .german: "Noch keine Dateien hinzugefügt.",
            .english: "No files added yet.",
            .spanish: "Aún no hay archivos.",
            .french: "Aucun fichier ajouté."
        ],
        "terminal_saver.general_header": [
            .german: "Allgemein",
            .english: "General",
            .spanish: "General",
            .french: "Général"
        ],
        "terminal_saver.fit_mode": [
            .german: "Anpassung",
            .english: "Fit",
            .spanish: "Ajuste",
            .french: "Ajustement"
        ],
        "terminal_saver.fit_contain": [
            .german: "Einpassen",
            .english: "Contain",
            .spanish: "Ajustar",
            .french: "Contenir"
        ],
        "terminal_saver.fit_cover": [
            .german: "Ausfüllen",
            .english: "Fill",
            .spanish: "Rellenar",
            .french: "Remplir"
        ],
        "terminal_saver.idle_timeout": [
            .german: "Wartezeit",
            .english: "Idle Time",
            .spanish: "Espera",
            .french: "Délai"
        ],
        "terminal_saver.idle_timeout_tooltip": [
            .german: "Startet Terminal Saver, wenn das Terminal so lange inaktiv war.",
            .english: "Starts Terminal Saver after this period of inactivity in your terminal.",
            .spanish: "Inicia Terminal Saver tras este tiempo de inactividad en el terminal.",
            .french: "Lance Terminal Saver après cette durée d'inactivité dans le terminal."
        ],
        "terminal_saver.render_style": [
            .german: "Stil",
            .english: "Style",
            .spanish: "Estilo",
            .french: "Style"
        ],
        "terminal_saver.style_filigree": [
            .german: "Filigran",
            .english: "Filigree",
            .spanish: "Filigrana",
            .french: "Filigrane"
        ],
        "terminal_saver.style_ultrafine": [
            .german: "Fein",
            .english: "Fine",
            .spanish: "Fino",
            .french: "Fin"
        ],
        "terminal_saver.style_dense": [
            .german: "Dicht",
            .english: "Dense",
            .spanish: "Denso",
            .french: "Dense"
        ],
        "terminal_saver.style_unicode": [
            .german: "Striche",
            .english: "Strokes",
            .spanish: "Trazos",
            .french: "Traits"
        ],
        "terminal_saver.color_preset": [
            .german: "Farben",
            .english: "Colors",
            .spanish: "Colores",
            .french: "Couleurs"
        ],
        "terminal_saver.color_original": [
            .german: "Original",
            .english: "Original",
            .spanish: "Original",
            .french: "Original"
        ],
        "terminal_saver.color_phosphor": [
            .german: "Phosphor",
            .english: "Phosphor",
            .spanish: "Fósforo",
            .french: "Phosphore"
        ],
        "terminal_saver.color_amber": [
            .german: "Bernstein",
            .english: "Amber",
            .spanish: "Ámbar",
            .french: "Ambre"
        ],
        "terminal_saver.color_moonlit": [
            .german: "Cyan",
            .english: "Cyan",
            .spanish: "Cian",
            .french: "Cyan"
        ],
        "terminal_saver.color_bloodmoon": [
            .german: "Rot",
            .english: "Crimson",
            .spanish: "Rojo",
            .french: "Rouge"
        ],
        "terminal_saver.wake_animation": [
            .german: "End-Animation",
            .english: "End Animation",
            .spanish: "Animación final",
            .french: "Animation de sortie"
        ],
        "terminal_saver.wake_dissolve": [
            .german: "Auflösen",
            .english: "Dissolve",
            .spanish: "Disolver",
            .french: "Fondu"
        ],
        "terminal_saver.wake_curtain": [
            .german: "Vorhang",
            .english: "Curtain",
            .spanish: "Cortina",
            .french: "Rideau"
        ],
        "terminal_saver.wake_cascade": [
            .german: "Kaskade",
            .english: "Cascade",
            .spanish: "Cascada",
            .french: "Cascade"
        ],
        "terminal_saver.wake_glitch": [
            .german: "Glitch",
            .english: "Glitch",
            .spanish: "Glitch",
            .french: "Glitch"
        ],
        "terminal_saver.wake_iris": [
            .german: "Blende",
            .english: "Iris",
            .spanish: "Iris",
            .french: "Iris"
        ],
        "terminal_saver.wake_instant": [
            .german: "Keine",
            .english: "None",
            .spanish: "Ninguna",
            .french: "Aucune"
        ],
        "terminal_saver.shells_header": [
            .german: "Terminal-Integration",
            .english: "Terminal Integration",
            .spanish: "Integración de terminal",
            .french: "Intégration terminal"
        ],
        "terminal_saver.shells_subtitle": [
            .german: "Funktioniert in Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, WezTerm, Warp und integrierten IDE-Terminals.",
            .english: "Works across Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, WezTerm, Warp, and integrated IDE terminals.",
            .spanish: "Funciona en Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, WezTerm, Warp y terminales de IDE.",
            .french: "Fonctionne dans Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, WezTerm, Warp et terminaux d'IDE."
        ],
        "terminal_saver.menubar_toggle": [
            .german: "In Menüleiste anzeigen",
            .english: "Show in Menu Bar",
            .spanish: "Mostrar en la barra de menús",
            .french: "Afficher dans la barre des menus"
        ],
        "terminal_saver.timeout_format": [
            .german: "Timeout: %d Sekunden",
            .english: "Timeout: %d seconds",
            .spanish: "Espera: %d segundos",
            .french: "Délai : %d secondes"
        ],
        "terminal_saver.loading_preview": [
            .german: "Vorschau wird vorbereitet…",
            .english: "Preparing preview…",
            .spanish: "Preparando vista previa…",
            .french: "Préparation de l'aperçu…"
        ],
        "terminal_saver.scene_settings_format": [
            .german: "Einstellungen für %@",
            .english: "Settings for %@",
            .spanish: "Ajustes de %@",
            .french: "Réglages de %@"
        ],
        "terminal_saver.playback_speed": [
            .german: "Geschwindigkeit",
            .english: "Speed",
            .spanish: "Velocidad",
            .french: "Vitesse"
        ],
        "terminal_saver.ping_pong_loop": [
            .german: "Vorwärts-rückwärts-Schleife",
            .english: "Forward and Reverse Loop",
            .spanish: "Bucle de ida y vuelta",
            .french: "Boucle aller-retour"
        ],
        "terminal_saver.ping_pong_loop_tooltip": [
            .german: "Spielt den Clip abwechselnd vorwärts und rückwärts ab.",
            .english: "Alternates between playing the clip forward and backward.",
            .spanish: "Reproduce el clip hacia delante y hacia atrás de forma alternada.",
            .french: "Lit le clip alternativement à l’endroit et à l’envers."
        ],
        "terminal_saver.start_animation": [
            .german: "Start-Animation",
            .english: "Start Animation",
            .spanish: "Animación inicial",
            .french: "Animation d'entrée"
        ],
        "terminal_saver.start_instant": [
            .german: "Keine",
            .english: "None",
            .spanish: "Ninguna",
            .french: "Aucune"
        ],
        "terminal_saver.remove_background": [
            .german: "Hintergrund entfernen",
            .english: "Remove Background",
            .spanish: "Quitar fondo",
            .french: "Retirer l'arrière-plan"
        ],
        "terminal_saver.remove_background_tooltip": [
            .german: "Stellt das Hauptmotiv lokal auf diesem Mac frei, sodass der Hintergrund leer bleibt.",
            .english: "Separates the foreground subject on-device so the background stays blank.",
            .spanish: "Separa el sujeto localmente en este Mac para dejar el fondo limpio.",
            .french: "Isole le sujet localement sur ce Mac pour laisser l'arrière-plan vide."
        ],
        "terminal_saver.animation_speed_tooltip": [
            .german: "Animationsgeschwindigkeit",
            .english: "Animation Speed",
            .spanish: "Velocidad de animación",
            .french: "Vitesse d'animation"
        ],
        "terminal_saver.animation_random": [
            .german: "Zufällig",
            .english: "Random",
            .spanish: "Aleatorio",
            .french: "Aléatoire"
        ],
        "terminal_saver.transition_animation": [
            .german: "Wechsel-Animation",
            .english: "Switch Animation",
            .spanish: "Animación de cambio",
            .french: "Transition"
        ],
        "terminal_saver.transition_slide": [
            .german: "Schieben",
            .english: "Slide",
            .spanish: "Deslizar",
            .french: "Glisser"
        ],
        "terminal_saver.transition_dissolve": [
            .german: "Überblenden",
            .english: "Crossfade",
            .spanish: "Fundido",
            .french: "Fondu"
        ],
        "terminal_saver.transition_wipe": [
            .german: "Wischen",
            .english: "Wipe",
            .spanish: "Barrido",
            .french: "Balayage"
        ],
        "terminal_saver.transition_glitch": [
            .german: "Glitch",
            .english: "Glitch",
            .spanish: "Glitch",
            .french: "Glitch"
        ],
        "terminal_saver.transition_swarm": [
            .german: "Schwarm",
            .english: "Swarm",
            .spanish: "Enjambre",
            .french: "Essaim"
        ],
        "terminal_saver.transition_decode": [
            .german: "Entschlüsseln",
            .english: "Decode",
            .spanish: "Descifrar",
            .french: "Déchiffrer"
        ],
        "terminal_saver.transition_morph": [
            .german: "Morph",
            .english: "Morph",
            .spanish: "Transformar",
            .french: "Morph"
        ],
        "terminal_saver.transition_shatter": [
            .german: "Zerfall",
            .english: "Shatter",
            .spanish: "Fragmentar",
            .french: "Éclat"
        ],
        "terminal_saver.transition_rain": [
            .german: "Zeichenregen",
            .english: "ASCII Rain",
            .spanish: "Lluvia ASCII",
            .french: "Pluie ASCII"
        ],
        "terminal_saver.transition_ripple": [
            .german: "Schockwelle",
            .english: "Shockwave",
            .spanish: "Onda",
            .french: "Onde"
        ],
        "terminal_saver.transition_instant": [
            .german: "Keine",
            .english: "None",
            .spanish: "Ninguna",
            .french: "Aucune"
        ],
        "terminal_saver.auto_advance": [
            .german: "Automatisch weiterschalten",
            .english: "Auto-Advance",
            .spanish: "Avance automático",
            .french: "Avance automatique"
        ],
        "terminal_saver.auto_advance_tooltip": [
            .german: "Schaltet im Terminal ab der eingestellten Dauer weiter, wenn mindestens zwei Quellen aktiv sind. Wahlweise wird zuerst die laufende Schleife beendet oder sofort gewechselt.",
            .english: "Advances in the terminal after the set time when at least two sources are active. Either finishes the current loop first or cuts immediately.",
            .spanish: "Pasa a la siguiente fuente en el terminal tras el tiempo indicado si hay al menos dos activas. Puede terminar el bucle actual o cambiar de inmediato.",
            .french: "Passe à la source suivante dans le terminal après le délai choisi si au moins deux sources sont actives. Termine la boucle en cours ou coupe immédiatement."
        ],
        "terminal_saver.auto_advance_duration": [
            .german: "Dauer pro Animation", .english: "Time per Animation", .spanish: "Tiempo por animación", .french: "Durée par animation"
        ],
        "terminal_saver.auto_advance_cutoff": [
            .german: "Bei Zeitablauf",
            .english: "At Time Limit",
            .spanish: "Al cumplirse el tiempo",
            .french: "À la fin du délai"
        ],
        "terminal_saver.auto_advance_finish_loop": [
            .german: "Loop beenden",
            .english: "Finish Loop",
            .spanish: "Terminar bucle",
            .french: "Finir la boucle"
        ],
        "terminal_saver.auto_advance_hard_cut": [
            .german: "Harter Schnitt",
            .english: "Hard Cut",
            .spanish: "Corte directo",
            .french: "Coupure nette"
        ],
        "terminal_saver.navigation_keys": [
            .german: "Navigation",
            .english: "Navigation",
            .spanish: "Navegación",
            .french: "Navigation"
        ],
        "terminal_saver.navigation_keys_tooltip": [
            .german: "Wechselt in Terminal Saver zur nächsten oder vorherigen Animation. Klicke auf eine Taste, um sie zu ändern.",
            .english: "Moves to the next or previous animation in Terminal Saver. Click a key to change it.",
            .spanish: "Cambia a la animación siguiente o anterior en Terminal Saver. Haz clic en una tecla para cambiarla.",
            .french: "Passe à l’animation suivante ou précédente dans Terminal Saver. Cliquez sur une touche pour la modifier."
        ],
        "terminal_saver.nav_previous": [
            .german: "Zurück",
            .english: "Previous",
            .spanish: "Anterior",
            .french: "Précédent"
        ],
        "terminal_saver.nav_next": [
            .german: "Weiter",
            .english: "Next",
            .spanish: "Siguiente",
            .french: "Suivant"
        ],
        "terminal_saver.press_key": [
            .german: "Taste…",
            .english: "Key…",
            .spanish: "Tecla…",
            .french: "Touche…"
        ],
        "terminal_saver.search_media": [
            .german: "Clips suchen…",
            .english: "Search clips…",
            .spanish: "Buscar clips…",
            .french: "Rechercher…"
        ],
        "terminal_saver.no_search_results": [
            .german: "Keine passenden Clips gefunden.",
            .english: "No matching clips found.",
            .spanish: "No se encontraron clips.",
            .french: "Aucun clip correspondant."
        ],
        "terminal_saver.rename_clip_placeholder": [
            .german: "Clip-Name",
            .english: "Clip Name",
            .spanish: "Nombre del clip",
            .french: "Nom du clip"
        ],

        // Battery Monitor
        "tab.batteryMonitor": [
            .german: "Batterie & Energie",
            .english: "Battery & Energy",
            .spanish: "Batería y Energía",
            .french: "Batterie & Énergie"
        ],
        "general.battery_monitor_title": [
            .german: "Batterie & Energie",
            .english: "Battery & Energy",
            .spanish: "Batería y Energía",
            .french: "Batterie & Énergie"
        ],
        "general.battery_monitor_sub": [
            .german: "24h-Akkuverlauf, Bildschirmzeit und App-Stromverbrauch in der Menüleiste.",
            .english: "24h battery level history, screen-on usage, and per-app energy tracking.",
            .spanish: "Historial de batería 24h, uso de pantalla y consumo por app.",
            .french: "Historique batterie 24h, temps d'écran et consommation par app."
        ],
        "battery.settings_subtitle": [
            .german: "Akkuverlauf über 24 Stunden und Energieverbrauch nach App",
            .english: "24-hour battery history and per-app energy breakdown",
            .spanish: "Historial de 24 horas y consumo energético por app",
            .french: "Historique 24 heures et consommation d'énergie par application"
        ],
        "battery.menubar_tooltip": [
            .german: "Batterie & Energieverbrauch (Klick für 24h-Übersicht)",
            .english: "Battery & Energy Usage (Click for 24h overview)",
            .spanish: "Batería y consumo energético",
            .french: "Batterie et consommation d'énergie"
        ],
        "battery.menu_open_overview": [
            .german: "Batterie-Übersicht öffnen",
            .english: "Open Battery Overview",
            .spanish: "Abrir resumen de batería",
            .french: "Ouvrir l'aperçu batterie"
        ],
        "battery.menubar_display": [
            .german: "Menüleisten-Anzeige",
            .english: "Menu Bar Display",
            .spanish: "Visualización en barra de menús",
            .french: "Affichage dans la barre des menus"
        ],
        "battery.style_icon_percent": [
            .german: "Batterie-Symbol + Prozent (z. B. 74%)",
            .english: "Battery Icon + Percentage (e.g. 74%)",
            .spanish: "Icono + Porcentaje",
            .french: "Icône + Pourcentage"
        ],
        "battery.style_icon_percent_watts": [
            .german: "Symbol + Prozent + Leistung (z. B. 74% -12W)",
            .english: "Icon + Percentage + Wattage (e.g. 74% -12W)",
            .spanish: "Icono + Porcentaje + Vatios",
            .french: "Icône + Pourcentage + Watts"
        ],
        "battery.style_icon_only": [
            .german: "Nur Batterie-Symbol",
            .english: "Battery Icon Only",
            .spanish: "Solo icono de batería",
            .french: "Icône uniquement"
        ],
        "battery.style_percent_only": [
            .german: "Nur Prozentzahl",
            .english: "Percentage Only",
            .spanish: "Solo porcentaje",
            .french: "Pourcentage uniquement"
        ],
        "battery.hardware_diagnostics": [
            .german: "Akku-Zustand & Leistung",
            .english: "Battery Health & Power",
            .spanish: "Salud y potencia",
            .french: "État et puissance"
        ],
        "battery.history_storage": [
            .german: "Verlauf & Aufzeichnung",
            .english: "History & Recording",
            .spanish: "Historial y registro",
            .french: "Historique et enregistrement"
        ],
        "battery.history_storage_desc": [
            .german: "Der Batteriestatus der letzten 24 Stunden wird aus macOS-Energieprotokollen ergänzt und ab App-Start zusammen mit dem Energieverbrauch jeder App lokal gespeichert.",
            .english: "24-hour battery charge and screen-on history are bootstrapped from macOS power logs and saved locally alongside per-app energy measurements.",
            .spanish: "El historial de 24h y el consumo por app se almacenan localmente.",
            .french: "L'historique 24h et la consommation par app sont enregistrés localement."
        ],
        "battery.clear_history": [
            .german: "Verlauf zurücksetzen",
            .english: "Clear History",
            .spanish: "Borrar historial",
            .french: "Effacer l'historique"
        ],
        "battery.range_live": [
            .german: "Live",
            .english: "Live",
            .spanish: "En vivo",
            .french: "En direct"
        ],
        "battery.range_1h": [
            .german: "1 Std.",
            .english: "1h",
            .spanish: "1 h",
            .french: "1 h"
        ],
        "battery.range_6h": [
            .german: "6 Std.",
            .english: "6h",
            .spanish: "6 h",
            .french: "6 h"
        ],
        "battery.range_24h": [
            .german: "24 Std.",
            .english: "24h",
            .spanish: "24 h",
            .french: "24 h"
        ],
        "battery.range_since_launch": [
            .german: "Seit Start",
            .english: "Since Launch",
            .spanish: "Desde inicio",
            .french: "Depuis lancement"
        ],
        "battery.low_power_mode": [
            .german: "Energiesparmodus",
            .english: "Low Power Mode",
            .spanish: "Bajo consumo",
            .french: "Économie d'énergie"
        ],
        "battery.no_battery": [
            .german: "Kein interner Akku erkannt (Netzbetrieb)",
            .english: "No internal battery detected (AC power)",
            .spanish: "Sin batería interna",
            .french: "Aucune batterie détectée"
        ],
        "battery.refresh_tooltip": [
            .german: "Messwerte jetzt aktualisieren",
            .english: "Refresh readings now",
            .spanish: "Actualizar ahora",
            .french: "Actualiser maintenant"
        ],
        "battery.health": [
            .german: "Kapazität",
            .english: "Health",
            .spanish: "Salud",
            .french: "Santé"
        ],
        "battery.cycles": [
            .german: "Zyklen",
            .english: "Cycles",
            .spanish: "Ciclos",
            .french: "Cycles"
        ],
        "battery.temp": [
            .german: "Temp.",
            .english: "Temp",
            .spanish: "Temp.",
            .french: "Temp."
        ],
        "battery.capacity": [
            .german: "Ladung",
            .english: "Charge",
            .spanish: "Carga",
            .french: "Charge"
        ],
        "battery.power_flow": [
            .german: "Leistung",
            .english: "Power Flow",
            .spanish: "Potencia",
            .french: "Puissance"
        ],
        "battery.ac_only": [
            .german: "Netzteil",
            .english: "AC Power",
            .spanish: "Corriente",
            .french: "Secteur"
        ],
        "battery.charging": [
            .german: "Lädt über Netzteil",
            .english: "Charging on AC",
            .spanish: "Cargando",
            .french: "En charge"
        ],
        "battery.fully_charged": [
            .german: "Vollständig geladen",
            .english: "Fully Charged",
            .spanish: "Carga completa",
            .french: "Chargée"
        ],
        "battery.on_ac": [
            .german: "Netzteil (Erhaltung)",
            .english: "Power Adapter",
            .spanish: "Adaptador",
            .french: "Adaptateur secteur"
        ],
        "battery.on_battery": [
            .german: "Stromversorgung: Batterie",
            .english: "Power Source: Battery",
            .spanish: "Fuente: Batería",
            .french: "Source : Batterie"
        ],
        "battery.charging_short": [
            .german: "Lädt",
            .english: "Charging",
            .spanish: "Cargando",
            .french: "En charge"
        ],
        "battery.on_battery_short": [
            .german: "Batterie",
            .english: "Battery",
            .spanish: "Batería",
            .french: "Batterie"
        ],
        "battery.chart_status": [
            .german: "Batteriestatus (24 Std.)",
            .english: "Battery Level (24h)",
            .spanish: "Nivel de batería (24h)",
            .french: "Niveau de batterie (24h)"
        ],
        "battery.chart_screen_on": [
            .german: "Nutzung bei eingeschaltetem Bildschirm",
            .english: "Screen On Usage",
            .spanish: "Uso con pantalla encendida",
            .french: "Utilisation écran allumé"
        ],
        "battery.loading_history": [
            .german: "Lade Verlauf…",
            .english: "Loading history…",
            .spanish: "Cargando historial…",
            .french: "Chargement…"
        ],
        "battery.total_24h": [
            .german: "Gesamt",
            .english: "Total",
            .spanish: "Total",
            .french: "Total"
        ],
        "battery.app_usage_title": [
            .german: "Energieverbrauch nach App",
            .english: "Energy Usage by App",
            .spanish: "Consumo por aplicación",
            .french: "Consommation par app"
        ],
        "battery.no_app_samples_yet": [
            .german: "Sammle Energie-Messwerte für aktive Apps — erste Ergebnisse erscheinen in wenigen Sekunden.",
            .english: "Collecting per-app energy counters — initial readings appear in a few seconds.",
            .spanish: "Recopilando datos de energía por app…",
            .french: "Collecte des données d'énergie par app…"
        ],
        "battery.significant_badge": [
            .german: "Erheblich",
            .english: "Significant",
            .spanish: "Significativo",
            .french: "Élevée"
        ],
        "battery.share_short": [
            .german: "Anteil",
            .english: "share",
            .spanish: "cuota",
            .french: "part"
        ],
        "battery.open_macos_settings": [
            .german: "Batterieeinstellungen…",
            .english: "Battery Settings…",
            .spanish: "Ajustes de batería…",
            .french: "Réglages batterie…"
        ],
        "battery.yeoman_settings": [
            .german: "Yeoman",
            .english: "Yeoman",
            .spanish: "Yeoman",
            .french: "Yeoman"
        ],
        "battery.recording_since_format": [
            .german: "Erfasst seit %@",
            .english: "Tracking since %@",
            .spanish: "Registrando desde %@",
            .french: "Suivi depuis %@"
        ]
    ]
}

public extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

public func l10n(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}

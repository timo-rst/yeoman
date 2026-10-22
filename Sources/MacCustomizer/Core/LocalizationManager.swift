import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    
    public var id: String { rawValue }
    
    public var flag: String {
        switch self {
        case .system: return "🌐"
        case .german: return "🇩🇪"
        case .english: return "🇬🇧"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        }
    }
    
    public var nativeName: String {
        switch self {
        case .system:
            return LocalizationManager.shared.localized("lang.system")
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
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    private let storageKey = "app_language"
    
    @Published public var selectedLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }
    
    public init() {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: stored) {
            self.selectedLanguage = lang
        } else {
            self.selectedLanguage = .system
        }
    }
    
    public var effectiveLanguage: AppLanguage {
        if selectedLanguage != .system {
            return selectedLanguage
        }
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let code = preferred.prefix(2).lowercased()
        switch code {
        case "de": return .german
        case "es": return .spanish
        case "fr": return .french
        default: return .english
        }
    }
    
    public func localized(_ key: String) -> String {
        let lang = effectiveLanguage
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
            .german: "MacCustomizer Einstellungen",
            .english: "MacCustomizer Settings",
            .spanish: "Configuración de MacCustomizer",
            .french: "Paramètres de MacCustomizer"
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
            .german: "Über MacCustomizer",
            .english: "About MacCustomizer",
            .spanish: "Acerca de MacCustomizer",
            .french: "À propos de MacCustomizer"
        ],
        
        // General Settings View
        "general.title": [
            .german: "Allgemeine Einstellungen",
            .english: "General Settings",
            .spanish: "Configuración general",
            .french: "Paramètres généraux"
        ],
        "general.subtitle": [
            .german: "Grundkonfiguration für Sprache, Startverhalten und Systemintegration.",
            .english: "Basic configuration for language, startup behavior, and system integration.",
            .spanish: "Configuración básica para idioma, inicio e integración con el sistema.",
            .french: "Configuration de base pour la langue, le démarrage et l'intégration système."
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
            .german: "Startet MacCustomizer automatisch beim Hochfahren deines Macs (Launch at Login).",
            .english: "Starts MacCustomizer automatically when your Mac boots up (Launch at Login).",
            .spanish: "Inicia MacCustomizer automáticamente cuando tu Mac se enciende (Launch at Login).",
            .french: "Lance MacCustomizer automatiquement au démarrage de votre Mac (Launch at Login)."
        ],
        "general.show_dock_icon": [
            .german: "Dock-Symbol anzeigen",
            .english: "Show Dock icon",
            .spanish: "Mostrar icono en el Dock",
            .french: "Afficher l'icône dans le Dock"
        ],
        "general.show_dock_icon_tooltip": [
            .german: "Bestimmt, ob MacCustomizer im Dock sichtbar ist. Wenn deaktiviert, läuft die App rein in der Menüleiste.",
            .english: "Determines whether MacCustomizer is visible in the Dock. When disabled, the app runs purely in the menu bar.",
            .spanish: "Determina si MacCustomizer es visible en el Dock. Si se desactiva, la aplicación solo se ejecuta en la barra de menús.",
            .french: "Détermine si MacCustomizer est visible dans le Dock. Si désactivé, l'application fonctionne uniquement dans la barre des menus."
        ],
        "general.show_main_status_item": [
            .german: "Haupt-Symbol in der Menüleiste anzeigen",
            .english: "Show main icon in menu bar",
            .spanish: "Mostrar icono principal en la barra de menús",
            .french: "Afficher l'icône principale dans la barre des menus"
        ],
        "general.show_main_status_item_tooltip": [
            .german: "Zeigt das MacCustomizer Hauptsymbol (Launcher) in der Menüleiste an, über das du schnellen Zugriff auf alle Module hast.",
            .english: "Shows the MacCustomizer main launcher icon in the menu bar for quick access to all modules.",
            .spanish: "Muestra el icono principal de MacCustomizer en la barra de menús para acceder rápidamente a todos los módulos.",
            .french: "Affiche l'icône principale de MacCustomizer dans la barre des menus pour un accès rapide à tous les modules."
        ],
        "general.active_modules": [
            .german: "Aktive Module & Menüleisten-Symbole",
            .english: "Active Modules & Menu Bar Icons",
            .spanish: "Módulos activos e iconos de la barra de menús",
            .french: "Modules actifs et icônes de la barre des menus"
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
            .german: "MacCustomizer beenden",
            .english: "Quit MacCustomizer",
            .spanish: "Salir de MacCustomizer",
            .french: "Quitter MacCustomizer"
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
        "updates.up_to_date": [
            .german: "MacCustomizer ist auf dem neuesten Stand",
            .english: "MacCustomizer is up to date",
            .spanish: "MacCustomizer está actualizado",
            .french: "MacCustomizer est à jour"
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
        
        // Web Panel
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
        ]
    ]
}

public extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

public func l10n(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}

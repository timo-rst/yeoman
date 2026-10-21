import AppKit
import Combine

public struct DisplayInfo: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let frame: NSRect
    public let visibleFrame: NSRect
    public let isMain: Bool
    public let hasNotch: Bool
    public let backingScaleFactor: CGFloat
    
    public var menuBarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }
}

public final class DisplayManager: ObservableObject {
    public static let shared = DisplayManager()
    
    @Published public private(set) var displays: [DisplayInfo] = []
    @Published public private(set) var mainDisplay: DisplayInfo?
    @Published public private(set) var hasMultipleDisplays: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        refreshDisplays()
        setupNotificationObserver()
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDisplays()
            }
            .store(in: &cancellables)
    }
    
    public func refreshDisplays() {
        let screens = NSScreen.screens
        var updatedDisplays: [DisplayInfo] = []
        
        for (index, screen) in screens.enumerated() {
            let isMain = screen == NSScreen.main
            let hasNotch = screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            
            let info = DisplayInfo(
                id: "\(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? index)",
                name: name,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: isMain,
                hasNotch: hasNotch,
                backingScaleFactor: screen.backingScaleFactor
            )
            updatedDisplays.append(info)
        }
        
        self.displays = updatedDisplays
        self.mainDisplay = updatedDisplays.first(where: { $0.isMain }) ?? updatedDisplays.first
        self.hasMultipleDisplays = updatedDisplays.count > 1
    }
}

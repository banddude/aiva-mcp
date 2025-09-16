import Foundation
import AppKit
import SwiftUI
import OSLog

private let log = Logger.service("appicons")

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()
    
    private var cachedIcons: [String: String] = [:]
    private let fallbackIcons: [String: String] = [
        "Calendar": "calendar",
        "Contacts": "person.crop.square.filled.and.at.rectangle.fill",
        "Mail": "envelope.fill",
        "Messages": "message.fill",
        "Music": "music.note",
        "Reminders": "list.bullet",
        "Maps": "mappin.and.ellipse",
        "Weather": "cloud.sun.fill",
        "Capture": "camera.on.rectangle.fill",
        "Utilities": "wrench.and.screwdriver",
        "Chrome": "chrome-logo",
        "Location": "location.circle.fill",
        "Memory": "brain",
        "Speech": "waveform.circle.fill",
        "Safari": "safari"
    ]
    
    private let bundleIdentifiers: [String: String] = [
        "Calendar": "com.apple.ical",
        "Contacts": "com.apple.AddressBook", 
        "Mail": "com.apple.mail",
        "Messages": "com.apple.MobileSMS",
        "Music": "com.apple.Music",
        "Reminders": "com.apple.reminders",
        "Maps": "com.apple.Maps",
        "Weather": "com.apple.weather",
        "Capture": "com.apple.screenshot",
        "Utilities": "com.apple.systempreferences",
        "Chrome": "com.google.Chrome",
        "Location": "com.apple.CoreLocation",
        "Safari": "com.apple.Safari",
        "Speech": "com.apple.speech.speechsynthesismanager"
    ]
    
    private init() {}
    
    func loadAppIcons() {
        log.info("Loading system app icons...")
        
        for (serviceName, bundleID) in self.bundleIdentifiers {
            if let iconName = self.extractAppIcon(serviceName: serviceName, bundleID: bundleID) {
                self.cachedIcons[serviceName] = iconName
                log.info("Loaded icon for \(serviceName): \(iconName)")
            } else {
                self.cachedIcons[serviceName] = self.fallbackIcons[serviceName]
                log.warning("Using fallback icon for \(serviceName): \(self.fallbackIcons[serviceName] ?? "unknown")")
            }
        }
        
        log.info("App icon loading complete. Loaded \(self.cachedIcons.count) icons.")
    }
    
    func getIconName(for serviceName: String) -> String {
        return self.cachedIcons[serviceName] ?? self.fallbackIcons[serviceName] ?? "app"
    }
    
    func getServerIcon(for serverType: ServerType) -> String {
        switch serverType {
        case .sse:
            return "externaldrive.badge.icloud"
        case .subprocess:
            return "externaldrive.connected.to.line.below"
        }
    }
    
    func getServerColor(for serverType: ServerType) -> Color {
        switch serverType {
        case .sse:
            return .white.opacity(0.9)
        case .subprocess:
            return .white.opacity(0.9)
        }
    }
    
    func shouldUseMulticolorRendering(for iconName: String) -> Bool {
        return iconName == getServerIcon(for: .sse) || iconName == getServerIcon(for: .subprocess)
    }
    
    func getForegroundColor(for iconName: String, isEnabled: Bool, defaultColor: Color) -> Color? {
        if shouldUseMulticolorRendering(for: iconName) {
            return nil // Let multicolor icons use their natural colors
        }
        return defaultColor
    }
    
    private func extractAppIcon(serviceName: String, bundleID: String) -> String? {
        // Special handling for Screenshot app
        if serviceName == "Capture" {
            let screenshotPath = "/System/Applications/Utilities/Screenshot.app"
            if FileManager.default.fileExists(atPath: screenshotPath) {
                let appIcon = NSWorkspace.shared.icon(forFile: screenshotPath)
                let iconName = "app_icon_\(serviceName.lowercased())"
                if self.saveIconAsAsset(icon: appIcon, name: iconName) {
                    return iconName
                }
            }
        }
        
        // Try to find the app by bundle identifier
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.warning("Could not find app for bundle ID: \(bundleID)")
            return nil
        }
        
        // Get the app icon
        let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        // Create a unique name for this icon
        let iconName = "app_icon_\(serviceName.lowercased())"
        
        // Save the icon as an image asset that can be referenced
        if self.saveIconAsAsset(icon: appIcon, name: iconName) {
            return iconName
        }
        
        return nil
    }
    
    private func saveIconAsAsset(icon: NSImage, name: String) -> Bool {
        // Convert NSImage to PNG data
        guard let tiffData = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            log.error("Could not convert icon to PNG data")
            return false
        }
        
        // Save to a temporary location that can be accessed as an Image
        let tempDir = FileManager.default.temporaryDirectory
        let iconPath = tempDir.appendingPathComponent("\(name).png")
        
        do {
            try pngData.write(to: iconPath)
            log.debug("Saved app icon to: \(iconPath.path)")
            
            // Store the path so Image can load it
            UserDefaults.standard.set(iconPath.path, forKey: "appIcon_\(name)")
            
            return true
        } catch {
            log.error("Failed to save icon: \(error)")
            return false
        }
    }
}

// Extension for SwiftUI Image to load app icons
extension Image {
    init(appIcon name: String) {
        if let iconPath = UserDefaults.standard.string(forKey: "appIcon_\(name)"),
           FileManager.default.fileExists(atPath: iconPath) {
            // Load from saved file
            if let nsImage = NSImage(contentsOfFile: iconPath) {
                self.init(nsImage: nsImage)
            } else {
                // Fallback to system name
                self.init(systemName: "app")
            }
        } else {
            // Fallback to system name  
            self.init(systemName: "app")
        }
    }
}

// MARK: - Unified Icon Component
struct UnifiedIconView: View {
    let iconName: String
    let color: Color
    let size: CGFloat
    let isEnabled: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(iconName: String, color: Color, size: CGFloat, isEnabled: Bool = true) {
        self.iconName = iconName
        self.color = color
        self.size = size
        self.isEnabled = isEnabled
    }
    
    var body: some View {
        Group {
            // Check if it's a system symbol first
            if NSImage(systemSymbolName: iconName, accessibilityDescription: nil) != nil {
                // SF Symbols - use same logic as ServiceToggleView
                RoundedRectangle(cornerRadius: size * 0.225) // iOS-style corner radius
                    .fill(backgroundColorForIcon)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: iconName)
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(AppIconManager.shared.shouldUseMulticolorRendering(for: iconName) ? .multicolor : .monochrome)
                            .foregroundColor(foregroundColorForIcon)
                            .padding(iconName == "externaldrive.connected.to.line.below" ? 8 : size * 0.1) // More padding for smaller subprocess icons
                    )
            } else if iconName.hasPrefix("app_icon_") {
                // Dynamic app icons - bigger, no background, with visual effects
                Image(appIcon: iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .grayscale(isEnabled ? 0.0 : 1.0)
                    .opacity(isEnabled ? 1.0 : 0.4)
            } else {
                // Custom assets like Chrome logo
                RoundedRectangle(cornerRadius: size * 0.225)
                    .fill(backgroundColorForIcon)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(foregroundColorForIcon)
                            .padding(size * 0.1)
                    )
            }
        }
        .animation(.snappy, value: isEnabled)
    }
    
    private var backgroundColorForIcon: Color {
        if isEnabled {
            // Special case for Memory service - always use black background
            if iconName == AppIconManager.shared.getIconName(for: "Memory") {
                return Color.black.opacity(0.8)
            }
            return color.opacity(1.0)
        } else {
            return Color(NSColor.controlColor)
                .opacity(colorScheme == .dark ? 0.8 : 0.2)
        }
    }
    
    private var foregroundColorForIcon: Color? {
        if AppIconManager.shared.shouldUseMulticolorRendering(for: iconName) {
            return AppIconManager.shared.getForegroundColor(for: iconName, isEnabled: isEnabled, defaultColor: .primary.opacity(isEnabled ? 1.0 : 0.6))
        }
        
        if isEnabled {
            // Special case for Memory service - white text on black background
            if iconName == AppIconManager.shared.getIconName(for: "Memory") {
                return .white
            }
            // Special case for server icons on light backgrounds
            if AppIconManager.shared.shouldUseMulticolorRendering(for: iconName) {
                return .primary
            }
            return .white
        } else {
            return .primary.opacity(0.4)
        }
    }
}
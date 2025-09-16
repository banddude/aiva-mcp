import SwiftUI
import AppKit

struct ServiceToggleView: View {
    let config: ServiceConfig
    @State private var isServiceActivated = false
    @State private var renderTick: Int = 0
    @State private var isOnLocal: Bool = false
    
    // MARK: Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    
    // MARK: Private State
    private let buttonSize: CGFloat = 26
    private let imagePadding: CGFloat = 5
    

    var body: some View {
        HStack {
            Button(action: {
                print("🔄 Toggling service: \(config.name)")
                isOnLocal.toggle()
                config.binding.wrappedValue = isOnLocal
                print("📝 \(config.name) enabled: \(isOnLocal), activated: \(isServiceActivated)")
                if isOnLocal && !isServiceActivated {
                    print("🚀 Attempting to activate \(config.name) service")
                    Task {
                        do {
                            try await config.service.activate()
                            print("✅ \(config.name) service activated successfully")
                            await MainActor.run { isServiceActivated = true }
                        } catch {
                            print("❌ \(config.name) service activation failed: \(error)")
                            isOnLocal = false
                            config.binding.wrappedValue = false
                        }
                    }
                }
                // Force a visual refresh for bindings backed by UserDefaults
                renderTick &+= 1
                // Let the server controller refresh services/bindings immediately
                NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
            }) {
                Group {
                    // Check if it's a system symbol first
                    if NSImage(systemSymbolName: config.iconName, accessibilityDescription: nil) != nil {
                        // SF Symbols - slightly smaller than app icons
                        RoundedRectangle(cornerRadius: (buttonSize + 1) * 0.225) // iOS-style corner radius
                            .fill(buttonBackgroundColor)
                            .frame(width: buttonSize + 1, height: buttonSize + 1)
                            .overlay(
                                Image(systemName: config.iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .symbolRenderingMode(AppIconManager.shared.shouldUseMulticolorRendering(for: config.iconName) ? .multicolor : .monochrome)
                                    .foregroundColor(AppIconManager.shared.getForegroundColor(for: config.iconName, isEnabled: isEnabled, defaultColor: buttonForegroundColor))
                                    .padding(config.iconName == "externaldrive.connected.to.line.below" ? imagePadding : imagePadding - 2.5) // Normal subprocess, bigger for SSE
                            )
                    } else if config.iconName.hasPrefix("app_icon_") {
                        // Dynamic app icons - bigger than circle, no background
                        Image(appIcon: config.iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize + 6, height: buttonSize + 6) // 6 points bigger than circle
                            .clipShape(Circle()) // Clip to circle but no background
                            .grayscale(isOnLocal ? 0.0 : 1.0) // Greyscale when disabled
                            .opacity(isOnLocal ? 1.0 : 0.4) // Lower opacity when disabled
                    } else {
                        // Custom assets like Chrome logo - slightly smaller than app icons
                        RoundedRectangle(cornerRadius: (buttonSize + 1) * 0.225) // iOS-style corner radius
                            .fill(buttonBackgroundColor)
                            .frame(width: buttonSize + 1, height: buttonSize + 1)
                            .overlay(
                                Image(config.iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(buttonForegroundColor)
                                    .padding(1.5) // Minimal padding for custom assets, adjusted for smaller size
                            )
                    }
                }
                .animation(.snappy, value: config.binding.wrappedValue || isEnabled)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEnabled)
            .frame(width: buttonSize, height: buttonSize)
            
            Text(config.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isEnabled ? Color.primary : .primary.opacity(0.5))
        }
        .frame(height: buttonSize)
        .padding(.horizontal, 14)
        .task { @MainActor in
            isServiceActivated = await config.isActivated
            isOnLocal = config.binding.wrappedValue
        }
        .id(renderTick)
        .onChange(of: config.binding.wrappedValue) { _, newValue in
            // Sync external changes (e.g., from Settings view) to local state
            isOnLocal = newValue
        }
    }

    private var buttonBackgroundColor: Color {
        if isOnLocal {
            // Special case for Memory service - always use black background
            if config.name == "Memory" {
                return Color.black.opacity(isEnabled ? 0.8 : 0.4)
            }
            return config.color.opacity(isEnabled ? 1.0 : 0.4)
        } else {
            return Color(NSColor.controlColor)
                .opacity(isEnabled ? (colorScheme == .dark ? 0.8 : 0.2) : 0.1)
        }
    }

    private var buttonForegroundColor: Color {
        if isOnLocal {
            // Special case for external drive icons on white/yellow background - use dark icon
            if AppIconManager.shared.shouldUseMulticolorRendering(for: config.iconName) {
                return .primary.opacity(isEnabled ? 1.0 : 0.6)
            }
            return .white.opacity(isEnabled ? 1.0 : 0.6)
        } else {
            return .primary.opacity(isEnabled ? 0.7 : 0.4)
        }
    }
}

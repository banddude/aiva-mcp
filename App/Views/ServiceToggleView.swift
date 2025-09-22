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
                UnifiedIconView(
                    iconName: config.iconName,
                    color: config.color,
                    size: buttonSize,
                    isEnabled: iconIsActive,
                    displayMode: .compact
                )
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

    private var iconIsActive: Bool {
        isOnLocal && isEnabled
    }
}

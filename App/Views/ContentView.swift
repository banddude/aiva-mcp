import AppKit
import MenuBarExtraAccess
import SwiftUI

struct ContentView: View {
    @ObservedObject var serverController: ServerController
    @Binding var isEnabled: Bool
    @Binding var isMenuPresented: Bool
    @Environment(\.openSettings) private var openSettings

    private let aboutWindowController: AboutWindowController

    private var serviceConfigs: [ServiceConfig] {
        serverController.computedServiceConfigs
    }

    private var serviceBindings: [String: Binding<Bool>] {
        Dictionary(
            uniqueKeysWithValues: serviceConfigs.map {
                ($0.id, $0.binding)
            })
    }

    init(
        serverManager: ServerController,
        isEnabled: Binding<Bool>,
        isMenuPresented: Binding<Bool>
    ) {
        self.serverController = serverManager
        self._isEnabled = isEnabled
        self._isMenuPresented = isMenuPresented
        self.aboutWindowController = AboutWindowController()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Enable MCP Server")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.top, 2)
            .padding(.horizontal, 14)
            .onChange(of: isEnabled, initial: true) {
                Task {
                    await serverController.setEnabled(isEnabled)
                }
            }

            if isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text("Services")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .opacity(isEnabled ? 1.0 : 0.4)
                        .padding(.horizontal, 14)

                    ForEach(serviceConfigs) { config in
                        ServiceToggleView(config: config)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
                .padding(.horizontal, 2)
                .onChange(of: serviceConfigs.map { $0.binding.wrappedValue }, initial: true) {
                    Task {
                        await serverController.updateServiceBindings(serviceBindings)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.3), value: isEnabled)
            }


            VStack(alignment: .leading, spacing: 2) {
                Divider()

                MenuButton("Settings...", isMenuPresented: $isMenuPresented) {
                    let settingsController = SettingsWindowController.shared(serverController: serverController)
                    settingsController.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuButton("About AIVA", isMenuPresented: $isMenuPresented) {
                    aboutWindowController.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuButton("Quit", isMenuPresented: $isMenuPresented) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.bottom, 2)
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 6)
        .background(
            // Liquid Glass layered effect with high translucency
            ZStack {
                // Base glass layer - much more transparent
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)
                
                // Secondary glass layer for depth - very subtle
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                    .opacity(0.15)
                    .blur(radius: 0.8)
                
                // Specular highlight layer - glass-like edges
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.25), lineWidth: 0.5)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.12),
                                .clear,
                                .black.opacity(0.03)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
                
                // Dynamic reflection layer - very subtle
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.06),
                                .clear,
                                .white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 1.2)
                    
                // Additional glass reflection for liquid effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.04),
                                .clear
                            ]),
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 60
                        )
                    )
            }
        )
    }
    
    static func checkIfAIVAInCLI() -> Bool {
        let path = (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json").path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any]
        else { return false }
        return servers["aiva"] != nil
    }
    
    static func checkIfAIVAInGemini() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any]
        else { return false }
        return servers["aiva"] != nil
    }
    
    static func checkIfAIVAInCodex() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.contains("[mcp_servers.aiva]")
    }
    
    static func checkIfAIVAInClaudeDesktop() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any]
        else { return false }
        return servers["aiva"] != nil
    }
}

private struct MenuButton: View {
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let action: () -> Void
    @Binding private var isMenuPresented: Bool
    @State private var isHighlighted: Bool = false
    @State private var isPressed: Bool = false

    init<S>(
        _ title: S,
        isMenuPresented: Binding<Bool>,
        action: @escaping () -> Void
    ) where S: StringProtocol {
        self.title = String(title)
        self._isMenuPresented = isMenuPresented
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary.opacity(isEnabled ? 1.0 : 0.4))
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)

            Spacer()
        }
        .contentShape(Rectangle())
        .allowsHitTesting(isEnabled)
        .onTapGesture {
            guard isEnabled else { return }

            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = true
                }

                try? await Task.sleep(for: .milliseconds(100))

                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }

                action()
                isMenuPresented = false
            }
        }
        .frame(height: 18)
        .padding(.vertical, 4)
        .background(
            ZStack {
                // Base Liquid Glass button effect
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .opacity(isHighlighted || isPressed ? 0.3 : 0)
                
                // Pressed/highlighted glass layer
                if isPressed {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.3), lineWidth: 0.5)
                        )
                } else if isHighlighted {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor.opacity(0.4),
                                    Color.accentColor.opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .blur(radius: 0.5)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isHighlighted)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        )
        .onHover { state in
            guard isEnabled else { return }
            isHighlighted = state
        }
        .onChange(of: isEnabled) { _, newValue in
            if !newValue {
                isHighlighted = false
                isPressed = false
            }
        }
    }
}

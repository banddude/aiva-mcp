import AppKit
import MenuBarExtraAccess
import SwiftUI

struct ContentView: View {
    @ObservedObject var serverController: ServerController
    @Binding var isEnabled: Bool
    @Binding var isMenuPresented: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var isInClaudeCodeCLI: Bool = false
    @State private var isInGemini: Bool = false
    @State private var isInCodex: Bool = false
    @State private var isInClaudeDesktop: Bool = false
    
    // Brand colors for CLI toggles
    private let claudeColor = Color.orange
    private let geminiColor = Color(red: 0.26, green: 0.52, blue: 1.0) // Google Blue
    private let codexColor = Color(red: 0.16, green: 0.66, blue: 0.58) // OpenAI Teal
    private let claudeDesktopColor = Color.orange

    private let aboutWindowController: AboutWindowController
    private let settingsWindowController: SettingsWindowController

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
        self.settingsWindowController = SettingsWindowController(serverController: serverManager)
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

            VStack(alignment: .leading, spacing: 8) {
                Divider()
                
                Text("Agent Integrations")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .opacity(isEnabled ? 1.0 : 0.4)
                    .padding(.horizontal, 14)

                CLIToggleView(
                    name: "Claude Desktop",
                    logoImageName: "claude-logo",
                    brandColor: claudeDesktopColor,
                    isEnabled: $isEnabled,
                    isActive: $isInClaudeDesktop,
                    action: performClaudeDesktopToggleAction,
                    launchAction: launchClaudeDesktop
                )

                CLIToggleView(
                    name: "Claude Code CLI",
                    logoImageName: "claude-logo",
                    brandColor: claudeColor,
                    isEnabled: $isEnabled,
                    isActive: $isInClaudeCodeCLI,
                    action: performToggleAction,
                    launchAction: launchClaudeCodeCLI
                )

                CLIToggleView(
                    name: "Gemini CLI",
                    logoImageName: "gemini-logo",
                    brandColor: geminiColor,
                    isEnabled: $isEnabled,
                    isActive: $isInGemini,
                    action: performGeminiToggleAction,
                    launchAction: launchGeminiCLI
                )

                CLIToggleView(
                    name: "Codex CLI",
                    logoImageName: "codex-logo",
                    brandColor: codexColor,
                    isEnabled: $isEnabled,
                    isActive: $isInCodex,
                    action: performCodexToggleAction,
                    launchAction: launchCodexCLI
                )

                MenuButton("Copy server command to clipboard", isMenuPresented: $isMenuPresented) {
                    let command = Bundle.main.bundleURL
                        .appendingPathComponent("Contents/MacOS/aiva-server")
                        .path

                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 2) {
                Divider()

                MenuButton("Settings...", isMenuPresented: $isMenuPresented) {
                    settingsWindowController.showWindow(nil)
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
        .background(Material.thick)
        .task {
            // Check CLI states when view appears
            isInClaudeCodeCLI = Self.checkIfAIVAInCLI()
            isInGemini = Self.checkIfAIVAInGemini()
            isInCodex = Self.checkIfAIVAInCodex()
            isInClaudeDesktop = Self.checkIfAIVAInClaudeDesktop()
        }
    }
    
    static func checkIfAIVAInCLI() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "jq -e '.mcpServers.aiva' \"$HOME/.claude.json\" >/dev/null 2>&1"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func checkIfAIVAInGemini() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "jq -e '.mcpServers.aiva' \"$HOME/.gemini/settings.json\" >/dev/null 2>&1"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func checkIfAIVAInCodex() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "grep -q '\\[mcp_servers\\.aiva\\]' \"$HOME/.codex/config.toml\" 2>/dev/null"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func checkIfAIVAInClaudeDesktop() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "jq -e '.mcpServers.aiva' \"$HOME/Library/Application Support/Claude/claude_desktop_config.json\" >/dev/null 2>&1"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func performToggleAction(_ newValue: Bool) {
        let serverPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/aiva-server")
            .path
        
        Task {
            let command = """
            # Edit Claude config JSON directly
            CLAUDE_CONFIG="$HOME/.claude.json"
            BACKUP_CONFIG="$HOME/.claude.json.backup.$(date +%s)"
            
            # Backup the config
            cp "$CLAUDE_CONFIG" "$BACKUP_CONFIG"
            echo "Backed up config to: $BACKUP_CONFIG"
            
            if [ "\(newValue)" = "true" ]; then
                # Add aiva
                jq '.mcpServers.aiva = {
                    "type": "stdio",
                    "command": "\(serverPath)",
                    "args": [],
                    "env": {}
                }' "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG.tmp" && mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
                echo "Added AIVA to Claude Code CLI config"
            else
                # Remove aiva
                jq 'del(.mcpServers.aiva)' "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG.tmp" && mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
                echo "Removed AIVA from Claude Code CLI config"
            fi
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    print("Claude Code CLI operation successful: \(output)")
                } else {
                    print("Failed Claude Code CLI operation: \(output)")
                    // Revert the toggle if the operation failed
                    await MainActor.run {
                        isInClaudeCodeCLI = !newValue
                    }
                }
            } catch {
                print("Failed to run command: \(error)")
                // Revert the toggle if the operation failed
                await MainActor.run {
                    isInClaudeCodeCLI = !newValue
                }
            }
        }
    }
    
    private func performGeminiToggleAction(_ newValue: Bool) {
        let serverPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/aiva-server")
            .path
        
        Task {
            let command = """
            # Edit Gemini config JSON directly
            GEMINI_CONFIG="$HOME/.gemini/settings.json"
            BACKUP_CONFIG="$HOME/.gemini/settings.json.backup.$(date +%s)"
            
            # Backup the config
            cp "$GEMINI_CONFIG" "$BACKUP_CONFIG"
            echo "Backed up Gemini config to: $BACKUP_CONFIG"
            
            if [ "\(newValue)" = "true" ]; then
                # Add aiva
                jq '.mcpServers.aiva = {
                    "command": "\(serverPath)",
                    "args": [],
                    "trust": true
                }' "$GEMINI_CONFIG" > "$GEMINI_CONFIG.tmp" && mv "$GEMINI_CONFIG.tmp" "$GEMINI_CONFIG"
                echo "Added AIVA to Gemini CLI config"
            else
                # Remove aiva
                jq 'del(.mcpServers.aiva)' "$GEMINI_CONFIG" > "$GEMINI_CONFIG.tmp" && mv "$GEMINI_CONFIG.tmp" "$GEMINI_CONFIG"
                echo "Removed AIVA from Gemini CLI config"
            fi
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    print("Gemini CLI operation successful: \(output)")
                } else {
                    print("Failed Gemini CLI operation: \(output)")
                    // Revert the toggle if the operation failed
                    await MainActor.run {
                        isInGemini = !newValue
                    }
                }
            } catch {
                print("Failed to run Gemini command: \(error)")
                // Revert the toggle if the operation failed
                await MainActor.run {
                    isInGemini = !newValue
                }
            }
        }
    }
    
    private func performCodexToggleAction(_ newValue: Bool) {
        let serverPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/aiva-server")
            .path
        
        Task {
            let command = """
            # Edit Codex config TOML directly
            CODEX_CONFIG="$HOME/.codex/config.toml"
            BACKUP_CONFIG="$HOME/.codex/config.toml.backup.$(date +%s)"
            
            # Backup the config
            cp "$CODEX_CONFIG" "$BACKUP_CONFIG"
            echo "Backed up Codex config to: $BACKUP_CONFIG"
            
            if [ "\(newValue)" = "true" ]; then
                # Add aiva section to TOML
                echo "" >> "$CODEX_CONFIG"
                echo "[mcp_servers.aiva]" >> "$CODEX_CONFIG"
                echo "command = \\"\(serverPath)\\"" >> "$CODEX_CONFIG"
                echo "args = []" >> "$CODEX_CONFIG"
                echo "Added AIVA to Codex CLI config"
            else
                # Remove all aiva sections from TOML using awk
                awk '
                /^\\[mcp_servers\\.aiva\\]/ { skip=3; next }
                skip > 0 { skip--; next }
                { print }
                ' "$CODEX_CONFIG" > "$CODEX_CONFIG.tmp"
                mv "$CODEX_CONFIG.tmp" "$CODEX_CONFIG"
                echo "Removed AIVA from Codex CLI config"
            fi
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    print("Codex CLI operation successful: \(output)")
                } else {
                    print("Failed Codex CLI operation: \(output)")
                    // Revert the toggle if the operation failed
                    await MainActor.run {
                        isInCodex = !newValue
                    }
                }
            } catch {
                print("Failed to run Codex command: \(error)")
                // Revert the toggle if the operation failed
                await MainActor.run {
                    isInCodex = !newValue
                }
            }
        }
    }
    
    private func performClaudeDesktopToggleAction(_ newValue: Bool) {
        let serverPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/aiva-server")
            .path
        
        Task {
            let command = """
            # Edit Claude Desktop config JSON directly
            CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
            BACKUP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json.backup.$(date +%s)"
            
            # Create directory if it doesn't exist
            mkdir -p "$(dirname "$CLAUDE_CONFIG")"
            
            # Create empty config if it doesn't exist
            if [ ! -f "$CLAUDE_CONFIG" ]; then
                echo '{"mcpServers":{}}' > "$CLAUDE_CONFIG"
            fi
            
            # Backup the config
            cp "$CLAUDE_CONFIG" "$BACKUP_CONFIG"
            echo "Backed up Claude Desktop config to: $BACKUP_CONFIG"
            
            echo "DEBUG: newValue is \(newValue)"
            if [ "\(newValue)" = "true" ]; then
                # Add aiva
                jq --arg serverPath "\(serverPath)" '.mcpServers.aiva = {
                    "command": $serverPath,
                    "args": []
                }' "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG.tmp" && mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
                echo "Added AIVA to Claude Desktop config"
            else
                # Remove aiva
                jq 'del(.mcpServers.aiva)' "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG.tmp" && mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
                echo "Removed AIVA from Claude Desktop config"
            fi
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    print("Claude Desktop operation successful: \(output)")
                } else {
                    print("Failed Claude Desktop operation: \(output)")
                    // Revert the toggle if the operation failed
                    await MainActor.run {
                        isInClaudeDesktop = !newValue
                    }
                }
            } catch {
                print("Failed to run Claude Desktop command: \\(error)")
                // Revert the toggle if the operation failed
                await MainActor.run {
                    isInClaudeDesktop = !newValue
                }
            }
        }
    }
    
    private func showClaudeCodeCLINotInstalledAlert() {
        let alert = NSAlert()
        alert.messageText = "Claude Code CLI Not Found"
        alert.informativeText = "Claude Code CLI is not installed. Please install it first to use this feature.\n\nYou can install it from: https://github.com/anthropics/claude-code"
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    // MARK: - Launch Actions
    
    private func launchClaudeDesktop() {
        NSWorkspace.shared.launchApplication("Claude")
    }
    
    private func launchClaudeCodeCLI() {
        openTerminalWithCommand("claude")
    }
    
    private func launchGeminiCLI() {
        openTerminalWithCommand("gemini")
    }
    
    private func launchCodexCLI() {
        openTerminalWithCommand("codex")
    }
    
    private func openTerminalWithCommand(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\"",
            "-e", "activate", 
            "-e", "do script \"\(command)\"",
            "-e", "end tell"
        ]
        
        do {
            try process.run()
        } catch {
            print("Failed to open Terminal: \(error)")
        }
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
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isPressed
                        ? Color.accentColor
                        : isHighlighted ? Color.accentColor.opacity(0.7) : Color.clear)
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

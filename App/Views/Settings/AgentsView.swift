import AppKit
import SwiftUI

struct AgentsView: View {
    @ObservedObject var serverController: ServerController
    @Binding var isEnabled: Bool
    @State private var isInClaudeCodeCLI: Bool = false
    @State private var isInGemini: Bool = false
    @State private var isInCodex: Bool = false
    @State private var isInClaudeDesktop: Bool = false
    
    // Alert states for confirmation dialogs
    @State private var showingClaudeDesktopAlert = false
    @State private var showingClaudeCodeAlert = false
    @State private var showingGeminiAlert = false
    @State private var showingCodexAlert = false
    @State private var pendingToggleValue: Bool = false
    @State private var pendingAgent: String = ""
    @State private var selectedClients = Set<String>()
    
    // Brand colors for CLI toggles
    private let claudeColor = Color.orange
    private let geminiColor = Color(red: 0.26, green: 0.52, blue: 1.0) // Google Blue
    private let codexColor = Color(red: 0.16, green: 0.66, blue: 0.58) // OpenAI Teal
    private let claudeDesktopColor = Color.orange
    
    // Client mapping
    private var trustedClients: [String] {
        serverController.getTrustedClients()
    }
    
    private var mappedClients: [String: String] {
        [
            "claude-ai": "Claude Desktop",
            "claude-code": "Claude Code CLI", 
            "codex-mcp-client": "Codex CLI",
            "gemini-cli-mcp-client-aiva": "Gemini CLI"
        ]
    }
    
    private var unmappedClients: [String] {
        trustedClients.filter { client in
            !mappedClients.keys.contains(client)
        }
    }
    
    private func getConnectedClient(for agentName: String) -> String? {
        let clientKey = mappedClients.first { $0.value == agentName }?.key
        return trustedClients.contains(clientKey ?? "") ? clientKey : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent Integrations")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Toggle switches to enable or disable agent connections")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Copy Server Command") {
                    let command = Bundle.main.bundleURL
                        .appendingPathComponent("Contents/MacOS/aiva-server")
                        .path

                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 6) {
                CLIToggleView(
                    name: "Claude Desktop",
                    logoImageName: "claude-logo",
                    brandColor: claudeDesktopColor,
                    isEnabled: $isEnabled,
                    isActive: $isInClaudeDesktop,
                    action: claudeDesktopToggleWithConfirmation,
                    launchAction: launchClaudeDesktop,
                    connectedClientId: getConnectedClient(for: "Claude Desktop"),
                    onUnlinkClient: nil,
                    installAction: nil
                )

                CLIToggleView(
                    name: "Claude Code CLI",
                    logoImageName: "claude-logo",
                    brandColor: claudeColor,
                    isEnabled: $isEnabled,
                    isActive: $isInClaudeCodeCLI,
                    action: claudeCodeToggleWithConfirmation,
                    launchAction: launchClaudeCodeCLI,
                    connectedClientId: getConnectedClient(for: "Claude Code CLI"),
                    onUnlinkClient: nil,
                    installAction: installClaudeCode
                )

                CLIToggleView(
                    name: "Gemini CLI",
                    logoImageName: "gemini-logo",
                    brandColor: geminiColor,
                    isEnabled: $isEnabled,
                    isActive: $isInGemini,
                    action: geminiToggleWithConfirmation,
                    launchAction: launchGeminiCLI,
                    connectedClientId: getConnectedClient(for: "Gemini CLI"),
                    onUnlinkClient: nil,
                    installAction: installGemini
                )

                CLIToggleView(
                    name: "Codex CLI",
                    logoImageName: "codex-logo",
                    brandColor: codexColor,
                    isEnabled: $isEnabled,
                    isActive: $isInCodex,
                    action: codexToggleWithConfirmation,
                    launchAction: launchCodexCLI,
                    connectedClientId: getConnectedClient(for: "Codex CLI"),
                    onUnlinkClient: nil,
                    installAction: installCodex
                )
            }
            
            // Show unmapped clients if any
            if !unmappedClients.isEmpty {
                Divider()
                    .padding(.vertical, 12)
                
                Text("Other Connected Clients")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.bottom, 8)
                
                Text("Clients that don't match known agents")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unmappedClients, id: \.self) { client in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            
                            Text(client)
                                .font(.body)
                                .font(.system(.body, design: .monospaced))
                            
                            Button(role: .destructive) {
                                serverController.removeTrustedClient(client)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            
                            Spacer()
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            // Check CLI states when view appears
            isInClaudeCodeCLI = ContentView.checkIfAIVAInCLI()
            isInGemini = ContentView.checkIfAIVAInGemini()
            isInCodex = ContentView.checkIfAIVAInCodex()
            isInClaudeDesktop = ContentView.checkIfAIVAInClaudeDesktop()
        }
        .alert("Claude Desktop Integration", isPresented: $showingClaudeDesktopAlert) {
            Button("Cancel", role: .cancel) { }
            Button(pendingToggleValue ? "Connect" : "Disconnect", role: pendingToggleValue ? .none : .destructive) {
                isInClaudeDesktop = pendingToggleValue
                performClaudeDesktopToggleAction(pendingToggleValue)
            }
        } message: {
            Text(pendingToggleValue ? 
                "This will add AIVA to your Claude Desktop configuration, allowing Claude to access AIVA's tools." :
                "This will remove AIVA from Claude Desktop and unlink any connected clients.")
        }
        .alert("Claude Code CLI Integration", isPresented: $showingClaudeCodeAlert) {
            Button("Cancel", role: .cancel) { }
            Button(pendingToggleValue ? "Connect" : "Disconnect", role: pendingToggleValue ? .none : .destructive) {
                isInClaudeCodeCLI = pendingToggleValue
                performToggleAction(pendingToggleValue)
            }
        } message: {
            Text(pendingToggleValue ? 
                "This will add AIVA to your Claude Code CLI configuration, enabling AIVA's tools in Claude Code." :
                "This will remove AIVA from Claude Code CLI and unlink any connected clients.")
        }
        .alert("Gemini CLI Integration", isPresented: $showingGeminiAlert) {
            Button("Cancel", role: .cancel) { }
            Button(pendingToggleValue ? "Connect" : "Disconnect", role: pendingToggleValue ? .none : .destructive) {
                isInGemini = pendingToggleValue
                performGeminiToggleAction(pendingToggleValue)
            }
        } message: {
            Text(pendingToggleValue ? 
                "This will add AIVA to your Gemini CLI configuration, enabling AIVA's tools in Gemini." :
                "This will remove AIVA from Gemini CLI and unlink any connected clients.")
        }
        .alert("Codex CLI Integration", isPresented: $showingCodexAlert) {
            Button("Cancel", role: .cancel) { }
            Button(pendingToggleValue ? "Connect" : "Disconnect", role: pendingToggleValue ? .none : .destructive) {
                isInCodex = pendingToggleValue
                performCodexToggleAction(pendingToggleValue)
            }
        } message: {
            Text(pendingToggleValue ? 
                "This will add AIVA to your Codex CLI configuration, enabling AIVA's tools in Codex." :
                "This will remove AIVA from Codex CLI and unlink any connected clients.")
        }
    }
    
    // MARK: - Confirmation Wrapper Functions
    
    private func claudeDesktopToggleWithConfirmation(_ newValue: Bool) {
        pendingToggleValue = newValue
        showingClaudeDesktopAlert = true
    }
    
    private func claudeCodeToggleWithConfirmation(_ newValue: Bool) {
        pendingToggleValue = newValue
        showingClaudeCodeAlert = true
    }
    
    private func geminiToggleWithConfirmation(_ newValue: Bool) {
        pendingToggleValue = newValue
        showingGeminiAlert = true
    }
    
    private func codexToggleWithConfirmation(_ newValue: Bool) {
        pendingToggleValue = newValue
        showingCodexAlert = true
    }
    
    // MARK: - Actual Toggle Functions
    
    private func performToggleAction(_ newValue: Bool) {
        let serverPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/aiva-server")
            .path
        Task {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
            do {
                var root: [String: Any] = [:]
                if let data = try? Data(contentsOf: url),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    root = obj
                }
                var servers = root["mcpServers"] as? [String: Any] ?? [:]
                if newValue {
                    servers["aiva"] = [
                        "type": "stdio",
                        "command": serverPath,
                        "args": [],
                        "env": [:]
                    ]
                } else {
                    servers.removeValue(forKey: "aiva")
                }
                root["mcpServers"] = servers
                let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            } catch {
                print("Failed to update Claude Code CLI config: \(error)")
                await MainActor.run { isInClaudeCodeCLI = !newValue }
            }
            
            // If turning off successfully, also unlink the connected client
            if !newValue, let clientId = getConnectedClient(for: "Claude Code CLI") {
                await MainActor.run {
                    serverController.removeTrustedClient(clientId)
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
            
            // Native write (sandbox-safe): update ~/.gemini/settings.json
            do {
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".gemini/settings.json")
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var root: [String: Any] = [:]
                if let data = try? Data(contentsOf: url),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    root = obj
                }
                var servers = root["mcpServers"] as? [String: Any] ?? [:]
                if newValue {
                    servers["aiva"] = [
                        "command": serverPath,
                        "args": [],
                        "trust": true
                    ]
                } else {
                    servers.removeValue(forKey: "aiva")
                }
                root["mcpServers"] = servers
                let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            } catch {
                print("Gemini JSON write failed: \(error)")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/echo")
            process.arguments = [command]
            do { try process.run(); process.waitUntilExit() } catch {}
            
            // If turning off successfully, also unlink the connected client
            if !newValue, let clientId = getConnectedClient(for: "Gemini CLI") {
                await MainActor.run {
                    serverController.removeTrustedClient(clientId)
                }
            }
        }
    }
    
    private func performCodexToggleAction(_ newValue: Bool) {
        let serverPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/aiva-server")
            .path
        
        Task {
            // Only use native write (idempotent) to avoid duplicate TOML sections
            // Still make a backup via shell for user safety
            let command = """
            CODEX_CONFIG="$HOME/.codex/config.toml"
            BACKUP_CONFIG="$HOME/.codex/config.toml.backup.$(date +%s)"
            if [ -f "$CODEX_CONFIG" ]; then
              cp "$CODEX_CONFIG" "$BACKUP_CONFIG" && echo "Backed up Codex config to: $BACKUP_CONFIG"
            fi
            """

            // Native write (sandbox-safe): update ~/.codex/config.toml idempotently
            do {
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex/config.toml")
                var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                // Always remove any existing [mcp_servers.aiva] block first
                do {
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                    var filtered: [Substring] = []
                    var skipping = false
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed == "[mcp_servers.aiva]" { skipping = true; continue }
                        if skipping, trimmed.hasPrefix("[") { skipping = false }
                        if !skipping { filtered.append(line) }
                    }
                    text = filtered.joined(separator: "\n")
                }

                if newValue {
                    // Append a single canonical block to avoid duplicates
                    let block = "\n[mcp_servers.aiva]\ncommand = \"\(serverPath)\"\nargs = []\n"
                    text.append(block)
                }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Codex TOML write failed: \(error)")
            }

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
                    print("Codex CLI backup successful: \(output)")
                    // If turning off, also unlink the connected client
                    if !newValue, let clientId = getConnectedClient(for: "Codex CLI") {
                        await MainActor.run {
                            serverController.removeTrustedClient(clientId)
                        }
                    }
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
            
            // Native write (sandbox-safe): update Claude Desktop config JSON
            do {
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var root: [String: Any] = [:]
                if let data = try? Data(contentsOf: url),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    root = obj
                }
                var servers = root["mcpServers"] as? [String: Any] ?? [:]
                if newValue {
                    servers["aiva"] = [
                        "command": serverPath,
                        "args": []
                    ]
                } else {
                    servers.removeValue(forKey: "aiva")
                }
                root["mcpServers"] = servers
                let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            } catch {
                print("Claude Desktop JSON write failed: \(error)")
            }

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
                    // If turning off, also unlink the connected client
                    if !newValue, let clientId = getConnectedClient(for: "Claude Desktop") {
                        await MainActor.run {
                            serverController.removeTrustedClient(clientId)
                        }
                    }
                } else {
                    print("Failed Claude Desktop operation: \(output)")
                    // Revert the toggle if the operation failed
                    await MainActor.run {
                        isInClaudeDesktop = !newValue
                    }
                }
            } catch {
                print("Failed to run Claude Desktop command: \(error)")
                // Revert the toggle if the operation failed
                await MainActor.run {
                    isInClaudeDesktop = !newValue
                }
            }
        }
    }
    
    // MARK: - Launch Actions
    
    private func launchClaudeDesktop() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Claude.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
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

    // MARK: - Install Actions

    private func installClaudeCode() {
        let command = "npm install -g @anthropic-ai/claude-code"
        openTerminalWithCommand(command)
    }

    private func installGemini() {
        let command = "npm install -g @google/gemini-cli"
        openTerminalWithCommand(command)
    }

    private func installCodex() {
        let command = "npm install -g @openai/codex"
        openTerminalWithCommand(command)
    }
}
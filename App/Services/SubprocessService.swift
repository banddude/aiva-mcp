import Foundation
import JSONSchema
import OSLog
import MCP

#if canImport(Darwin)
    import Darwin
#endif

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

private let log = Logger.service("subprocess")

@MainActor
final class SubprocessService: Service, Sendable {
    private let server: ServerEntry
    private var manager: SubprocessMCPManager?
    private var cachedTools: [Tool] = []
    
    init?(server: ServerEntry) {
        // Only handle subprocess servers
        guard server.type == .subprocess else { return nil }
        guard let command = server.command, !command.isEmpty else { return nil }
        self.server = server
        
        print("🔧 [Subprocess] Created SubprocessService for: \(server.name)")
    }
    
    var isActivated: Bool {
        get async {
            return manager != nil
        }
    }
    
    func activate() async throws {
        print("🚀 [Subprocess] Activating server: \(server.name)")
        
        guard let command = server.command else {
            throw NSError(domain: "SubprocessService", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "No command specified"])
        }
        
        let manager = SubprocessMCPManager(
            name: server.name,
            command: command,
            arguments: server.arguments ?? [],
            environment: server.environment ?? [:],
            workingDirectory: server.workingDirectory
        )
        
        self.manager = manager
        
        do {
            try await manager.start()
            // Fetch tools from the subprocess
            self.cachedTools = await manager.getAvailableTools()
            print("🎯 [Subprocess] Started \(server.name) with \(cachedTools.count) tools")
        } catch {
            self.manager = nil
            print("❌ [Subprocess] Failed to start \(server.name): \(error)")
            throw error
        }
    }
    
    func deactivate() async {
        if let manager = manager {
            await manager.stop()
            self.manager = nil
            self.cachedTools = []
            print("🛑 [Subprocess] Stopped server: \(server.name)")
        }
    }
    
    nonisolated var tools: [Tool] {
        return MainActor.assumeIsolated {
            print("🔍 [Subprocess] tools getter called for \(server.name)")
            print("🔍 [Subprocess] cachedTools count: \(cachedTools.count)")
            
            // Return cached tools, filtered by user preferences
            var enabledTools: [Tool] = []
            for tool in cachedTools {
                // Use the ServiceConfig idOverride pattern for consistency
                let serviceId = "SubprocessService_\(server.id.uuidString)"
                let key = "toolEnabled.\(serviceId).\(tool.name)"
                if UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) {
                    enabledTools.append(tool)
                    print("✅ [Subprocess] Tool enabled: \(tool.name)")
                } else {
                    print("❌ [Subprocess] Tool disabled: \(tool.name)")
                }
            }
            print("🔍 [Subprocess] Returning \(enabledTools.count) enabled tools")
            return enabledTools
        }
    }

    nonisolated var lastStatus: String? {
        return MainActor.assumeIsolated {
            return (manager?.getLastError())
        }
    }
    
    deinit {
        Task { [manager] in
            await manager?.stop()
        }
    }
}

actor SubprocessMCPManager {
    private let name: String
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private let workingDirectory: String?
    
    private var process: Process?
    private var client: MCP.Client?
    private var transport: StdioTransport?
    private var availableTools: [Tool] = []
    private var isRunning = false
    nonisolated(unsafe) private var lastError: String?
    private var tempScriptPath: String?
    
    init(name: String, command: String, arguments: [String], environment: [String: String], workingDirectory: String?) {
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
    
    func start() async throws {
        guard !self.isRunning else { return }
        
        // Create process
        let process = Process()

        // Helper: resolve absolute path to a command using login shell and common locations
        func expand(_ path: String) -> String {
            NSString(string: path).expandingTildeInPath
        }
        func isExecutable(_ path: String) -> Bool {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return exists && !isDir.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }
        func resolveAbsoluteCommand(_ cmd: String) -> String? {
            // Try login shell PATH
            do {
                let output = Pipe()
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                let escaped = cmd.replacingOccurrences(of: "'", with: "'\\''")
                p.arguments = ["-l", "-c", "command -v '" + escaped + "' || true"]
                p.standardOutput = output
                p.standardError = Pipe()
                try p.run()
                p.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("/"), isExecutable(s) {
                    return s
                }
            } catch {
                // ignore
            }

            // Try common install locations
            var candidates: [String] = [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/opt/local/bin",
                "~/.volta/bin",
                "~/.bun/bin",
                "~/.local/share/pnpm",
                "~/.local/bin",
                "~/.deno/bin",
                "~/.cargo/bin",
                "~/.asdf/shims",
                "~/.nodenv/shims",
                "~/.fnm",
                "/opt/homebrew/opt/node/bin",
                "/usr/local/opt/node/bin",
            ]
            // Homebrew node@X formulas
            let hbOpt = "/opt/homebrew/opt"
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: hbOpt) {
                for entry in contents where entry.hasPrefix("node") {
                    candidates.append("\(hbOpt)/\(entry)/bin")
                }
            }
            let ulOpt = "/usr/local/opt"
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: ulOpt) {
                for entry in contents where entry.hasPrefix("node") {
                    candidates.append("\(ulOpt)/\(entry)/bin")
                }
            }
            // nvm versions
            let nvmBase = expand("~/.nvm/versions/node")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
                let sorted = contents.sorted(by: >)
                for ver in sorted { candidates.append(nvmBase + "/" + ver + "/bin") }
            }
            for dir in candidates {
                let full = expand(dir) + "/" + cmd
                if isExecutable(full) { return full }
            }
            return nil
        }

        // Honor user's command/args, but use a managed Node runtime for node/npm/npx
        var effectiveCommand: String = self.command
        var effectiveArgs: [String] = self.arguments
        var processEnv = ProcessInfo.processInfo.environment
        let nodeCommands: Set<String> = ["node", "npm", "npx"]

        // Always prefer the app-managed Node by prepending it to PATH so any
        // shebang like `#!/usr/bin/env node` resolves to our runtime.
        if let binURL = await NodeRuntimeManager.shared.preferEmbeddedOrInstalled() {
            let nodeBin = binURL.path
            let existing = processEnv["PATH"] ?? "/usr/bin:/bin"
            processEnv["PATH"] = nodeBin + ":" + existing

            if nodeCommands.contains(self.command) {
                switch self.command {
                case "node":
                    effectiveCommand = nodeBin + "/node"
                case "npm":
                    effectiveCommand = nodeBin + "/npm"
                case "npx":
                    // Prefer npm exec -y on modern Node; fall back to npx if available
                    let npmPath = nodeBin + "/npm"
                    let npxPath = nodeBin + "/npx"
                    if FileManager.default.isExecutableFile(atPath: npmPath) {
                        effectiveCommand = npmPath
                        effectiveArgs = ["exec", "-y"] + effectiveArgs
                    } else if FileManager.default.isExecutableFile(atPath: npxPath) {
                        effectiveCommand = npxPath
                    }
                    if processEnv["npm_config_yes"] == nil { processEnv["npm_config_yes"] = "1" }
                    processEnv["npm_config_update_notifier"] = "false"
                    // Disable quarantine for npm packages in sandboxed apps
                    processEnv["npm_config_ignore_scripts"] = "false"
                    processEnv["ELECTRON_RUN_AS_NODE"] = "1"
                default:
                    break
                }
            }
        } else if nodeCommands.contains(self.command) {
            // No bundled Node found; do NOT fall back to system. Fail fast.
            let msg = "Bundled Node runtime required but not found in app Resources"
            print("❌ [Subprocess] \(msg)")
            log.error("[Subprocess] \(msg)")
            self.lastError = msg
            throw NSError(domain: "SubprocessService", code: 1001, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        // Merge with any user-provided environment
        processEnv = processEnv.merging(self.environment) { _, new in new }

        // Use absolute path if resolved, else env
        if effectiveCommand.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: effectiveCommand)
            process.arguments = effectiveArgs
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [effectiveCommand] + effectiveArgs
        }
        process.environment = processEnv
        
        // Set working directory - default to user's home directory if not specified
        if let workingDirectory = self.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        } else {
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        
        // Set up pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        // Ignore SIGPIPE to prevent crashes
        signal(SIGPIPE, SIG_IGN)
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Add error handling for stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let errorString = String(data: data, encoding: .utf8) {
                print("❌ [Subprocess] stderr from \(self.name): \(errorString)")
                // Log to system log as well for debugging built apps
                log.error("[Subprocess] stderr from \(self.name): \(errorString)")
                
                // Also write to a debug file for troubleshooting
                let debugPath = "/tmp/aiva_subprocess_debug.log"
                let timestamp = Date().description
                let debugMessage = "[\(timestamp)] stderr from \(self.name): \(errorString)\n"
                if let fileHandle = FileHandle(forWritingAtPath: debugPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(debugMessage.data(using: .utf8) ?? Data())
                    fileHandle.closeFile()
                } else {
                    try? debugMessage.write(toFile: debugPath, atomically: true, encoding: .utf8)
                }
            }
        }
        
        // Monitor process termination
        process.terminationHandler = { proc in
            print("⚠️ [Subprocess] Process \(self.name) terminated with status: \(proc.terminationStatus)")
        }
        
        // Create MCP client and transport
        let client = MCP.Client(name: "AIVA-\(self.name)", version: "1.0.0")
        
        // Convert FileHandle to FileDescriptor for StdioTransport
        let inputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        
        let transport = StdioTransport(
            input: outputFD,  // Reading from subprocess's stdout
            output: inputFD   // Writing to subprocess's stdin
        )
        
        self.process = process
        self.client = client
        self.transport = transport
        
        // Start process
        do {
            // Special handling for npm exec to bypass quarantine
            if effectiveCommand.contains("/npm") && effectiveArgs.contains("exec") {
                print("🔧 [Subprocess] Detected npm exec command, preparing quarantine bypass...")
                print("🔧 [Subprocess] Command: \(effectiveCommand)")
                print("🔧 [Subprocess] Arguments: \(effectiveArgs)")
                
                // Create a temporary script that will handle the execution
                let scriptContent = """
#!/bin/bash
# Auto-generated script to bypass quarantine for npm exec
export PATH="\(processEnv["PATH"] ?? "/usr/bin:/bin")"
cd "\(process.currentDirectoryURL?.path ?? FileManager.default.homeDirectoryForCurrentUser.path)"

# Clear quarantine from npm cache
# Check both regular npm cache (with entitlements) and container cache
for NPX_DIR in "$HOME/.npm/_npx" "$HOME/Library/Containers/com.mikeshaffer.AIVA/Data/.npm/_npx"; do
    if [ -d "$NPX_DIR" ]; then
        echo "Clearing quarantine from: $NPX_DIR"
        find "$NPX_DIR" -name "*.js" -print0 2>/dev/null | xargs -0 -P 8 xattr -d com.apple.quarantine 2>/dev/null || true
    fi
done

# Execute the npm command
exec "\(effectiveCommand)" \(effectiveArgs.map { "\"\($0)\"" }.joined(separator: " "))
"""
                
                let scriptPath = "/tmp/aiva_npm_exec_\(UUID().uuidString).sh"
                try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
                
                // Store the script path for cleanup
                self.tempScriptPath = scriptPath
                
                // Update process to run our script instead
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptPath]
                
                print("🔧 [Subprocess] Created quarantine bypass script at: \(scriptPath)")
            }
            
            try process.run()
            print("✅ [Subprocess] Started process for \(self.name): \(effectiveCommand) \(effectiveArgs.joined(separator: " "))")
            print("📍 [Subprocess] Working directory: \(process.currentDirectoryURL?.path ?? "(default)")")
            print("🔧 [Subprocess] PATH: \(processEnv["PATH"] ?? "(not set)")")
            
            // Write startup info to debug file
            let debugPath = "/tmp/aiva_subprocess_startup.log"
            let startupInfo = """
            === SUBPROCESS STARTUP ===
            Time: \(Date())
            Name: \(self.name)
            Command: \(effectiveCommand)
            Args: \(effectiveArgs.joined(separator: " "))
            Working Dir: \(process.currentDirectoryURL?.path ?? "default")
            Script Created: \(self.tempScriptPath ?? "none")
            ===
            
            """
            try? startupInfo.write(toFile: debugPath, atomically: false, encoding: .utf8)
        } catch {
            let msg = "Failed to start process for \(self.name): \(error.localizedDescription)"
            print("❌ [Subprocess] \(msg)")
            self.lastError = msg
            throw error
        }
        
        // Give the process a moment to start
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second (increased from 0.5)
        
        // Check if process is still running
        if !process.isRunning {
            let exitCode = process.terminationStatus
            let errorMsg = "Process exited immediately (code \(exitCode)). Check if \(self.command) is installed and accessible."
            print("❌ [Subprocess] \(errorMsg)")
            log.error("[Subprocess] \(errorMsg)")
            self.lastError = errorMsg
            throw NSError(domain: "SubprocessService", code: Int(exitCode),
                         userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        // Connect MCP client with timeout
        do {
            // Create a timeout task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds timeout (increased from 10)
                throw NSError(domain: "SubprocessService", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "MCP connection timeout after 30 seconds. The subprocess may not be an MCP server."])
            }
            
            // Try to connect
            try await withTaskCancellationHandler {
                try await client.connect(transport: transport)
                timeoutTask.cancel()
                print("✅ [Subprocess] Connected to MCP server for \(self.name)")
            } onCancel: {
                timeoutTask.cancel()
            }
        } catch {
            let msg = "Failed to connect to MCP server for \(self.name): \(error.localizedDescription)"
            print("❌ [Subprocess] \(msg)")
            self.lastError = msg
            if process.isRunning {
                process.terminate()
            }
            throw error
        }
        
        // Fetch available tools
        let (tools, _) = try await client.listTools()
        print("🔧 [Subprocess] Retrieved \(tools.count) tools from subprocess")
        for tool in tools {
            print("  📌 Tool: \(tool.name) - \(tool.description)")
        }
        
        self.availableTools = tools.map { mcpTool in
            Tool(
                name: mcpTool.name,
                description: mcpTool.description,
                inputSchema: mcpTool.inputSchema ?? .object(properties: [:], additionalProperties: true),
                annotations: mcpTool.annotations
            ) { [weak self] arguments in
                guard let self = self else {
                    throw NSError(domain: "SubprocessManager", code: 1, 
                                 userInfo: [NSLocalizedDescriptionKey: "Manager unavailable"])
                }
                guard let client = await self.client else {
                    throw NSError(domain: "SubprocessManager", code: 1, 
                                 userInfo: [NSLocalizedDescriptionKey: "Client unavailable"])
                }
                
                let (content, isError) = try await client.callTool(name: mcpTool.name, arguments: arguments)
                
                if isError ?? false {
                    let errorText = content.compactMap { item in
                        if case .text(let text) = item { return text }
                        return nil
                    }.joined(separator: "\n")
                    throw NSError(domain: "SubprocessTool", code: 1, 
                                 userInfo: [NSLocalizedDescriptionKey: errorText])
                }
                
                // Convert MCP content to Value
                let results = content.map { item -> [String: Value] in
                    switch item {
                    case .text(let text):
                        return ["type": Value.string("text"), "content": Value.string(text)]
                    case .image(let data, let mimeType, let metadata):
                        return [
                            "type": Value.string("image"),
                            "data": Value.string(data),
                            "mimeType": Value.string(mimeType),
                            "metadata": Value.object(metadata?.mapValues { Value.string("\($0)") } ?? [:])
                        ]
                    case .audio(let data, let mimeType):
                        return [
                            "type": Value.string("audio"),
                            "data": Value.string(data),
                            "mimeType": Value.string(mimeType)
                        ]
                    case .resource(let uri, let mimeType, let text):
                        return [
                            "type": Value.string("resource"),
                            "uri": Value.string(uri),
                            "mimeType": Value.string(mimeType),
                            "text": Value.string(text ?? "")
                        ]
                    }
                }
                
                return ["results": Value.array(results.map(Value.object))]
            }
        }
        
        self.isRunning = true
        log.info("Subprocess MCP server \(self.name) started with \(self.availableTools.count) tools")
    }
    
    func stop() async {
        self.isRunning = false
        
        if let process = self.process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        
        // Clean up temporary script if it exists
        if let scriptPath = self.tempScriptPath {
            try? FileManager.default.removeItem(atPath: scriptPath)
            print("🧹 [Subprocess] Cleaned up temporary script: \(scriptPath)")
            self.tempScriptPath = nil
        }
        
        self.client = nil
        self.transport = nil
        self.process = nil
        self.availableTools = []
        
        log.info("Subprocess MCP server \(self.name) stopped")
    }
    
    func getAvailableTools() -> [Tool] {
        return self.availableTools
    }

    nonisolated func getLastError() -> String? { self.lastError }
}

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
        
        // Check if command is npx or npm and use full path
        let effectiveCommand: String
        if self.command == "npx" || self.command == "npm" {
            // Common paths for npm/npx on macOS (prioritize homebrew on Apple Silicon)
            let possiblePaths = [
                "/opt/homebrew/bin/npx",
                "/opt/homebrew/bin/npm",
                "/usr/local/bin/npx",
                "/usr/local/bin/npm",
                "~/.nvm/versions/node/v20.11.0/bin/npx",
                "~/.nvm/versions/node/v20.11.0/bin/npm"
            ]
            
            if self.command == "npx" {
                if let npxPath = possiblePaths.filter({ $0.contains("npx") }).first(where: { FileManager.default.fileExists(atPath: NSString(string: $0).expandingTildeInPath) }) {
                    effectiveCommand = NSString(string: npxPath).expandingTildeInPath
                } else {
                    effectiveCommand = self.command
                }
            } else {
                if let npmPath = possiblePaths.filter({ $0.contains("npm") }).first(where: { FileManager.default.fileExists(atPath: NSString(string: $0).expandingTildeInPath) }) {
                    effectiveCommand = NSString(string: npmPath).expandingTildeInPath
                } else {
                    effectiveCommand = self.command
                }
            }
        } else {
            effectiveCommand = self.command
        }
        
        // Setup environment with proper PATH
        var processEnv = ProcessInfo.processInfo.environment
        
        // Add common Node.js paths to PATH
        let additionalPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "~/.nvm/versions/node/v20.11.0/bin"
        ]
        
        if var existingPath = processEnv["PATH"] {
            let expandedPaths = additionalPaths.map { NSString(string: $0).expandingTildeInPath }
            existingPath = expandedPaths.joined(separator: ":") + ":" + existingPath
            processEnv["PATH"] = existingPath
        } else {
            let expandedPaths = additionalPaths.map { NSString(string: $0).expandingTildeInPath }
            processEnv["PATH"] = expandedPaths.joined(separator: ":")
        }
        
        // Merge with any user-provided environment
        processEnv = processEnv.merging(self.environment) { _, new in new }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [effectiveCommand] + self.arguments
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
            try process.run()
            print("✅ [Subprocess] Started process for \(self.name): \(effectiveCommand) \(self.arguments.joined(separator: " "))")
            print("📍 [Subprocess] Working directory: \(process.currentDirectoryURL?.path ?? "(default)")")
            print("🔧 [Subprocess] PATH: \(processEnv["PATH"] ?? "(not set)")")
        } catch {
            print("❌ [Subprocess] Failed to start process for \(self.name): \(error)")
            throw error
        }
        
        // Give the process a moment to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Check if process is still running
        if !process.isRunning {
            let exitCode = process.terminationStatus
            throw NSError(domain: "SubprocessService", code: Int(exitCode),
                         userInfo: [NSLocalizedDescriptionKey: "Process exited immediately with code \(exitCode)"])
        }
        
        // Connect MCP client with timeout
        do {
            // Create a timeout task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds timeout
                throw NSError(domain: "SubprocessService", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Connection timeout after 10 seconds"])
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
            print("❌ [Subprocess] Failed to connect to MCP server for \(self.name): \(error)")
            if process.isRunning {
                process.terminate()
            }
            throw error
        }
        
        // Fetch available tools
        let (tools, _) = try await client.listTools()
        print("🔧 [Subprocess] Retrieved \(tools.count) tools from subprocess")
        for tool in tools {
            print("  📌 Tool: \(tool.name) - \(tool.description ?? "no description")")
        }
        
        self.availableTools = tools.map { mcpTool in
            Tool(
                name: mcpTool.name,
                description: mcpTool.description,
                inputSchema: mcpTool.inputSchema ?? .object(properties: [:], additionalProperties: true),
                annotations: mcpTool.annotations ?? .init()
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
                            "mimeType": Value.string(mimeType ?? ""),
                            "metadata": Value.object(metadata?.mapValues { Value.string("\($0)") } ?? [:])
                        ]
                    case .audio(let data, let mimeType):
                        return [
                            "type": Value.string("audio"),
                            "data": Value.string(data),
                            "mimeType": Value.string(mimeType ?? "")
                        ]
                    case .resource(let uri, let mimeType, let text):
                        return [
                            "type": Value.string("resource"),
                            "uri": Value.string(uri),
                            "mimeType": Value.string(mimeType ?? ""),
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
        
        self.client = nil
        self.transport = nil
        self.process = nil
        self.availableTools = []
        
        log.info("Subprocess MCP server \(self.name) stopped")
    }
    
    func getAvailableTools() -> [Tool] {
        return self.availableTools
    }
}
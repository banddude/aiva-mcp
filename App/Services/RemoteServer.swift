import Foundation
import MCP
import JSONSchema
import OrderedCollections

// Simplified MCP remote server implementation using direct HTTP requests
// since the Swift MCP SDK doesn't have high-level client convenience methods

private struct JSONRPCRequest<T: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: T
    let jsonrpc = "2.0"
}

private struct JSONRPCResponse<T: Decodable>: Decodable {
    let id: Int?
    let result: T?
    let error: RPCError?
    let jsonrpc: String
    
    struct RPCError: Decodable { let code: Int; let message: String }
}

private struct RemoteToolSpec: Decodable {
    let name: String
    let description: String?
    let inputSchema: Value?
    let annotations: Annotations?
    
    struct Annotations: Decodable { let title: String? }
    
    enum CodingKeys: String, CodingKey { case name, description, annotations, inputSchemaSnake = "input_schema", inputSchemaCamel = "inputSchema" }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        annotations = try container.decodeIfPresent(Annotations.self, forKey: .annotations)
        
        // Try both input_schema and inputSchema
        inputSchema = (try? container.decodeIfPresent(Value.self, forKey: .inputSchemaSnake)) ??
                     (try? container.decodeIfPresent(Value.self, forKey: .inputSchemaCamel))
    }
}

private struct ListToolsResult: Decodable { let tools: [RemoteToolSpec] }

private struct CachedTool: Codable {
    let name: String
    let description: String
    let inputSchema: Value
    let title: String?
}

private struct EmptyParams: Encodable {}

@MainActor
final class RemoteServerService: Service, Sendable {
    private let server: ServerEntry
    private let endpoint: URL
    private let cacheKey: String
    private var cachedTools: [Tool] = []
    private var client: Client?
    
    init?(server: ServerEntry) {
        // Only handle SSE servers
        guard server.type == .sse else { return nil }
        self.server = server
        guard let urlString = server.url, let url = URL(string: urlString) else { return nil }
        self.endpoint = url
        self.cacheKey = "RemoteServer_\(server.name)_\(urlString)"
        
        // Load cached tools on startup for immediate UI responsiveness
        if let cached = Self.loadCachedTools(cacheKey: cacheKey) {
            self.cachedTools = cached
        }
        
        print("🔧 [RemoteServer] Created RemoteServer for: \(server.name) at \(url)")
    }

    nonisolated var tools: [Tool] {
        // Only return tools the user has enabled (or not explicitly disabled)
        // This is for UI/agent filtering consistency
        return MainActor.assumeIsolated {
            var enabledTools: [Tool] = []
            for tool in cachedTools {
                let key = "toolEnabled.\(server.name).\(tool.name)"
                // If absent from UserDefaults, default to enabled (true)
                if UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) {
                    enabledTools.append(tool)
                }
            }
            return enabledTools
        }
    }

    var isActivated: Bool {
        get async { client != nil && !cachedTools.isEmpty }
    }

    func activate() async throws {
        print("🔧 [RemoteServer] Activating server: \(server.name)")
        
        // Create MCP Client (reuse if possible)
        let client = self.client ?? Client(name: "AIVA", version: "1.0.0")

        // Build URLSession configuration to include custom headers if provided
        let configuration: URLSessionConfiguration = {
            let config = URLSessionConfiguration.default
            if let key = server.headerKey, let value = server.headerValue, !key.isEmpty, !value.isEmpty {
                var headers = config.httpAdditionalHeaders as? [String: String] ?? [:]
                headers[key] = value
                config.httpAdditionalHeaders = headers
            }
            return config
        }()

        // Heuristic: many servers expose SSE at "/sse" and POST at "/messages"
        // The SDK's HTTPClientTransport uses a single endpoint for both.
        // If the provided URL ends with "/sse", switch to "/messages" and disable streaming.
        let urlStr = endpoint.absoluteString
        let prefersMessagesEndpoint = urlStr.hasSuffix("/sse") || urlStr.hasSuffix("/sse/")

        // Compute primary endpoint + streaming flag
        let primaryEndpoint: URL
        let primaryStreaming: Bool
        if prefersMessagesEndpoint {
            if var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) {
                var parts = comps.path.split(separator: "/").map(String.init)
                if parts.last == "sse" { parts.removeLast(); parts.append("messages") }
                comps.path = "/" + parts.joined(separator: "/")
                primaryEndpoint = comps.url ?? endpoint
                primaryStreaming = false
            } else {
                primaryEndpoint = endpoint
                primaryStreaming = false
            }
        } else {
            primaryEndpoint = endpoint
            // If they gave us a messages endpoint explicitly, avoid SSE
            primaryStreaming = !urlStr.hasSuffix("/messages") && !urlStr.hasSuffix("/messages/")
        }

        // Try primary connection
        print("🔧 [RemoteServer] Connecting to MCP server: \(primaryEndpoint) streaming=\(primaryStreaming)")
        do {
            let transport = HTTPClientTransport(endpoint: primaryEndpoint, configuration: configuration, streaming: primaryStreaming)
            let initResult = try await client.connect(transport: transport)
            print("🔧 [RemoteServer] Connected! Server capabilities: \(initResult.capabilities)")
        } catch {
            // Fallback: if 404/endpoint error, try '/messages' without streaming
            let fallbackEndpoint: URL
            if var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) {
                var parts = comps.path.split(separator: "/").map(String.init)
                if parts.last != "messages" { parts.append("messages") }
                comps.path = "/" + parts.joined(separator: "/")
                fallbackEndpoint = comps.url ?? endpoint
            } else {
                fallbackEndpoint = endpoint
            }
            print("🔧 [RemoteServer] Primary connect failed (\(error)). Retrying: \(fallbackEndpoint) streaming=false")
            let transport = HTTPClientTransport(endpoint: fallbackEndpoint, configuration: configuration, streaming: false)
            let initResult = try await client.connect(transport: transport)
            print("🔧 [RemoteServer] Connected (fallback)! Server capabilities: \(initResult.capabilities)")
        }
        
        // List tools using the official MCP client
        let (mcpTools, _) = try await client.listTools()
        print("🔧 [RemoteServer] Retrieved \(mcpTools.count) tools from server")
        
        // Convert MCP tools to AIVA tools
        var aivaTools: [Tool] = []
        for mcpTool in mcpTools {
            if let tool = convertMCPToolToAIVATool(mcpTool, client: client) {
                aivaTools.append(tool)
            }
        }
        
        self.client = client
        self.cachedTools = aivaTools
        Self.saveCachedTools(aivaTools, cacheKey: cacheKey)
        print("✅ [RemoteServer] Successfully activated with \(aivaTools.count) tools")
    }

    @discardableResult
    func refreshTools() async throws -> [Tool] {
        // Just call activate which now uses proper MCP SDK
        try await activate()
        return cachedTools
    }
    
    private func convertMCPToolToAIVATool(_ mcpTool: MCP.Tool, client: Client) -> Tool? {
        // Convert MCP JSONSchema to AIVA JSONSchema  
        let schema = convertMCPJSONSchemaToAIVA(mcpTool.inputSchema ?? .object(properties: [:]))
        let annotations = MCP.Tool.Annotations(
            title: mcpTool.annotations.title,
            readOnlyHint: mcpTool.annotations.readOnlyHint,
            destructiveHint: mcpTool.annotations.destructiveHint,
            idempotentHint: mcpTool.annotations.idempotentHint,
            openWorldHint: mcpTool.annotations.openWorldHint
        )
        
        print("🔨 [RemoteServer] Converting MCP tool: \(mcpTool.name) for server: \(server.name)")
        
        return Tool(
            name: mcpTool.name,
            description: mcpTool.description,
            inputSchema: schema,
            annotations: annotations
        ) { [weak self] (input: [String: Value]) async throws -> Value in
            print("🎯 [RemoteServer] MCP Tool closure called for: \(mcpTool.name) with input: \(input)")
            
            guard let self else {
                print("❌ [RemoteServer] Self is nil for tool: \(mcpTool.name)")
                return Value.object([:])
            }
            
            do {
                // Convert AIVA Value dictionary to MCP arguments
                var mcpArguments: [String: Value] = [:]
                for (key, value) in input {
                    mcpArguments[key] = value
                }
                
                // Call tool using MCP client
                let (content, isError) = try await client.callTool(name: mcpTool.name, arguments: mcpArguments)
                
                if isError == true {
                    print("❌ [RemoteServer] MCP tool \(mcpTool.name) returned error")
                    return Value.object([:])
                }
                
                // Convert MCP content to AIVA Value
                return self.convertMCPContentToValue(content)
                
            } catch {
                print("❌ [RemoteServer] MCP Tool \(mcpTool.name) error: \(error)")
                return Value.object([:])
            }
        }
    }
    
    private func callRemoteTool(name: String, args: [String: Value]) async throws -> Value {
        struct CallParams: Encodable { 
            let name: String
            let arguments: [String: Value]?
        }
        
        print("🔧 [RemoteServer] Calling remote tool: \(name) with args: \(args)")
        
        let postURL = resolvePostURL(from: endpoint)
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        
        // MCP-compatible headers - avoid 417 Expectation Failed
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Custom headers from server config
        if let k = server.headerKey, let v = server.headerValue, !k.isEmpty, !v.isEmpty {
            req.setValue(v, forHTTPHeaderField: k)
        }
        
        let params = CallParams(name: name, arguments: args.isEmpty ? nil : args)
        let rpc = JSONRPCRequest(id: 2, method: "tools/call", params: params)
        req.httpBody = try JSONEncoder().encode(rpc)
        
        // Create URLSession without Expect: 100-continue
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldUsePipelining = false
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        
        print("🔧 [RemoteServer] Making tools/call request to: \(postURL)")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let responseString = String(data: data, encoding: .utf8) ?? ""
        print("🔧 [RemoteServer] Tool response: \(responseString)")
        
        // Handle both regular JSON and SSE responses
        var resultData = data
        if responseString.contains("event: message") && responseString.contains("data: ") {
            let lines = responseString.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    resultData = jsonString.data(using: .utf8) ?? Data()
                    break
                }
            }
        }
        
        struct ToolCallResult: Decodable {
            let content: [ContentItem]
            let isError: Bool?
            
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }
        }
        
        do {
            let decoded = try JSONDecoder().decode(JSONRPCResponse<ToolCallResult>.self, from: resultData)
            
            if let err = decoded.error { 
                throw NSError(domain: "JSONRPC", code: err.code, userInfo: [NSLocalizedDescriptionKey: err.message]) 
            }
            
            guard let result = decoded.result else {
                return Value.object([:])
            }
            
            // Convert content to Value
            if let textContent = result.content.first?.text {
                // Try to parse as JSON first
                if let jsonData = textContent.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                    return convertJSONToValue(jsonObject)
                } else {
                    return Value.string(textContent)
                }
            }
            
            return Value.object([:])
            
        } catch {
            print("🔧 [RemoteServer] Tool call decode error: \(error)")
            return Value.object([:])
        }
    }
    
    // Convert MCP Tool.Content to AIVA Value
    nonisolated private func convertMCPContentToValue(_ content: [MCP.Tool.Content]) -> Value {
        // Handle MCP Tool.Content array
        if content.isEmpty {
            return .object([:])
        }
        
        // If single content item, return it directly
        if content.count == 1 {
            return convertSingleContentToValue(content[0])
        }
        
        // Multiple content items - return as array
        var values: [Value] = []
        for item in content {
            values.append(convertSingleContentToValue(item))
        }
        return .array(values)
    }
    
    nonisolated private func convertSingleContentToValue(_ content: MCP.Tool.Content) -> Value {
        switch content {
        case .text(let text):
            // Try to parse as JSON first
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return convertJSONToValue(json)
            }
            // Otherwise return as text
            return .string(text)
        case let .image(data, mimeType, _):
            // Return image info as object
            return .object([
                "type": .string("image"),
                "data": .string(data),
                "mimeType": .string(mimeType)
            ])
        case let .resource(uri, mimeType, text):
            // Return resource info as object
            return .object([
                "type": .string("resource"),
                "uri": .string(uri),
                "text": .string(text ?? ""),
                "mimeType": .string(mimeType)
            ])
        case let .audio(data, mimeType):
            // Return audio info as object
            return .object([
                "type": .string("audio"),
                "data": .string(data),
                "mimeType": .string(mimeType)
            ])
        }
    }
    
    // Convert MCP JSONSchema to AIVA JSONSchema
    nonisolated private func convertMCPJSONSchemaToAIVA(_ mcpSchema: JSONSchema) -> JSONSchema {
        // Since both are JSONSchema, we can directly return
        // In the future, if there are differences, we can convert here
        return mcpSchema
    }
    
    // Helper conversion functions
    nonisolated private func convertJSONToValue(_ json: Any) -> Value {
        if let str = json as? String {
            return .string(str)
        } else if let num = json as? Double {
            return .double(num)
        } else if let num = json as? Int {
            return .int(num)
        } else if let bool = json as? Bool {
            return .bool(bool)
        } else if let arr = json as? [Any] {
            var values: [Value] = []
            for item in arr {
                values.append(convertJSONToValue(item))
            }
            return .array(values)
        } else if let dict = json as? [String: Any] {
            var result: [String: Value] = [:]
            for (key, value) in dict {
                result[key] = convertJSONToValue(value)
            }
            return .object(result)
        } else {
            return .object([:])
        }
    }
    
    nonisolated private func convertValueToJSONSchema(_ value: Value) -> JSONSchema {
        switch value {
        case .null:
            return .null
        case .bool(_):
            return .boolean()
        case .int(_):
            return .integer()
        case .double(_):
            return .number()
        case .string(_):
            return .string()
        case .data(_, _):
            return .string() // Represent data as base64 string
        case .array(let arr):
            let itemSchema: JSONSchema = arr.isEmpty ? .null : convertValueToJSONSchema(arr[0])
            return .array(items: itemSchema)
        case .object(let obj):
            var properties = OrderedDictionary<String, JSONSchema>()
            for (key, val) in obj {
                properties[key] = convertValueToJSONSchema(val)
            }
            return .object(properties: properties, required: [])
        }
    }
    
    nonisolated private func resolvePostURL(from baseURL: URL) -> URL {
        if baseURL.absoluteString.hasSuffix("/messages") {
            return baseURL
        } else if baseURL.pathComponents.count > 1 {
            return baseURL
        } else {
            return baseURL.appendingPathComponent("messages")
        }
    }
    
    private static func loadCachedTools(cacheKey: String) -> [Tool]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let specs = try? JSONDecoder().decode([CachedTool].self, from: data) else { return nil }
        
        var tools: [Tool] = []
        for cachedTool in specs {
            let tool = Tool(
                name: cachedTool.name,
                description: cachedTool.description,
                inputSchema: convertValueToJSONSchemaStatic(cachedTool.inputSchema),
                annotations: .init(
                    title: cachedTool.title,
                    readOnlyHint: false,
                    openWorldHint: true
                )
            ) { _ in Value.object([:]) }
            tools.append(tool)
        }
        return tools
    }
    
    private static func saveCachedTools(_ tools: [Tool], cacheKey: String) {
        var specs: [CachedTool] = []
        for t in tools {
            let spec = CachedTool(
                name: t.name, 
                description: t.description, 
                inputSchema: convertJSONSchemaToValue(t.inputSchema), 
                title: t.annotations.title
            )
            specs.append(spec)
        }
        if let data = try? JSONEncoder().encode(specs) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    private static func convertValueToJSONSchemaStatic(_ value: Value) -> JSONSchema {
        switch value {
        case .null:
            return .null
        case .bool(_):
            return .boolean()
        case .int(_):
            return .integer()
        case .double(_):
            return .number()
        case .string(_):
            return .string()
        case .data(_, _):
            return .string()
        case .array(let arr):
            let itemSchema: JSONSchema = arr.isEmpty ? .null : convertValueToJSONSchemaStatic(arr[0])
            return .array(items: itemSchema)
        case .object(let obj):
            var properties = OrderedDictionary<String, JSONSchema>()
            for (key, val) in obj {
                properties[key] = convertValueToJSONSchemaStatic(val)
            }
            return .object(properties: properties, required: [])
        }
    }
    
    private static func convertJSONSchemaToValue(_ schema: JSONSchema) -> Value {
        // This is simplified - we just return a basic value for caching purposes
        return .object([:])
    }
}

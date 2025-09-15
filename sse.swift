import SwiftUI

// Minimal JSON-RPC types
struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Params
}
struct EmptyParams: Encodable {}

struct Tool: Identifiable, Decodable {
    let name: String
    let description: String?
    var id: String { name }
}
struct ListToolsResult: Decodable {
    let tools: [Tool]
}
struct JSONRPCResponse<ResultType: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: ResultType?
    let error: RPCError?
    struct RPCError: Decodable { let code: Int; let message: String }
}

@main
struct MCPBrowserApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var sseURL = "https://officeadmin.io/mcp/qb/sse"
    @State private var authHeaderKey = ""        // e.g. "Authorization"
    @State private var authHeaderValue = ""      // e.g. "Bearer sk-…"
    @State private var discoveredPostURL = ""    // filled automatically from SSE event; can be edited
    @State private var isConnecting = false
    @State private var log = ""
    @State private var tools: [Tool] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCP SSE Tool Lister").font(.title2).bold()

            VStack(alignment: .leading) {
                Text("SSE URL")
                TextField("https://…/sse", text: $sseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Auth Header Key (optional)")
                    TextField("Authorization or X-API-Key", text: $authHeaderKey)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Auth Header Value (optional)")
                    SecureField("Bearer …", text: $authHeaderValue)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading) {
                Text("POST URL (auto-filled from SSE; override if needed)")
                TextField("https://…/messages", text: $discoveredPostURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Button(action: connectAndListTools) {
                    Label(isConnecting ? "Connecting…" : "Connect & List Tools", systemImage: "link")
                }
                .disabled(isConnecting)
                Button(role: .destructive) {
                    tools.removeAll(); log.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }

            Divider()

            if !tools.isEmpty {
                Text("Tools (\(tools.count))").font(.headline)
                List(tools) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.name).font(.body.monospaced()).bold()
                        if let d = t.description, !d.isEmpty {
                            Text(d).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No tools yet.").foregroundStyle(.secondary)
            }

            Divider()
            Text("Log").font(.headline)
            ScrollView {
                Text(log).font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(.secondarySystemBackground))
        }
        .padding()
    }

    // MARK: - Networking

    func connectAndListTools() {
        tools.removeAll()
        log.removeAll()
        isConnecting = true

        // 1) Open SSE stream to sseURL and wait for an event that contains the POST endpoint.
        Task {
            do {
                let postURL = try await openSSEAndDiscoverPostURL(sseURL: sseURL)
                await MainActor.run {
                    discoveredPostURL = postURL.absoluteString
                    log.append("Discovered POST endpoint: \(postURL.absoluteString)\n")
                }

                // 2) Send tools/list JSON-RPC to that POST URL
                let listed = try await fetchTools(postURL: postURL)
                await MainActor.run {
                    self.tools = listed
                    self.log.append("Fetched \(listed.count) tools.\n")
                    self.isConnecting = false
                }
            } catch {
                await MainActor.run {
                    self.log.append("Error: \(error.localizedDescription)\n")
                    self.isConnecting = false
                }
            }
        }
    }

    // Opens an SSE stream and looks for an event whose data JSON includes the POST endpoint.
    // Common patterns:
    // { "endpoint": "/messages/abcd" }   or   { "postUrl": "https://…/messages/abcd" }
    // We try both keys and resolve relative -> absolute.
    func openSSEAndDiscoverPostURL(sseURL: String) async throws -> URL {
        guard let url = URL(string: sseURL) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !authHeaderKey.isEmpty && !authHeaderValue.isEmpty {
            req.setValue(authHeaderValue, forHTTPHeaderField: authHeaderKey)
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse SSE lines until we find a data: … that decodes to JSON containing the endpoint
        var iterator = bytes.lines.makeAsyncIterator()
        while let line = try await iterator.next() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { self.log.append("SSE> \(trimmed)\n") }

            // SSE format: lines starting with "data: "
            if trimmed.hasPrefix("data:") {
                let payload = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                if let endpointURL = try parseEndpoint(from: payload, base: url) {
                    return endpointURL
                }
            }
        }

        throw NSError(domain: "SSE", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Did not receive endpoint in SSE stream"])
    }

    func parseEndpoint(from jsonString: String, base: URL) throws -> URL? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Try common keys
            if let ep = (obj["endpoint"] as? String) ?? (obj["postUrl"] as? String) ?? (obj["url"] as? String) {
                if let absolute = URL(string: ep, relativeTo: base)?.absoluteURL { return absolute }
            }
            // Some servers send { "endpoint": { "path": "/messages/…" } }
            if let nested = obj["endpoint"] as? [String: Any], let path = nested["path"] as? String {
                if let absolute = URL(string: path, relativeTo: base)?.absoluteURL { return absolute }
            }
        }
        return nil
    }

    // POST a JSON-RPC tools/list and decode the result
    func fetchTools(postURL: URL) async throws -> [Tool] {
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !authHeaderKey.isEmpty && !authHeaderValue.isEmpty {
            req.setValue(authHeaderValue, forHTTPHeaderField: authHeaderKey)
        }

        let rpc = JSONRPCRequest(id: 1, method: "tools/list", params: EmptyParams())
        req.httpBody = try JSONEncoder().encode(rpc)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(JSONRPCResponse<ListToolsResult>.self, from: data)
        if let err = decoded.error {
            throw NSError(domain: "JSONRPC", code: err.code,
                          userInfo: [NSLocalizedDescriptionKey: err.message])
        }
        return decoded.result?.tools ?? []
    }
}

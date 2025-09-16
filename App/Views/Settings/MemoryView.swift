import SwiftUI
import AppKit

struct MemoryView: View {
    @AppStorage("memoryNeo4jUrl") private var neo4jUrl = ""
    @AppStorage("memoryNeo4jUsername") private var neo4jUsername = ""
    @AppStorage("memoryNeo4jPassword") private var neo4jPassword = ""
    @AppStorage("memoryNeo4jDatabase") private var neo4jDatabase = "neo4j"
    @State private var showPassword = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    
    enum ConnectionStatus {
        case unknown
        case connected
        case disconnected
        case testing
        
        var color: Color {
            switch self {
            case .unknown: return .gray
            case .connected: return .green
            case .disconnected: return .red
            case .testing: return .orange
            }
        }
        
        var text: String {
            switch self {
            case .unknown: return "Unknown"
            case .connected: return "Connected"
            case .disconnected: return "Disconnected"
            case .testing: return "Testing..."
            }
        }
        
        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .connected: return "checkmark.circle"
            case .disconnected: return "xmark.circle"
            case .testing: return "arrow.triangle.2.circlepath"
            }
        }
    }
    
    private var connectButtonTint: Color {
        switch connectionStatus {
        case .connected: return .green
        case .disconnected: return .red
        case .testing: return .orange
        case .unknown: return .accentColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header matching AgentsView style
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Memory")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        // Connection status and tool count
                        HStack(spacing: 4) {
                            if connectionStatus == .connected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text("\(MemoryService.shared.tools.count) tools available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: connectionStatus == .testing ? "clock" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(connectionStatus == .testing ? .orange : .red)
                                    .font(.caption)
                                Text(connectionStatus == .testing ? "Testing connection..." : "Not connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Text("Configure Neo4j knowledge graph storage")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Memory Service Card
                    VStack(alignment: .leading, spacing: 12) {
                        
                        // Configuration fields
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Database")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("neo4j", text: $neo4jDatabase)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                                .frame(minWidth: 100)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Username")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("Username", text: $neo4jUsername)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                                .frame(minWidth: 120)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Database URL")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("neo4j+s://your-instance.databases.neo4j.io", text: $neo4jUrl)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Password")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                if showPassword {
                                    TextField("Password", text: $neo4jPassword)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                } else {
                                    SecureField("Password", text: $neo4jPassword)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Auto-test connection on first appear if configured
            if connectionStatus == .unknown && !neo4jUrl.isEmpty && !neo4jUsername.isEmpty && !neo4jPassword.isEmpty {
                testConnection()
            }
        }
        .onChange(of: neo4jUrl) { _, _ in checkConnectionStatus() }
        .onChange(of: neo4jUsername) { _, _ in checkConnectionStatus() }
        .onChange(of: neo4jPassword) { _, _ in checkConnectionStatus() }
        .onChange(of: neo4jDatabase) { _, _ in checkConnectionStatus() }
    }
    
    private func testConnection() {
        connectionStatus = .testing
        
        Task {
            do {
                // Test connection by trying to read the graph
                let memory = MemoryService.shared
                _ = try await memory.call(tool: "read_graph", with: [:])
                
                await MainActor.run {
                    connectionStatus = .connected
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .disconnected
                }
            }
        }
    }
    
    private func checkConnectionStatus() {
        // Only reset connection status when settings actually change
        // If we're already connected/disconnected, don't reset to unknown
        if connectionStatus == .connected || connectionStatus == .disconnected {
            connectionStatus = .unknown
        }
    }

    private func labelRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}
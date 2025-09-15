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
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                        Image(systemName: "brain")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 32, height: 32)
                    Text("Memory")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        testConnection()
                    } label: {
                        HStack(spacing: 6) {
                            switch connectionStatus {
                            case .testing:
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting...")
                            case .connected:
                                Image(systemName: "checkmark.circle.fill")
                                Text("Connected")
                            case .disconnected:
                                Image(systemName: "arrow.clockwise.circle")
                                Text("Retry")
                            case .unknown:
                                Image(systemName: "bolt.horizontal.circle")
                                Text("Connect")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(connectButtonTint)
                    .disabled(connectionStatus == .testing)

                    Button("Clear") {
                        neo4jUrl = ""
                        neo4jUsername = ""
                        neo4jPassword = ""
                        neo4jDatabase = "neo4j"
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Card: Connection Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Configure your Neo4j connection for memory storage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Simple vertical layout to prevent text wrapping
                    VStack(spacing: 16) {
                        // Database Name and URL row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                labelRow(icon: "cylinder.fill", color: .orange, title: "Database")
                                TextField("neo4j", text: $neo4jDatabase)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .frame(minWidth: 120)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                labelRow(icon: "link", color: .blue, title: "Database URL")
                                TextField("neo4j+s://your-instance.databases.neo4j.io", text: $neo4jUrl)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        
                        // Username and Password row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                labelRow(icon: "person.crop.square.filled.and.at.rectangle.fill", color: .green, title: "Username")
                                TextField("Username", text: $neo4jUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .frame(minWidth: 120)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    labelRow(icon: "lock.fill", color: .purple, title: "Password")
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
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            checkConnectionStatus()
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
        // Set to unknown when settings change, requiring a test
        connectionStatus = .unknown
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
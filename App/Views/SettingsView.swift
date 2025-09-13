import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController {
    convenience init(serverController: ServerController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView(serverController: serverController))
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 300)
        self.init(window: window)
    }
}

struct SettingsView: View {
    @ObservedObject var serverController: ServerController
    @State private var selectedSection: SettingsSection? = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case memory = "Memory"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .memory: return "brain"
            }
        }
    }

    var body: some View {
        NavigationView {
            List(
                selection: .init(
                    get: { selectedSection },
                    set: { section in
                        selectedSection = section
                    }
                )
            ) {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }

            if let selectedSection {
                switch selectedSection {
                case .general:
                    GeneralSettingsView(serverController: serverController)
                        .navigationTitle("General")
                        .formStyle(.grouped)
                case .memory:
                    MemorySettingsView()
                        .navigationTitle("Memory")
                        .formStyle(.grouped)
                }
            } else {
                Text("Select a category")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            Text("")
        }
        .task {
            let window = NSApplication.shared.keyWindow
            window?.toolbarStyle = .unified
            window?.toolbar?.displayMode = .iconOnly
        }
        .onAppear {
            if selectedSection == nil, let firstSection = SettingsSection.allCases.first {
                selectedSection = firstSection
            }
        }
    }

}

struct GeneralSettingsView: View {
    @ObservedObject var serverController: ServerController
    @State private var showingResetAlert = false
    @State private var selectedClients = Set<String>()

    private var trustedClients: [String] {
        serverController.getTrustedClients()
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Trusted Clients")
                            .font(.headline)
                        Spacer()
                        if !trustedClients.isEmpty {
                            Button("Remove All") {
                                showingResetAlert = true
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }

                    Text("Clients that automatically connect without approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                if trustedClients.isEmpty {
                    HStack {
                        Text("No trusted clients")
                            .foregroundStyle(.secondary)
                            .italic()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    List(trustedClients, id: \.self, selection: $selectedClients) { client in
                        HStack {
                            Text(client)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                        .contextMenu {
                            Button("Remove Client", role: .destructive) {
                                serverController.removeTrustedClient(client)
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: 200)
                    .onDeleteCommand {
                        for clientID in selectedClients {
                            serverController.removeTrustedClient(clientID)
                        }
                        selectedClients.removeAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Remove All Trusted Clients", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                serverController.resetTrustedClients()
                selectedClients.removeAll()
            }
        } message: {
            Text(
                "This will remove all trusted clients. They will need to be approved again when connecting."
            )
        }
    }
}

struct MemorySettingsView: View {
    @AppStorage("memoryNeo4jUrl") private var neo4jUrl = "neo4j+s://54f7352a.databases.neo4j.io"
    @AppStorage("memoryNeo4jUsername") private var neo4jUsername = "neo4j"
    @AppStorage("memoryNeo4jPassword") private var neo4jPassword = "LlTnVK-QQie_GwI2xYjfSdYktv9_a0cVDF8sJB_zvgs"
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        Text("Neo4j Connection")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        // Connection Status Indicator
                        HStack(spacing: 4) {
                            Image(systemName: connectionStatus.icon)
                                .foregroundStyle(connectionStatus.color)
                                .symbolRenderingMode(.multicolor)
                                .font(.caption)
                                .symbolEffect(.rotate, isActive: connectionStatus == .testing)
                            Text(connectionStatus.text)
                                .font(.caption)
                                .foregroundStyle(connectionStatus.color)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(connectionStatus.color.opacity(0.1))
                        .cornerRadius(6)
                        
                        Spacer()
                        
                        // Action Buttons moved to header
                        HStack(spacing: 12) {
                            Button("Test Connection") {
                                testConnection()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(connectionStatus == .testing)
                            
                            Button("Reset to Defaults") {
                                neo4jUrl = "neo4j+s://54f7352a.databases.neo4j.io"
                                neo4jUsername = "neo4j"
                                neo4jPassword = "LlTnVK-QQie_GwI2xYjfSdYktv9_a0cVDF8sJB_zvgs"
                                neo4jDatabase = "neo4j"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                    Text("Configure your Neo4j database connection for memory storage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Connection Form
                VStack(spacing: 20) {
                    // Database URL
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                                .frame(width: 16)
                            Text("Database URL")
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        TextField("neo4j+s://your-instance.databases.neo4j.io", text: $neo4jUrl)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // Credentials Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.green)
                                .frame(width: 16)
                            Text("Credentials")
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        
                        VStack(spacing: 12) {
                            // Username
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Username")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField("Username", text: $neo4jUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            // Password
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Password")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
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
                    
                    // Database Name
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cylinder")
                                .foregroundStyle(.orange)
                                .frame(width: 16)
                            Text("Database Name")
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        TextField("Database name", text: $neo4jDatabase)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
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
}

import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController {
    convenience init(serverController: ServerController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView(serverController: serverController))
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 300)
        self.init(window: window)
    }
}

struct SettingsView: View {
    @ObservedObject var serverController: ServerController
    @State private var selectedSection: SettingsSection? = .clients

    enum SettingsSection: String, CaseIterable, Identifiable {
        case clients = "Clients"
        case memory = "Memory"
        case tools = "Tools"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .clients: return "person.2"
            case .memory: return "brain"
            case .tools: return "hammer"
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
                case .clients:
                    GeneralSettingsView(serverController: serverController)
                        .navigationTitle("Clients")
                case .memory:
                    MemorySettingsView()
                        .navigationTitle("Memory")
                        .formStyle(.grouped)
                case .tools:
                    ToolsCatalogView(serviceConfigs: serverController.computedServiceConfigs)
                        .navigationTitle("Tools")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    Text("Clients")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    if !trustedClients.isEmpty {
                        Button("Remove All", role: .destructive) {
                            showingResetAlert = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Text("Trusted clients connect automatically without approval.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                // Card with list of clients or empty state
                VStack(alignment: .leading, spacing: 12) {
                    if trustedClients.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No trusted clients yet")
                                .font(.headline)
                            Text("Approve a client once, then add it here to trust it for future connections.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    } else {
                        List(trustedClients, id: \.self, selection: $selectedClients) { client in
                            HStack {
                                Image(systemName: "lock.open")
                                    .foregroundStyle(.green)
                                Text(client)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    serverController.removeTrustedClient(client)
                                }
                            }
                        }
                        .frame(minHeight: 140, maxHeight: 260)
                        .onDeleteCommand {
                            for clientID in selectedClients {
                                serverController.removeTrustedClient(clientID)
                            }
                            selectedClients.removeAll()
                        }

                        HStack {
                            Button("Remove Selected", role: .destructive) {
                                for clientID in selectedClients {
                                    serverController.removeTrustedClient(clientID)
                                }
                                selectedClients.removeAll()
                            }
                            .disabled(selectedClients.isEmpty)
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
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
    private let labelHeight: CGFloat = 20
    private let leftColumnWidth: CGFloat = 260
    
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
                    Image(systemName: "brain")
                        .foregroundStyle(.blue)
                        .font(.title2)
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

                    Button("Reset Defaults") {
                        neo4jUrl = "neo4j+s://54f7352a.databases.neo4j.io"
                        neo4jUsername = "neo4j"
                        neo4jPassword = "LlTnVK-QQie_GwI2xYjfSdYktv9_a0cVDF8sJB_zvgs"
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

                    // Proper grid alignment: two rows, two columns
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            // Row 1: DB Name (left) | URL (right)
                            VStack(alignment: .leading, spacing: 6) {
                                labelRow(icon: "cylinder", color: .orange, title: "Database Name")
                                TextField("Database name", text: $neo4jDatabase)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .frame(width: leftColumnWidth, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                labelRow(icon: "link", color: .blue, title: "Database URL")
                                TextField("neo4j+s://your-instance.databases.neo4j.io", text: $neo4jUrl)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GridRow {
                            // Row 2: Username (left) | Password (right)
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    labelRow(icon: "person", color: .green, title: "Username")
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .frame(height: labelHeight)

                                TextField("Username", text: $neo4jUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .frame(width: leftColumnWidth, alignment: .leading)

                            ZStack(alignment: .topTrailing) {
                                VStack(alignment: .leading, spacing: 6) {
                                    // Label (uniform height)
                                    labelRow(icon: "key", color: .purple, title: "Password")
                                        .frame(height: labelHeight, alignment: .leading)

                                    // Field
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

                                // Eye aligned to the far right edge of the field (container's trailing)
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

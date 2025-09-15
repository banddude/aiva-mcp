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
        case servers = "Servers"
        case memory = "Memory"
        case tools = "Tools"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .clients: return "person.2"
            case .servers: return "server.rack"
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
                case .servers:
                    ServersSettingsView(controller: serverController)
                        .navigationTitle("Servers")
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

struct ServersSettingsView: View {
    let controller: ServerController
    @AppStorage("customServers") private var serversData = Data()
    @State private var servers: [ServerEntry] = []
    @State private var newServerName: String = ""
    @State private var newServerURL: String = ""
    @State private var newServerType: ServerType = .sse
    @State private var newServerCommand: String = ""
    @State private var newServerArguments: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    Text("Servers")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Add MCP-compatible servers by name and URL.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Existing servers list
                    if servers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No servers added yet")
                                .font(.headline)
                            Text("Use the form below to add your first server.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(servers.enumerated()), id: \.element.id) { index, _ in
                                ServerRowView(
                                    server: $servers[index],
                                    didChange: {
                                        save()
                                        NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                                    },
                                    onDelete: {
                                        let id = servers[index].id
                                        let removedList = servers.filter { $0.id == id }
                                        servers.removeAll { $0.id == id }
                                        save()
                                        NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                                        if let removed = removedList.first {
                                            print("[Servers] Removed server: \(removed.name) :: \(removed.url)")
                                        }
                                    },
                                    controller: controller
                                )
                            }
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // Add server form
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Type").frame(width: 60, alignment: .trailing)
                            Picker("Server Type", selection: $newServerType) {
                                ForEach(ServerType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Name").frame(width: 60, alignment: .trailing)
                            TextField("My Server", text: $newServerName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        if newServerType == .sse {
                            GridRow {
                                Text("URL").frame(width: 60, alignment: .trailing)
                                TextField("https://example.com/mcp", text: $newServerURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                        } else {
                            GridRow {
                                Text("Command").frame(width: 60, alignment: .trailing)
                                TextField("npx", text: $newServerCommand)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            GridRow {
                                Text("Arguments").frame(width: 60, alignment: .trailing)
                                TextField("@playwright/mcp@latest", text: $newServerArguments)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        
                        GridRow {
                            Text("")
                            HStack {
                                Button {
                                    addServer()
                                } label: {
                                    Label("Add Server", systemImage: "plus")
                                }
                                .disabled(isAddButtonDisabled())
                                Spacer()
                            }
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
        .onAppear(perform: load)
        .onChange(of: servers) { _, _ in save() }
    }

    private func load() {
        if let arr = try? JSONDecoder().decode([ServerEntry].self, from: serversData) {
            servers = arr
        } else {
            servers = []
        }
    }

    private func save() {
        serversData = (try? JSONEncoder().encode(servers)) ?? Data()
    }

    private func isAddButtonDisabled() -> Bool {
        let name = newServerName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return true }
        
        if newServerType == .sse {
            let url = newServerURL.trimmingCharacters(in: .whitespaces)
            return URL(string: url) == nil
        } else {
            let command = newServerCommand.trimmingCharacters(in: .whitespaces)
            return command.isEmpty
        }
    }
    
    private func addServer() {
        let name = newServerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        if newServerType == .sse {
            let url = newServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URL(string: url) != nil else { return }
            servers.append(ServerEntry(name: name, url: url))
        } else {
            let command = newServerCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            let args = newServerArguments.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ").map(String.init)
            guard !command.isEmpty else { return }
            servers.append(ServerEntry(name: name, command: command, arguments: args))
        }
        
        // Clear form
        newServerName = ""
        newServerURL = ""
        newServerCommand = ""
        newServerArguments = ""
        save()
        NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
    }

    private struct ServerRowView: View {
        @Binding var server: ServerEntry
        var didChange: () -> Void
        var onDelete: () -> Void
        let controller: ServerController
        @State private var isFetching = false
        @State private var status: String = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: server.type == .sse ? "shippingbox" : "terminal")
                        .foregroundStyle(server.type == .sse ? Color.accentColor : Color.yellow)
                    Text(server.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $server.name)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                    
                    if server.type == .sse {
                        Button {
                            Task {
                                isFetching = true
                                status = "Fetching..."
                                print("[Servers] Fetch Tools tapped for \(server.url ?? "")")
                                
                                // Trigger services rebuild first
                                NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                                
                                // Give the ServerController time to rebuild services
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                
                                // Find and refresh the actual service from the registry
                                let configs = controller.computedServiceConfigs
                                if let config = configs.first(where: { 
                                    $0.id == "RemoteServerService_\(server.id.uuidString)" 
                                }) {
                                    if let remoteService = config.service as? RemoteServerService {
                                        do {
                                            let tools = try await remoteService.refreshTools()
                                            status = "Fetched \(tools.count) tools"
                                            print("[Servers] \(server.name): fetched \(tools.count) tools")
                                            NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                                        } catch {
                                            status = "Error: \(error.localizedDescription)"
                                            print("[Servers] \(server.name) fetch error: \(error)")
                                        }
                                    } else {
                                        status = "Service type mismatch"
                                    }
                                } else {
                                    status = "Service not found in registry"
                                    print("[Servers] Could not find remote service in registry for: \(server.name)")
                                }
                                isFetching = false
                            }
                        } label: {
                            if isFetching { 
                                ProgressView().controlSize(.small) 
                            } else { 
                                Label("Fetch Tools", systemImage: "arrow.clockwise") 
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                
                if server.type == .sse {
                    TextField("https://example.com/mcp", text: Binding(
                        get: { server.url ?? "" },
                        set: { server.url = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    
                    Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Text("Header Key").frame(width: 90, alignment: .trailing)
                            TextField("Authorization or X-API-Key", text: Binding(get: { server.headerKey ?? "" }, set: { server.headerKey = $0 }))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Header Value").frame(width: 90, alignment: .trailing)
                            SecureField("Bearer …", text: Binding(get: { server.headerValue ?? "" }, set: { server.headerValue = $0 }))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Command:").font(.caption).foregroundStyle(.secondary)
                            Text("\(server.command ?? "") \((server.arguments ?? []).joined(separator: " "))")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        // Show status for subprocess servers
                        HStack(spacing: 4) {
                            if let config = controller.computedServiceConfigs.first(where: { 
                                $0.id == "SubprocessService_\(server.id.uuidString)" 
                            }) {
                                let toolCount = config.service.tools.count
                                if toolCount > 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Text("\(toolCount) tools available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text("Starting...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !status.isEmpty && server.type == .sse {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: server) { _, _ in didChange() }
        }
    }
}

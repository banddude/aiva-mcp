import SwiftUI

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
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Neo4j Connection")
                        .font(.headline)
                    Text("Configure your Neo4j database connection for memory storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                
                LabeledContent("Database URL:") {
                    TextField("neo4j+s://your-instance.databases.neo4j.io", text: $neo4jUrl)
                        .textFieldStyle(.roundedBorder)
                }
                
                LabeledContent("Username:") {
                    TextField("Username", text: $neo4jUsername)
                        .textFieldStyle(.roundedBorder)
                }
                
                LabeledContent("Password:") {
                    SecureField("Password", text: $neo4jPassword)
                        .textFieldStyle(.roundedBorder)
                }
                
                LabeledContent("Database:") {
                    TextField("Database name", text: $neo4jDatabase)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Button("Test Connection") {
                        // TODO: Test Neo4j connection
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button("Reset to Defaults") {
                        neo4jUrl = "neo4j+s://54f7352a.databases.neo4j.io"
                        neo4jUsername = "neo4j"
                        neo4jPassword = "LlTnVK-QQie_GwI2xYjfSdYktv9_a0cVDF8sJB_zvgs"
                        neo4jDatabase = "neo4j"
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
    }
}

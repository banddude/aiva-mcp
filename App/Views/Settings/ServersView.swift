import SwiftUI
import AppKit

struct ServersView: View {
    let controller: ServerController
    @AppStorage("customServers") private var serversData = Data()
    @State private var servers: [ServerEntry] = []
    @State private var newServerName: String = ""
    @State private var newServerURL: String = ""
    @State private var newServerType: ServerType = .sse
    @State private var newServerCommand: String = ""
    @State private var newServerArguments: String = ""
    @State private var showingAddForm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header matching AgentsView style
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Servers")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Connect to external MCP servers or run local MCP tools")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Add New Server") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingAddForm.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Add server form dropdown
                    if showingAddForm {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Add New Server")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Button("Cancel") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showingAddForm = false
                                        clearForm()
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Type")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Picker("Server Type", selection: $newServerType) {
                                        ForEach(ServerType.allCases, id: \.self) { type in
                                            Text(type.rawValue).tag(type)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Name")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("My Server", text: $newServerName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                if newServerType == .sse {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("URL")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        TextField("https://example.com/mcp", text: $newServerURL)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Command")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        TextField("npx", text: $newServerCommand)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Arguments")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        TextField("@playwright/mcp@latest", text: $newServerArguments)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                                
                                HStack {
                                    Button {
                                        addServer()
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showingAddForm = false
                                        }
                                    } label: {
                                        Label("Add Server", systemImage: "plus")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isAddButtonDisabled())
                                    
                                    Spacer()
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    }

                    // Existing servers list
                    if !servers.isEmpty {
                        VStack(spacing: 8) {
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
                                            print("[Servers] Removed server: \(removed.name) :: \(removed.url ?? "N/A")")
                                        }
                                    },
                                    controller: controller
                                )
                            }
                        }
                    }

                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        
        clearForm()
        save()
        NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
    }
    
    private func clearForm() {
        newServerName = ""
        newServerURL = ""
        newServerCommand = ""
        newServerArguments = ""
    }

    private struct ServerRowView: View {
        @Binding var server: ServerEntry
        var didChange: () -> Void
        var onDelete: () -> Void
        let controller: ServerController

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill((server.type == .sse ? Color.accentColor : Color.yellow).opacity(0.15))
                        Image(systemName: server.type == .sse ? "globe.americas.fill" : "terminal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(server.type == .sse ? Color.accentColor : Color.yellow)
                    }
                    .frame(width: 26, height: 26)
                    .padding(.top, 6) // Align with text field center
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            TextField("Name", text: $server.name)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(server.type.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if server.type == .sse {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("URL:").font(.caption).foregroundStyle(.secondary)
                            Text(server.url ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        // Show tool count for SSE servers
                        HStack(spacing: 4) {
                            if let config = controller.computedServiceConfigs.first(where: {
                                $0.id == "RemoteServerService_\(server.id.uuidString)"
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
                                    Text("Connecting...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Image(systemName: "clock")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("Loading...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                                } else if let err = (config.service as? SubprocessService)?.lastStatus, !err.isEmpty {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text(err)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
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
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
            .onChange(of: server) { _, _ in didChange() }
        }
    }
}
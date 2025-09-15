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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                        Image(systemName: "server.rack")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 32, height: 32)
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
                                            print("[Servers] Removed server: \(removed.name) :: \(removed.url ?? "N/A")")
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
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
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
                    ZStack {
                        Circle()
                            .fill((server.type == .sse ? Color.accentColor : Color.yellow).opacity(0.15))
                        Image(systemName: server.type == .sse ? "globe.americas.fill" : "terminal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(server.type == .sse ? Color.accentColor : Color.yellow)
                    }
                    .frame(width: 26, height: 26)
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

                if !status.isEmpty && server.type == .sse {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            .onChange(of: server) { _, _ in didChange() }
        }
    }
}
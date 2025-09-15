import SwiftUI
import JSONSchema

struct ToolsCatalogView: View {
    let serviceConfigs: [ServiceConfig]
    @State private var query: String = ""
    @State private var expandedServices: Set<String> = []
    @State private var refreshID = UUID()

    init(serviceConfigs: [ServiceConfig]) {
        self.serviceConfigs = serviceConfigs
        // Default to expanded for visibility
        _expandedServices = State(initialValue: Set(serviceConfigs.map { $0.id }))
    }

    private var gridColumns: [GridItem] {
        // Five columns for compact tool cards
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header to match Clients/Memory
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "hammer")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text("Tools")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tools", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(serviceConfigs, id: \.id) { config in
                        let tools = filteredTools(for: config)
                        if !tools.isEmpty {
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedServices.contains(config.id) || !query.isEmpty },
                                    set: { isOpen in
                                        if isOpen { expandedServices.insert(config.id) }
                                        else { expandedServices.remove(config.id) }
                                    }
                                )
                            ) {
                                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                                    ForEach(tools, id: \.name) { tool in
                                        ToolRow(
                                            tool: tool,
                                            isOn: toolToggle(serviceId: config.id, toolName: tool.name),
                                            serviceIconName: config.iconName,
                                            serviceColor: config.color
                                        )
                                    }
                                }
                                .padding(.vertical, 8)
                            } label: {
                                SectionHeaderLabel(
                                    iconName: config.iconName,
                                    color: config.color,
                                    name: config.name
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        if expandedServices.contains(config.id) {
                                            expandedServices.remove(config.id)
                                        } else {
                                            expandedServices.insert(config.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                        }
                    }
                }
                .animation(.default, value: expandedServices)
                .animation(.default, value: query)
            }
        }
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .aivaToolTogglesChanged)) { _ in
            // Force refresh when tools change
            refreshID = UUID()
        }
    }

    private struct SectionHeaderLabel: View {
        let iconName: String
        let color: Color
        let name: String
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(color)
                Text(name)
                    .font(.headline)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color(NSColor.selectedControlColor).opacity(0.08) : .clear)
            )
            .onHover { hovering = $0 }
        }
    }

    private func filteredTools(for config: ServiceConfig) -> [Tool] {
        let tools = config.service.tools
        guard !query.isEmpty else { return tools }
        let q = query.lowercased()
        return tools.filter { tool in
            tool.name.lowercased().contains(q) ||
            tool.description.lowercased().contains(q) ||
            (tool.annotations.title?.lowercased().contains(q) ?? false)
        }
    }
    private func toolToggle(serviceId: String, toolName: String) -> Binding<Bool> {
        let key = "toolEnabled.\(serviceId).\(toolName)"
        return Binding<Bool>(
            get: {
                if UserDefaults.standard.object(forKey: key) == nil { return true }
                return UserDefaults.standard.bool(forKey: key)
            },
            set: { newValue in
                UserDefaults.standard.set(newValue, forKey: key)
                NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
            }
        )
    }
}

private struct ToolRow: View {
    let tool: Tool
    @Binding var isOn: Bool
    @State private var isExpanded: Bool = false
    let serviceIconName: String
    let serviceColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: service icon + toggle
            HStack(alignment: .center) {
                ZStack {
                    Circle()
                        .fill(serviceColor.opacity(0.15))
                    Image(systemName: serviceIconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(serviceColor)
                }
                .frame(width: 24, height: 24)

                Spacer(minLength: 0)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            // Name below, clickable to expand (3-line fixed area)
            Button(action: { isExpanded.toggle() }) {
                Text(tool.annotations.title ?? tool.name)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(height: 42, alignment: .topLeading) // ~3 lines @12pt
                    .foregroundColor(.primary)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if !tool.description.isEmpty {
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(inputSummary(tool.inputSchema))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    private func prettySchema(_ schema: JSONSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(schema), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return String(describing: schema)
    }

    private func inputSummary(_ schema: JSONSchema) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(schema),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Inputs"
        }
        if (obj["type"] as? String) == "object" {
            let properties = (obj["properties"] as? [String: Any]) ?? [:]
            let required = Set((obj["required"] as? [String]) ?? [])
            if properties.isEmpty { return "No inputs" }
            let keys = properties.keys.sorted()
            let parts = keys.map { key in required.contains(key) ? "\(key)*" : key }
            return "Inputs: " + parts.joined(separator: ", ")
        }
        if let type = obj["type"] as? String { return "Inputs: \(type)" }
        return "Inputs"
    }
    
}

#Preview {
    // Minimal preview with a couple of services
    ToolsCatalogView(serviceConfigs: ServiceRegistry.configureServices(
        calendarEnabled: .constant(true),
        captureEnabled: .constant(true),
        contactsEnabled: .constant(false),
        locationEnabled: .constant(true),
        mailEnabled: .constant(false),
        mapsEnabled: .constant(true),
        memoryEnabled: .constant(false),
        messagesEnabled: .constant(false),
        remindersEnabled: .constant(false),
        speechEnabled: .constant(true),
        utilitiesEnabled: .constant(true),
        weatherEnabled: .constant(false)
    ))
}

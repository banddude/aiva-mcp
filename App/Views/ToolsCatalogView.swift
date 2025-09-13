import SwiftUI
import JSONSchema

struct ToolsCatalogView: View {
    let serviceConfigs: [ServiceConfig]
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(serviceConfigs, id: \.id) { config in
                    let tools = filteredTools(for: config)
                    if !tools.isEmpty {
                        Section(header: sectionHeader(config)) {
                            ForEach(tools, id: \.name) { tool in
                                ToolRow(
                                    tool: tool,
                                    isOn: toolToggle(serviceId: config.id, toolName: tool.name)
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.automatic)
        }
    }

    private func sectionHeader(_ config: ServiceConfig) -> some View {
        HStack(spacing: 8) {
            Image(systemName: config.iconName)
                .foregroundColor(config.color)
            Text(config.name)
                .font(.headline)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(tool.annotations.title ?? tool.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Show a concise summary of inputs instead of a static label
            Text(inputSummary(tool.inputSchema))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
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

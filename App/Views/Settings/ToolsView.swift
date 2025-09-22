import SwiftUI
import JSONSchema

struct ServicesView: View {
    let serviceConfigs: [ServiceConfig]
    @State private var selectedService: ServiceConfig?
    @State private var query: String = ""
    @State private var refreshID = UUID()
    @State private var sortDisabledToEnd = false

    private var serviceGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 3)]
    }

    private var toolGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let service = selectedService {
                serviceToolsView(for: service)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                servicesGridView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .aivaToolTogglesChanged)) { _ in
            refreshID = UUID()
        }
    }

    private var servicesGridView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Services")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Pick a service to manage its tools")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.bottom, 3)

            ScrollView {
                LazyVGrid(columns: serviceGridColumns, spacing: 3) {
                    ForEach(serviceConfigs) { config in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedService = config
                                query = ""
                                sortDisabledToEnd = false
                            }
                        } label: {
                            ServiceTile(
                                iconName: config.iconName,
                                color: config.color,
                                name: config.name,
                                toolCount: config.service.tools.count
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(config.name)
                        .accessibilityHint("Show tools for \(config.name)")
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func serviceToolsView(for service: ServiceConfig) -> some View {
        let tools = toolsForService(service)

        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedService = nil
                    query = ""
                    sortDisabledToEnd = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Services")
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            HStack(spacing: 0) {
                UnifiedIconView(
                    iconName: service.iconName,
                    color: service.color,
                    size: 32,
                    isEnabled: true
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(service.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("\(service.service.tools.count) tool\(service.service.tools.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    sortDisabledToEnd.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortDisabledToEnd ? "line.3.horizontal.decrease" : "line.3.horizontal")
                            .font(.caption)
                        Text(sortDisabledToEnd ? "Disabled Last" : "Sort Disabled")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 8)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tools", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(2)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.bottom, 12)

            ScrollView {
                if tools.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No tools match your search.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                } else {
                    LazyVGrid(columns: toolGridColumns, alignment: .leading, spacing: 12) {
                        ForEach(tools, id: \.id) { entry in
                            SquareToolCard(
                                tool: entry.tool,
                                isOn: toolToggle(serviceId: entry.serviceId, toolName: entry.tool.name),
                                serviceIconName: entry.serviceIconName,
                                serviceColor: entry.serviceColor,
                                serviceName: entry.serviceName
                            )
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: sortDisabledToEnd)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func toolsForService(_ config: ServiceConfig) -> [ToolWithService] {
        let tools = config.service.tools
        let filteredTools: [Tool]

        if query.isEmpty {
            filteredTools = tools
        } else {
            let q = query.lowercased()
            filteredTools = tools.filter { tool in
                tool.name.lowercased().contains(q) ||
                tool.description.lowercased().contains(q) ||
                (tool.annotations.title?.lowercased().contains(q) ?? false)
            }
        }

        var mapped = filteredTools.map { tool in
            ToolWithService(
                tool: tool,
                serviceId: config.id,
                serviceName: config.name,
                serviceIconName: config.iconName,
                serviceColor: config.color
            )
        }

        if sortDisabledToEnd {
            var enabled: [ToolWithService] = []
            var disabled: [ToolWithService] = []

            for tool in mapped {
                let key = "toolEnabled.\(tool.serviceId).\(tool.tool.name)"
                let enabledValue = UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)

                if enabledValue {
                    enabled.append(tool)
                } else {
                    disabled.append(tool)
                }
            }

            mapped = enabled + disabled
        }

        return mapped
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

    private struct ToolWithService: Identifiable {
        let tool: Tool
        let serviceId: String
        let serviceName: String
        let serviceIconName: String
        let serviceColor: Color

        var id: String {
            "\(serviceId).\(tool.name)"
        }
    }
}

private struct ServiceTile: View {
    let iconName: String
    let color: Color
    let name: String
    let toolCount: Int

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            UnifiedIconView(
                iconName: iconName,
                color: color,
                size: 64,
                isEnabled: true
            )

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 0)
    }
}

private struct SquareToolCard: View {
    let tool: Tool
    @Binding var isOn: Bool
    @State private var isExpanded: Bool = false
    let serviceIconName: String
    let serviceColor: Color
    let serviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: service icon + toggle
            HStack(alignment: .center, spacing: 0) {
                UnifiedIconView(
                    iconName: serviceIconName,
                    color: serviceColor,
                    size: 28,
                    isEnabled: true
                )

                Spacer(minLength: 0)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            // Service name
            Text(serviceName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Tool name, clickable to expand (fixed height area)
            Button(action: { isExpanded.toggle() }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(cleanToolName(tool))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isExpanded {
                        if !tool.description.isEmpty {
                            Text(tool.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(inputSummary(tool.inputSchema))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxHeight: isExpanded ? .infinity : 48, alignment: .top)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(minWidth: 160, alignment: .topLeading)
    }

    private func cleanToolName(_ tool: Tool) -> String {
        // If there's a proper title annotation, use it
        if let title = tool.annotations.title, !title.isEmpty {
            return title
        }

        // Otherwise, clean up the snake_case name
        return tool.name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
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
    ServicesView(serviceConfigs: ServiceRegistry.configureServices(
        appleMusicEnabled: .constant(true),
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

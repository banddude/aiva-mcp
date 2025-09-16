import SwiftUI
import JSONSchema

struct ToolsView: View {
    let serviceConfigs: [ServiceConfig]
    @State private var query: String = ""
    @State private var refreshID = UUID()
    @State private var sortDisabledToEnd = false

    init(serviceConfigs: [ServiceConfig]) {
        self.serviceConfigs = serviceConfigs
    }
    
    // Data structure for tools with their service info
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
    
    // All tools flattened into a single array
    private var allFilteredTools: [ToolWithService] {
        var result: [ToolWithService] = []
        
        for config in serviceConfigs {
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
            
            for tool in filteredTools {
                result.append(ToolWithService(
                    tool: tool,
                    serviceId: config.id,
                    serviceName: config.name,
                    serviceIconName: config.iconName,
                    serviceColor: config.color
                ))
            }
        }
        
        // Sort by enabled status if requested (preserve original order within groups)
        if sortDisabledToEnd {
            var enabledTools: [ToolWithService] = []
            var disabledTools: [ToolWithService] = []
            
            for tool in result {
                let key = "toolEnabled.\(tool.serviceId).\(tool.tool.name)"
                let enabled = UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
                
                if enabled {
                    enabledTools.append(tool)
                } else {
                    disabledTools.append(tool)
                }
            }
            
            result = enabledTools + disabledTools
        }
        
        return result
    }

    private var gridColumns: [GridItem] {
        // Adaptive grid that fits the current width with square tiles
        [GridItem(.adaptive(minimum: 120), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header matching other settings views
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tools")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("All available tools from connected services")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
            .padding(.bottom, 20)

            // Search
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
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                    ForEach(allFilteredTools, id: \.id) { toolWithService in
                        SquareToolCard(
                            tool: toolWithService.tool,
                            isOn: toolToggle(serviceId: toolWithService.serviceId, toolName: toolWithService.tool.name),
                            serviceIconName: toolWithService.serviceIconName,
                            serviceColor: toolWithService.serviceColor,
                            serviceName: toolWithService.serviceName
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: sortDisabledToEnd)
                .padding(.bottom, 24)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .aivaToolTogglesChanged)) { _ in
            // Force refresh when tools change
            refreshID = UUID()
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

private struct SquareToolCard: View {
    let tool: Tool
    @Binding var isOn: Bool
    @State private var isExpanded: Bool = false
    let serviceIconName: String
    let serviceColor: Color
    let serviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: service icon + toggle
            HStack(alignment: .center) {
                UnifiedIconView(
                    iconName: serviceIconName,
                    color: serviceColor,
                    size: 24,
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
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Tool name, clickable to expand (fixed height area)
            Button(action: { isExpanded.toggle() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cleanToolName(tool))
                            .font(.system(size: 12, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if isExpanded {
                            if !tool.description.isEmpty {
                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(inputSummary(tool.inputSchema))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 60) // Fixed height for content area
        }
        .padding(12)
        .frame(width: 120, height: 120) // Fixed square size
        .clipped()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    // Minimal preview with a couple of services
    ToolsView(serviceConfigs: ServiceRegistry.configureServices(
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

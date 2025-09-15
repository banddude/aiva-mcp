import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController {
    static private var sharedInstance: SettingsWindowController?
    
    static func shared(serverController: ServerController) -> SettingsWindowController {
        if let existing = sharedInstance {
            return existing
        }
        let controller = SettingsWindowController(serverController: serverController)
        sharedInstance = controller
        return controller
    }
    
    private convenience init(serverController: ServerController) {
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
        
        // Clear the shared instance when window is closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SettingsWindowController.sharedInstance = nil
            }
        }
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
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
        case logs = "Logs"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .clients: return "person.2"
            case .servers: return "server.rack"
            case .memory: return "brain"
            case .tools: return "hammer"
            case .logs: return "text.and.command.macwindow"
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
                    ClientsView(serverController: serverController)
                        .navigationTitle("Clients")
                case .servers:
                    ServersView(controller: serverController)
                        .navigationTitle("Servers")
                case .memory:
                    MemoryView()
                        .navigationTitle("Memory")
                        .formStyle(.grouped)
                case .tools:
                    ToolsView(serviceConfigs: serverController.computedServiceConfigs)
                        .navigationTitle("Tools")
                case .logs:
                    LogsView()
                        .navigationTitle("Logs")
                }
            } else {
                Text("Select a category")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Spacer()
                    .frame(minWidth: 0, minHeight: 0)
            }
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

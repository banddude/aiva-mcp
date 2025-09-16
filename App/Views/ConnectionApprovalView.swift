import AppKit
import SwiftUI

struct ConnectionApprovalView: View {
    let clientName: String
    let onApprove: (Bool) -> Void  // Bool parameter is for "always trust"
    let onDeny: () -> Void

    @State private var alwaysTrust = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow \"\(clientName)\" to connect to AIVA?")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .cornerRadius(8)

                    Text("This client can use your currently enabled services and any you enable in the future.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Always trust + actions row
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Toggle("Always trust this client", isOn: $alwaysTrust)
                    .toggleStyle(CheckboxToggleStyle())
                Spacer()
                Button("Deny") { onDeny() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Allow") { onApprove(alwaysTrust) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 450, maxWidth: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                .accessibilityLabel(configuration.isOn ? "Always trust this client, checked" : "Always trust this client, unchecked")
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

@MainActor
class ConnectionApprovalWindowController: NSObject {
    private var window: NSWindow?
    private var approvalView: ConnectionApprovalView?

    func showApprovalWindow(
        clientName: String,
        onApprove: @escaping (Bool) -> Void,
        onDeny: @escaping () -> Void
    ) {
        // Create the SwiftUI view
        let approvalView = ConnectionApprovalView(
            clientName: clientName,
            onApprove: { alwaysTrust in
                onApprove(alwaysTrust)
                self.closeWindow()
            },
            onDeny: {
                onDeny()
                self.closeWindow()
            }
        )

        // Create the hosting controller
        let hostingController = NSHostingController(rootView: approvalView)
        
        // Calculate the intrinsic content size
        let contentSize = hostingController.sizeThatFits(in: CGSize(width: 600, height: 500))

        // Create the window with dynamic size based on content
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(360, contentSize.width), height: max(175, contentSize.height)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Connection Request"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = false

        // Initial centering
        window.center()

        // Store references
        self.window = window
        self.approvalView = approvalView

        // Activate the app first
        NSApp.activate(ignoringOtherApps: true)

        // Show the window
        window.makeKeyAndOrderFront(nil)

        // Center again after showing to ensure proper positioning
        Task { @MainActor in
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let windowRect = window.frame
                let x = (screenRect.width - windowRect.width) / 2 + screenRect.origin.x
                let y = (screenRect.height - windowRect.height) / 2 + screenRect.origin.y
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }

    private func closeWindow() {
        window?.close()
        window = nil
        approvalView = nil
    }
}

#Preview {
    ConnectionApprovalView(
        clientName: "Claude Desktop",
        onApprove: { alwaysTrust in print("Approved: \(alwaysTrust)") },
        onDeny: { print("Denied") }
    )
}

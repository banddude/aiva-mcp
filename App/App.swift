import MenuBarExtraAccess
import SwiftUI

@main
struct App: SwiftUI.App {
    @StateObject private var serverController = ServerController()
    @AppStorage("isEnabled") private var isEnabled = true
    @State private var isMenuPresented = false

    init() {
        // Start capturing stdout/stderr for in-app logs view
        ConsoleCapture.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                serverManager: serverController,
                isEnabled: $isEnabled,
                isMenuPresented: $isMenuPresented
            )
        } label: {
            Image("aiva-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 10, maxHeight: 10)
                .opacity(isEnabled ? 1.0 : 0.5)
                .id(isEnabled)
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $isMenuPresented)

        Settings {
            SettingsView(serverController: serverController)
        }

        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

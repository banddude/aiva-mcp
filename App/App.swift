import MenuBarExtraAccess
import SwiftUI

@main
struct App: SwiftUI.App {
    @StateObject private var serverController = ServerController()
    @AppStorage("isEnabled") private var isEnabled = true
    @State private var isMenuPresented = false

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                serverManager: serverController,
                isEnabled: $isEnabled,
                isMenuPresented: $isMenuPresented
            )
        } label: {
            Text(isEnabled ? "AIVA" : "aiva")
                .font(.system(size: 12, weight: .medium))
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

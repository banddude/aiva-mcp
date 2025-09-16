import AppKit
import SwiftUI

class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "About AIVA"
        window.contentView = NSHostingView(rootView: AboutView())
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

private struct AboutView: View {
    private var versionString: String {
        let short = Bundle.main.shortVersionString ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        switch (short.isEmpty, build.isEmpty) {
        case (false, false): return "Version \(short) (\(build))"
        case (false, true): return "Version \(short)"
        case (true, false): return "Build \(build)"
        default: return ""
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // App icon
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            // App name and version
            if !versionString.isEmpty {
                Text(versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Keep only "Report an Issue..." link; Website/Docs removed
            Button("Report an Issue...") {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/banddude/aiva-mcp/issues/new")!
                )
            }
            .buttonStyle(.link)
            .font(.callout)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

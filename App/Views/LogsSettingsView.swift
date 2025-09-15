import SwiftUI
import AppKit

struct LogsSettingsView: View {
    @StateObject private var console = ConsoleCapture.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 8) {
            // Controls
            HStack {
                Toggle("Auto-scroll", isOn: $autoScroll)
                Spacer()
                Button("Copy All") { copyAll() }
                Button("Clear") { console.clear() }
            }
            .padding(.horizontal)

            // Log output
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(console.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .textSelection(.enabled)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: console.lines.count) { _, _ in
                    if autoScroll, console.lines.indices.last != nil {
                        withAnimation(.linear(duration: 0.15)) {
                            proxy.scrollTo(console.lines.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func copyAll() {
        let str = console.lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }
}

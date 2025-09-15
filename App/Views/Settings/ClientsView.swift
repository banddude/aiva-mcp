import SwiftUI
import AppKit

struct ClientsView: View {
    @ObservedObject var serverController: ServerController
    @State private var showingResetAlert = false
    @State private var selectedClients = Set<String>()

    private var trustedClients: [String] {
        serverController.getTrustedClients()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                        Image(systemName: "person.2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 32, height: 32)
                    Text("Clients")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    if !trustedClients.isEmpty {
                        Button("Remove All", role: .destructive) {
                            showingResetAlert = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Text("Trusted clients connect automatically without approval.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                // Card with list of clients or empty state
                VStack(alignment: .leading, spacing: 12) {
                    if trustedClients.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No trusted clients yet")
                                .font(.headline)
                            Text("Approve a client once, then add it here to trust it for future connections.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    } else {
                        List(trustedClients, id: \.self, selection: $selectedClients) { client in
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.15))
                                    Image(systemName: "person.2")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                                .frame(width: 26, height: 26)
                                Text(client)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    serverController.removeTrustedClient(client)
                                }
                            }
                        }
                        .frame(minHeight: 140, maxHeight: 260)
                        .onDeleteCommand {
                            for clientID in selectedClients {
                                serverController.removeTrustedClient(clientID)
                            }
                            selectedClients.removeAll()
                        }

                        HStack {
                            Button("Remove Selected", role: .destructive) {
                                for clientID in selectedClients {
                                    serverController.removeTrustedClient(clientID)
                                }
                                selectedClients.removeAll()
                            }
                            .disabled(selectedClients.isEmpty)
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .alert("Remove All Trusted Clients", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                serverController.resetTrustedClients()
                selectedClients.removeAll()
            }
        } message: {
            Text(
                "This will remove all trusted clients. They will need to be approved again when connecting."
            )
        }
    }
}
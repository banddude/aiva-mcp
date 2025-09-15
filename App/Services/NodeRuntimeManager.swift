import Foundation

@MainActor
final class NodeRuntimeManager {
    static let shared = NodeRuntimeManager()

    private let version = "20.17.0"

    private init() {}

    private func appSupportDir() throws -> URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "NodeRuntimeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "AppSupport not found"])
        }
        let dir = base.appendingPathComponent("AIVA/Runtime/node", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func archString() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    private func installRoot() throws -> URL {
        let dir = try appSupportDir()
        return dir.appendingPathComponent("v\(version)-darwin-\(archString())", isDirectory: true)
    }

    // Try to locate an embedded Node runtime inside the app bundle (preferred).
    private func embeddedBinURL() -> URL? {
        let fm = FileManager.default
        // The darwin-arm64 folder is copied as a folder reference to Resources
        let binURL = Bundle.main.resourceURL?.appendingPathComponent("darwin-arm64/bin", isDirectory: true)
        if let binURL = binURL {
            let nodeURL = binURL.appendingPathComponent("node")
            print("[NodeRuntimeManager] Looking for Node at: \(nodeURL.path)")
            print("[NodeRuntimeManager] File exists: \(fm.fileExists(atPath: nodeURL.path))")
            // Check if file exists (more reliable than isExecutableFile in sandboxed apps)
            if fm.fileExists(atPath: nodeURL.path) {
                print("[NodeRuntimeManager] Found bundled Node at: \(binURL.path)")
                return binURL
            }
        }
        print("[NodeRuntimeManager] Bundled Node not found")
        return nil
    }

    // Synchronous helper: return embedded Node only (no fallbacks)
    func preferEmbeddedOrInstalled() -> URL? {
        return embeddedBinURL()
    }

    func ensureInstalled() async throws -> URL { // returns bin dir
        if let embedded = embeddedBinURL() { return embedded }
        throw NSError(
            domain: "NodeRuntimeManager",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Bundled Node runtime not found in app Resources."]
        )
    }

    private func runtimeMatchesVersion(nodeBinary: URL) async throws -> Bool {
        let outPipe = Pipe()
        let p = Process()
        p.executableURL = nodeBinary
        p.arguments = ["-v"]
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return false
        }
        guard p.terminationStatus == 0 else { return false }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let ver = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ver.hasPrefix("v\(version)")
    }
}

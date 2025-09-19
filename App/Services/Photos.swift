import Foundation
import JSONSchema
import OSLog

private let log = Logger.service("photos")

@MainActor
final class PhotosService: Service, Sendable {
    static let shared = PhotosService()

    var isActivated: Bool {
        get async {
            guard FileManager.default.fileExists(atPath: "/System/Applications/Photos.app") else { return false }
            do {
                _ = try await executeAppleScript("tell application \"Photos\" to return name")
                return true
            } catch {
                log.info("Photos service not yet activated: \(error.localizedDescription)")
                return false
            }
        }
    }

    func activate() async throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Photos.app") else {
            throw NSError(domain: "PhotosError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos app not found"])
        }
        do {
            _ = try await executeAppleScript("tell application \"Photos\" to return name")
            log.info("Photos service activated successfully")
        } catch {
            log.error("Failed to activate Photos service: \(error.localizedDescription)")
            throw error
        }
    }

    nonisolated var tools: [Tool] {
        [
            Tool(
                name: "photos_export_by_search",
                description: "Use Photos UI to search and export the most recent N items to a folder",
                inputSchema: .object(
                    properties: [
                        "query": .string(description: "Search text to type into Photos' search"),
                        "count": .integer(description: "Number of items to export (default 1)"),
                        "destination": .string(description: "Destination folder (POSIX path), created if missing")
                    ],
                    required: ["query"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Export From Photos Search", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let query = input["query"]?.stringValue ?? ""
                let count = max(1, input["count"]?.intValue ?? 1)
                let dest = input["destination"]?.stringValue ?? (NSHomeDirectory() + "/Desktop/aiva-photos-export")
                return try await self.exportBySearch(query: query, count: count, destination: dest)
            }
        ]
    }

    // MARK: - Implementation

    private func exportBySearch(query: String, count: Int, destination: String) async throws -> String {
        let escapedPath = destination
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedQuery = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let rightRepeats = max(0, count - 1)

        let script = """
        -- Ensure destination exists
        set destPath to "\(escapedPath)"
        do shell script "mkdir -p " & quoted form of destPath

        tell application "Photos" to activate
        delay 0.8
        tell application "System Events"
            tell process "Photos"
                set frontmost to true
            end tell
        end tell
        delay 0.6
        
        tell application "System Events"
            -- Focus search
            tell process "Photos" to keystroke "f" using {command down}
            delay 0.4
            -- Clear and type query
            keystroke "a" using {command down}
            key code 51
            delay 0.2
            keystroke "\(escapedQuery)"
            delay 0.8
            -- Commit search
            key code 36
            delay 0.8
            -- Tab to results and select first
            key code 48
            delay 0.4
            key code 48
            delay 0.4
            -- Move down twice to ensure grid focus/selection
            key code 125
            delay 0.2
            key code 125
            delay 0.4
            -- Extend selection to desired count
            if \(rightRepeats) > 0 then
                repeat \(rightRepeats) times
                    key code 124 using {shift down}
                    delay 0.2
                end repeat
                delay 0.5
            end if
            -- Export
            keystroke "e" using {shift down, command down}
            delay 1.2
            key code 36
            delay 1.0
            -- Go to destination and confirm
            keystroke "g" using {shift down, command down}
            delay 0.6
            keystroke destPath
            key code 36
            delay 0.8
            key code 36
        end tell
        
        return "Exported \((rightRepeats) + 1) item(s) to \(escapedPath)"
        """

        _ = try await executeAppleScript(script)
        return "Exported \(rightRepeats + 1) item(s) to \(destination)"
    }

    // MARK: - AppleScript helper
    private func executeAppleScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            final class Box<T>: @unchecked Sendable {
                private let lock = NSLock()
                private var _v: T
                init(_ v: T) { _v = v }
                var value: T {
                    get { lock.lock(); defer { lock.unlock() }; return _v }
                    set { lock.lock(); defer { lock.unlock() }; _v = newValue }
                }
            }
            let resumed = Box(false)

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                if !resumed.value && task.isRunning {
                    resumed.value = true
                    task.terminate()
                    continuation.resume(throwing: NSError(domain: "PhotosError", code: 2, userInfo: [NSLocalizedDescriptionKey: "AppleScript timed out"]))
                }
            }

            task.terminationHandler = { _ in
                timeoutTask.cancel()
                if !resumed.value {
                    resumed.value = true
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if task.terminationStatus == 0 {
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        continuation.resume(throwing: NSError(domain: "PhotosError", code: 3, userInfo: [NSLocalizedDescriptionKey: output]))
                    }
                }
            }

            do { try task.run() } catch {
                if !resumed.value {
                    resumed.value = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

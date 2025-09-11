import Foundation
import JSONSchema
import OSLog

private let log = Logger.service("speech")

final class SpeechService: Service {
    static let shared = SpeechService()
    
    var isActivated: Bool {
        get async {
            // Speech is always available on macOS - no special permissions needed
            return true
        }
    }
    
    func activate() async throws {
        // No activation needed for speech
    }
    
    var tools: [Tool] {
        Tool(
            name: "speech_say",
            description: "Speak text aloud using macOS text-to-speech with the system default voice",
            inputSchema: .object(
                properties: [
                    "text": .string(description: "The text to speak aloud")
                ],
                required: ["text"],
                additionalProperties: false
            ),
            annotations: .init(
                title: "Speak Text",
                readOnlyHint: false,
                openWorldHint: false
            )
        ) { input in
            let text = input["text"]?.stringValue ?? ""
            
            guard !text.isEmpty else {
                log.error("Text cannot be empty")
                throw NSError(
                    domain: "SpeechError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Text cannot be empty"]
                )
            }
            
            let command = ["say", text]
            
            log.info("Executing speech command: \(command.joined(separator: " "))")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = Array(command.dropFirst()) // Remove "say" since it's the executable
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    return "Successfully spoke text: \"\(text)\""
                } else {
                    log.error("Speech command failed with exit code \(process.terminationStatus)")
                    throw NSError(
                        domain: "SpeechError", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Speech command failed with exit code \(process.terminationStatus)"]
                    )
                }
            } catch {
                log.error("Failed to execute speech command: \(error)")
                throw NSError(
                    domain: "SpeechError", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to execute speech: \(error.localizedDescription)"]
                )
            }
        }
    }
}
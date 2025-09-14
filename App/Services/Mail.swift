import Foundation
import JSONSchema
import OSLog

private let log = Logger.service("mail")

final class MailService: Service {
    static let shared = MailService()
    
    var isActivated: Bool {
        get async {
            // Check if Mail app is available
            let mailExists = FileManager.default.fileExists(atPath: "/Applications/Mail.app")
            return mailExists
        }
    }
    
    func activate() async throws {
        // Ensure Mail app is available and accessible
        guard await isActivated else {
            throw MailError.mailAppNotFound
        }
        
        // Test basic AppleScript execution
        _ = try await executeAppleScript("tell application \"Mail\" to return name")
        log.info("Mail service activated successfully")
    }
    
    var tools: [Tool] {
            // Reply tool
            Tool(
                name: "mail_reply",
                description: "Reply to the currently selected email in Mail app using ⌘R keyboard shortcut",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Reply to Email", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.reply()
                return "Reply command executed successfully"
            }
            
            Tool(
                name: "mail_reply_all",
                description: "Reply to all recipients of the currently selected email using ⇧⌘R keyboard shortcut",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Reply All to Email", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.replyAll()
                return "Reply all command executed successfully"
            }
            
            Tool(
                name: "mail_forward",
                description: "Forward the currently selected email using ⇧⌘F keyboard shortcut",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Forward Email", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.forward()
                return "Forward command executed successfully"
            }
            
            Tool(
                name: "mail_redirect",
                description: "Redirect the currently selected email using ⇧⌘E keyboard shortcut",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Redirect Email", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.redirect()
                return "Redirect command executed successfully"
            }
            
            Tool(
                name: "mail_search",
                description: "Search for emails in Mail app by query string",
                inputSchema: .object(
                    properties: [
                        "query": .string(description: "Search query to find emails by subject, sender, or content")
                    ],
                    required: ["query"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Search Emails", readOnlyHint: true, openWorldHint: false)
            ) { input in
                let query = input["query"]?.stringValue ?? ""
                let results = try await self.searchEmails(query: query)
                return "Found \(results.count) emails matching '\(query)'"
            }
            
            Tool(
                name: "mail_read",
                description: "Read the content of the currently selected email in Mail app",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Read Email", readOnlyHint: true, openWorldHint: false)
            ) { _ in
                let content = try await self.readSelectedEmail()
                return "Subject: \(content.subject)\nFrom: \(content.sender)\nDate: \(content.dateSent)\n\n\(content.content)"
            }
            
            Tool(
                name: "mail_draft",
                description: "Create a new email draft in Mail app",
                inputSchema: .object(
                    properties: [
                        "to": .string(description: "Recipient email address"),
                        "subject": .string(description: "Email subject line"),
                        "body": .string(description: "Email message body")
                    ],
                    required: ["to", "subject", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Create Email Draft", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let to = input["to"]?.stringValue ?? ""
                let subject = input["subject"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                try await self.createDraft(to: to, subject: subject, body: body)
                return "Email draft created successfully"
            }
            
            Tool(
                name: "mail_send",
                description: "Create and send an email directly through Mail app",
                inputSchema: .object(
                    properties: [
                        "to": .string(description: "Recipient email address"),
                        "subject": .string(description: "Email subject line"),
                        "body": .string(description: "Email message body")
                    ],
                    required: ["to", "subject", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Send Email", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let to = input["to"]?.stringValue ?? ""
                let subject = input["subject"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                try await self.sendEmail(to: to, subject: subject, body: body)
                return "Email sent successfully to \(to)"
            }
    }
    
    // MARK: - AppleScript Execution
    
    private func executeAppleScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if task.terminationStatus == 0 {
                    continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: MailError.appleScriptError(output))
                }
            }
            
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Mail Actions
    
    func reply() async throws {
        log.info("Executing reply command")
        try await activateMailAndExecuteKeyCommand("r", modifiers: ["command"])
    }
    
    func replyAll() async throws {
        log.info("Executing reply all command")
        try await activateMailAndExecuteKeyCommand("r", modifiers: ["shift", "command"])
    }
    
    func forward() async throws {
        log.info("Executing forward command")
        try await activateMailAndExecuteKeyCommand("f", modifiers: ["shift", "command"])
    }
    
    func redirect() async throws {
        log.info("Executing redirect command")
        try await activateMailAndExecuteKeyCommand("e", modifiers: ["shift", "command"])
    }
    
    private func activateMailAndExecuteKeyCommand(_ key: String, modifiers: [String]) async throws {
        let modifierString = modifiers.joined(separator: " down, ") + " down"
        let script = """
        tell application "Mail" to activate
        delay 0.5
        tell application "System Events" to keystroke "\(key)" using {\(modifierString)}
        """
        _ = try await executeAppleScript(script)
    }
    
    // MARK: - Email Search
    
    func searchEmails(query: String) async throws -> [EmailResult] {
        log.info("Searching emails with query: \(query)")
        let script = """
        tell application "Mail"
            set searchResults to search every message for "\(query)"
            set resultList to {}
            repeat with eachMessage in searchResults
                set messageInfo to {subject of eachMessage, sender of eachMessage, date sent of eachMessage}
                set end of resultList to messageInfo
            end repeat
            return resultList
        end tell
        """
        
        let output = try await executeAppleScript(script)
        return parseEmailResults(output)
    }
    
    private func parseEmailResults(_ output: String) -> [EmailResult] {
        // Parse AppleScript list output into EmailResult objects
        // This is a simplified parser - may need enhancement
        let results: [EmailResult] = []
        // TODO: Implement proper parsing of AppleScript list format
        return results
    }
    
    // MARK: - Email Reading
    
    func readSelectedEmail() async throws -> EmailContent {
        log.info("Reading selected email")
        let script = """
        tell application "Mail"
            set selectedMessages to selection
            if (count of selectedMessages) > 0 then
                set theMessage to item 1 of selectedMessages
                return {subject of theMessage, content of theMessage, sender of theMessage, date sent of theMessage}
            else
                error "No email selected"
            end if
        end tell
        """
        
        let output = try await executeAppleScript(script)
        return parseEmailContent(output)
    }
    
    private func parseEmailContent(_ output: String) -> EmailContent {
        // TODO: Implement proper parsing of email content
        return EmailContent(subject: "", content: "", sender: "", dateSent: Date())
    }
    
    // MARK: - Email Drafting & Sending
    
    func createDraft(to: String, subject: String, body: String) async throws {
        log.info("Creating email draft")
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)"}
            tell newMessage to make new to recipient at end of to recipients with properties {address:"\(to)"}
            activate
        end tell
        """
        _ = try await executeAppleScript(script)
    }
    
    func sendEmail(to: String, subject: String, body: String) async throws {
        log.info("Sending email")
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)"}
            tell newMessage to make new to recipient at end of to recipients with properties {address:"\(to)"}
            send newMessage
        end tell
        """
        _ = try await executeAppleScript(script)
    }
}

// MARK: - Data Models

struct EmailResult {
    let subject: String
    let sender: String
    let dateSent: Date
}

struct EmailContent {
    let subject: String
    let content: String
    let sender: String
    let dateSent: Date
}

// MARK: - Errors

enum MailError: Error {
    case mailAppNotFound
    case appleScriptError(String)
    case noEmailSelected
    case parsingError
}
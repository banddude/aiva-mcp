import Foundation
import JSONSchema
import OSLog

private let log = Logger.service("mail")

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    
    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
    
    init(_ value: T) {
        self._value = value
    }
}

@MainActor
final class MailService: Service, Sendable {
    static let shared = MailService()
    
    var isActivated: Bool {
        get async {
            // Check if Mail app is available
            guard FileManager.default.fileExists(atPath: "/System/Applications/Mail.app") else {
                return false
            }
            
            // Test basic AppleScript access without throwing errors
            do {
                _ = try await executeAppleScript("tell application \"Mail\" to return name")
                return true
            } catch {
                log.info("Mail service not yet activated: \(error)")
                print("🔍 Mail service isActivated check failed: \(error)")
                return false
            }
        }
    }
    
    func activate() async throws {
        // Ensure Mail app is available
        guard FileManager.default.fileExists(atPath: "/System/Applications/Mail.app") else {
            throw MailError.mailAppNotFound
        }
        
        // Test AppleScript execution - this will trigger permission prompt if needed
        do {
            _ = try await executeAppleScript("tell application \"Mail\" to return name")
            log.info("Mail service activated successfully")
            print("✅ Mail service activated successfully")
        } catch {
            log.error("Failed to activate Mail service: \(error)")
            print("❌ Mail service activation failed: \(error)")
            throw MailError.activationFailed(error.localizedDescription)
        }
    }
    
    private func getAccountNames() async -> [String] {
        do {
            let accounts = try await listAccounts()
            return accounts.map { $0.name }
        } catch {
            return ["iCloud", "Google", "SHAFFER"] // Fallback
        }
    }
    
    nonisolated var tools: [Tool] {
            // List accounts tool
            Tool(
                name: "mail_list_accounts",
                description: "List all configured mail accounts in Mail app",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "List Mail Accounts", readOnlyHint: true, openWorldHint: false)
            ) { _ in
                let accounts = try await self.listAccounts()
                return "Mail accounts:\n" + accounts.map { "- \($0.name) (\($0.email))" }.joined(separator: "\n")
            }
            
            Tool(
                name: "mail_get_unread",
                description: "Get unread emails, optionally filtered by account name (e.g., 'SHAFFER', 'Google', 'iCloud')",
                inputSchema: .object(
                    properties: [
                        "account": .string(description: "Optional account name to filter by (e.g., 'SHAFFER' for work emails)")
                    ],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Get Unread Emails", readOnlyHint: true, openWorldHint: false)
            ) { input in
                let accountFilter = input["account"]?.stringValue
                let unreadEmails = try await self.getUnreadEmails(accountFilter: accountFilter)
                if unreadEmails.isEmpty {
                    return accountFilter != nil ? "No unread emails in \(accountFilter!) account." : "No unread emails."
                } else {
                    let accountText = accountFilter != nil ? " in \(accountFilter!) account" : ""
                    return "Found \(unreadEmails.count) unread emails\(accountText):\n" + 
                           unreadEmails.map { "• ID: \($0.id) - \($0.subject) - from \($0.sender)" }.joined(separator: "\n")
                }
            }
            
            Tool(
                name: "mail_reply",
                description: "Reply to a specific email by message ID with custom body text",
                inputSchema: .object(
                    properties: [
                        "messageId": .string(description: "Message ID from unread emails or search results"),
                        "account": .string(description: "Account name (e.g., 'iCloud', 'Google', 'SHAFFER')"),
                        "body": .string(description: "Reply message body text")
                    ],
                    required: ["messageId", "account", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Reply to Email", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let messageId = input["messageId"]?.stringValue ?? ""
                let account = input["account"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                try await self.replyToMessage(messageId: messageId, account: account, body: body)
                return "Reply sent successfully to message ID \(messageId)"
            }
            
            Tool(
                name: "mail_reply_all",
                description: "Reply to all recipients of a specific email by message ID with custom body text",
                inputSchema: .object(
                    properties: [
                        "messageId": .string(description: "Message ID from unread emails or search results"),
                        "account": .string(description: "Account name (e.g., 'iCloud', 'Google', 'SHAFFER')"),
                        "body": .string(description: "Reply message body text")
                    ],
                    required: ["messageId", "account", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Reply All to Email", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let messageId = input["messageId"]?.stringValue ?? ""
                let account = input["account"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                try await self.replyAllToMessage(messageId: messageId, account: account, body: body)
                return "Reply all sent successfully to message ID \(messageId)"
            }
            
            Tool(
                name: "mail_forward",
                description: "Forward a specific email by message ID with custom body text to a recipient",
                inputSchema: .object(
                    properties: [
                        "messageId": .string(description: "Message ID from unread emails or search results"),
                        "account": .string(description: "Account name (e.g., 'iCloud', 'Google', 'SHAFFER')"),
                        "to": .string(description: "Email address to forward to"),
                        "body": .string(description: "Forward message body text")
                    ],
                    required: ["messageId", "account", "to", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Forward Email", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let messageId = input["messageId"]?.stringValue ?? ""
                let account = input["account"]?.stringValue ?? ""
                let to = input["to"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                try await self.forwardMessage(messageId: messageId, account: account, to: to, body: body)
                return "Email forwarded successfully to \(to)"
            }
            
            Tool(
                name: "mail_flag",
                description: "Set or remove colored flags on a specific email by message ID",
                inputSchema: .object(
                    properties: [
                        "messageId": .string(description: "Message ID from unread emails or search results"),
                        "account": .string(description: "Account name (e.g., 'iCloud', 'Google', 'SHAFFER')"),
                        "flag": .string(description: "Flag color: 'none', 'orange', 'red', 'yellow', 'blue', 'green', 'purple'")
                    ],
                    required: ["messageId", "account", "flag"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Flag Email", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let messageId = input["messageId"]?.stringValue ?? ""
                let account = input["account"]?.stringValue ?? ""
                let flag = input["flag"]?.stringValue ?? ""
                try await self.flagMessage(messageId: messageId, account: account, flag: flag)
                return "Flag '\(flag)' set on message ID \(messageId)"
            }
            
            Tool(
                name: "mail_list_mailboxes",
                description: "List all available mailboxes/folders/labels in a mail account",
                inputSchema: .object(
                    properties: [
                        "account": .string(description: "Account name (e.g., 'iCloud', 'Google', 'SHAFFER')")
                    ],
                    required: ["account"],
                    additionalProperties: false
                ),
                annotations: .init(title: "List Mailboxes", readOnlyHint: true, openWorldHint: false)
            ) { input in
                let account = input["account"]?.stringValue ?? ""
                let mailboxes = try await self.listMailboxes(account: account)
                return "Available mailboxes in \(account) account:\n" + mailboxes.joined(separator: "\n")
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
                description: "Read the content of an email by message ID or the currently selected email",
                inputSchema: .object(
                    properties: [
                        "messageId": .string(description: "Optional message ID to read specific email"),
                        "account": .string(description: "Optional account name if messageId is provided")
                    ],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Read Email", readOnlyHint: true, openWorldHint: false)
            ) { input in
                let messageId = input["messageId"]?.stringValue
                let account = input["account"]?.stringValue
                
                let content: EmailContent
                if let msgId = messageId, let acc = account {
                    content = try await self.readEmailById(messageId: msgId, account: acc)
                } else {
                    content = try await self.readSelectedEmail()
                }
                
                return "Subject: \(content.subject)\nFrom: \(content.sender)\nDate: \(content.dateSent)\n\n\(content.content)"
            }
            
            Tool(
                name: "mail_draft",
                description: "Create a new email draft in Mail app",
                inputSchema: .object(
                    properties: [
                        "to": .string(description: "Recipient email address"),
                        "subject": .string(description: "Email subject line"),
                        "body": .string(description: "Email message body"),
                        "from_account": .string(description: "Email account to send from (optional)")
                    ],
                    required: ["to", "subject", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Create Email Draft", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let to = input["to"]?.stringValue ?? ""
                let subject = input["subject"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                let fromAccount = input["from_account"]?.stringValue
                try await self.createDraft(to: to, subject: subject, body: body, fromAccount: fromAccount)
                return "Email draft created successfully"
            }
            
            Tool(
                name: "mail_send",
                description: "Create and send an email directly through Mail app",
                inputSchema: .object(
                    properties: [
                        "to": .string(description: "Recipient email address"),
                        "subject": .string(description: "Email subject line"),
                        "body": .string(description: "Email message body"),
                        "from_account": .string(description: "Email account to send from (optional)")
                    ],
                    required: ["to", "subject", "body"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Send Email", readOnlyHint: false, openWorldHint: false)
            ) { input in
                let to = input["to"]?.stringValue ?? ""
                let subject = input["subject"]?.stringValue ?? ""
                let body = input["body"]?.stringValue ?? ""
                let fromAccount = input["from_account"]?.stringValue
                try await self.sendEmail(to: to, subject: subject, body: body, fromAccount: fromAccount)
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
            
            let resumedBox = Box(false)
            
            // Set a reasonable timeout using Task
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if !resumedBox.value && task.isRunning {
                    resumedBox.value = true
                    task.terminate()
                    continuation.resume(throwing: MailError.appleScriptError("AppleScript execution timed out"))
                }
            }
            
            task.terminationHandler = { _ in
                timeoutTask.cancel()
                if !resumedBox.value {
                    resumedBox.value = true
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if task.terminationStatus == 0 {
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        let errorMessage = output.isEmpty ? "AppleScript execution failed" : output
                        continuation.resume(throwing: MailError.appleScriptError(errorMessage))
                    }
                }
            }
            
            do {
                try task.run()
            } catch {
                if !resumedBox.value {
                    resumedBox.value = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Account Management
    
    func listAccounts() async throws -> [MailAccount] {
        log.info("Listing mail accounts")
        let script = """
        tell application "Mail"
            set accountList to {}
            repeat with eachAccount in accounts
                set accountInfo to {name of eachAccount, email addresses of eachAccount}
                set end of accountList to accountInfo
            end repeat
            return accountList
        end tell
        """
        
        let output = try await executeAppleScript(script)
        return parseAccountResults(output)
    }
    
    private func parseAccountResults(_ output: String) -> [MailAccount] {
        // Parse AppleScript comma-separated output
        print("🔍 Raw AppleScript output: '\(output)'")
        
        var accounts: [MailAccount] = []
        let components = output.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // AppleScript returns: accountName1, email1, accountName2, email2, etc.
        for i in stride(from: 0, to: components.count, by: 2) {
            if i + 1 < components.count {
                let name = String(components[i])
                let email = String(components[i + 1])
                accounts.append(MailAccount(name: name, email: email))
                print("📧 Found mail account: \(name) (\(email))")
            }
        }
        
        return accounts
    }
    
    // MARK: - Mail Actions
    
    func reply() async throws {
        log.info("Executing reply command")
        
        let script = """
        tell application "Mail"
            activate
            set selectedMessages to selection
            if (count of selectedMessages) = 0 then
                error "No email selected. Please select an email first."
            end if
            delay 0.5
        end tell
        tell application "System Events" to keystroke "r" using command down
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func replyToMessage(messageId: String, account: String, body: String) async throws {
        log.info("Replying to message \(messageId) in account \(account)")
        
        let script = """
        tell application "Mail"
            activate
            repeat with eachAccount in accounts
                if name of eachAccount contains "\(account)" then
                    repeat with eachMailbox in mailboxes of eachAccount
                        if name of eachMailbox contains "INBOX" then
                            set targetMessages to (messages of eachMailbox whose id = \(messageId))
                            if (count of targetMessages) > 0 then
                                set targetMessage to item 1 of targetMessages
                                -- Open the message
                                set viewer to open targetMessage
                                delay 2
                                -- Use keyboard shortcut to reply
                                tell application "System Events"
                                    keystroke "r" using command down
                                    delay 2
                                    keystroke "\(body)"
                                    delay 1
                                    keystroke "d" using {shift down, command down}
                                end tell
                                return "Reply sent successfully"
                            end if
                        end if
                    end repeat
                end if
            end repeat
            error "Message not found with ID: \(messageId)"
        end tell
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func replyAllToMessage(messageId: String, account: String, body: String) async throws {
        log.info("Reply all to message \(messageId) in account \(account)")
        
        let script = """
        tell application "Mail"
            activate
            repeat with eachAccount in accounts
                if name of eachAccount contains "\(account)" then
                    repeat with eachMailbox in mailboxes of eachAccount
                        if name of eachMailbox contains "INBOX" then
                            set targetMessages to (messages of eachMailbox whose id = \(messageId))
                            if (count of targetMessages) > 0 then
                                set targetMessage to item 1 of targetMessages
                                -- Open the message
                                set viewer to open targetMessage
                                delay 2
                                -- Use keyboard shortcut to reply all
                                tell application "System Events"
                                    keystroke "r" using {shift down, command down}
                                    delay 2
                                    keystroke "\(body)"
                                    delay 1
                                    keystroke "d" using {shift down, command down}
                                end tell
                                return "Reply all sent successfully"
                            end if
                        end if
                    end repeat
                end if
            end repeat
            error "Message not found with ID: \(messageId)"
        end tell
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func forwardMessage(messageId: String, account: String, to: String, body: String) async throws {
        log.info("Forward message \(messageId) in account \(account) to \(to)")
        
        let script = """
        tell application "Mail"
            activate
            repeat with eachAccount in accounts
                if name of eachAccount contains "\(account)" then
                    repeat with eachMailbox in mailboxes of eachAccount
                        if name of eachMailbox contains "INBOX" then
                            set targetMessages to (messages of eachMailbox whose id = \(messageId))
                            if (count of targetMessages) > 0 then
                                set targetMessage to item 1 of targetMessages
                                -- Open the message
                                set viewer to open targetMessage
                                delay 2
                                -- Use keyboard shortcut to forward
                                tell application "System Events"
                                    keystroke "f" using {shift down, command down}
                                    delay 2
                                    -- Tab to the To field and enter recipient
                                    keystroke tab
                                    delay 0.5
                                    keystroke "\(to)"
                                    delay 0.5
                                    -- Tab to the body field and enter message
                                    keystroke tab
                                    keystroke tab
                                    delay 0.5
                                    keystroke "\(body)"
                                    delay 1
                                    keystroke "d" using {shift down, command down}
                                end tell
                                return "Forward sent successfully"
                            end if
                        end if
                    end repeat
                end if
            end repeat
            error "Message not found with ID: \(messageId)"
        end tell
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func flagMessage(messageId: String, account: String, flag: String) async throws {
        log.info("Flagging message \(messageId) in account \(account) with \(flag)")
        
        // Convert flag name to index
        let flagIndex: Int
        switch flag.lowercased() {
        case "none": flagIndex = 0
        case "orange": flagIndex = 1
        case "red": flagIndex = 2
        case "yellow": flagIndex = 3
        case "blue": flagIndex = 4
        case "green": flagIndex = 5
        case "purple": flagIndex = 6
        default: flagIndex = 0
        }
        
        let script = """
        tell application "Mail"
            repeat with eachAccount in accounts
                if name of eachAccount contains "\(account)" then
                    repeat with eachMailbox in mailboxes of eachAccount
                        if name of eachMailbox contains "INBOX" then
                            set targetMessages to (messages of eachMailbox whose id = \(messageId))
                            if (count of targetMessages) > 0 then
                                set targetMessage to item 1 of targetMessages
                                set flag index of targetMessage to \(flagIndex)
                                return "Flag set successfully"
                            end if
                        end if
                    end repeat
                end if
            end repeat
            error "Message not found with ID: \(messageId)"
        end tell
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func listMailboxes(account: String) async throws -> [String] {
        log.info("Listing mailboxes for account \(account)")
        
        let script = """
        tell application "Mail"
            set mailboxNames to {}
            repeat with eachAccount in accounts
                if name of eachAccount contains "\(account)" then
                    repeat with eachMailbox in mailboxes of eachAccount
                        set end of mailboxNames to name of eachMailbox
                    end repeat
                end if
            end repeat
            return mailboxNames
        end tell
        """
        
        let output = try await executeAppleScript(script)
        let mailboxes = output.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return mailboxes.map { String($0) }
    }
    
    
    func replyAll() async throws {
        log.info("Executing reply all command")
        
        let script = """
        tell application "Mail"
            activate
            set selectedMessages to selection
            if (count of selectedMessages) = 0 then
                error "No email selected. Please select an email first."
            end if
            delay 0.5
        end tell
        tell application "System Events" to keystroke "r" using {shift down, command down}
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func forward() async throws {
        log.info("Executing forward command")
        
        let script = """
        tell application "Mail"
            activate
            set selectedMessages to selection
            if (count of selectedMessages) = 0 then
                error "No email selected. Please select an email first."
            end if
            delay 0.5
        end tell
        tell application "System Events" to keystroke "f" using {shift down, command down}
        """
        
        _ = try await executeAppleScript(script)
    }
    
    func redirect() async throws {
        log.info("Executing redirect command")
        
        let script = """
        tell application "Mail"
            activate
            set selectedMessages to selection
            if (count of selectedMessages) = 0 then
                error "No email selected. Please select an email first."
            end if
            delay 0.5
        end tell
        tell application "System Events" to keystroke "e" using {shift down, command down}
        """
        
        _ = try await executeAppleScript(script)
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
            set resultList to {}
            repeat with eachAccount in accounts
                repeat with eachMailbox in mailboxes of eachAccount
                    if name of eachMailbox contains "INBOX" then
                        set searchResults to (messages of eachMailbox whose subject contains "\(query)" or content contains "\(query)")
                        repeat with eachMessage in searchResults
                            set messageInfo to {id of eachMessage, subject of eachMessage, sender of eachMessage, date sent of eachMessage}
                            set end of resultList to messageInfo
                        end repeat
                    end if
                end repeat
            end repeat
            return resultList
        end tell
        """
        
        let output = try await executeAppleScript(script)
        return parseEmailResults(output)
    }
    
    private func parseEmailResults(_ output: String) -> [EmailResult] {
        print("🔍 Raw search results: '\(output)'")
        
        var results: [EmailResult] = []
        let components = output.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // AppleScript returns: id1, subject1, sender1, date1, id2, subject2, sender2, date2, etc.
        for i in stride(from: 0, to: components.count, by: 4) {
            if i + 3 < components.count {
                let id = String(components[i])
                let subject = String(components[i + 1])
                let sender = String(components[i + 2])
                let _ = String(components[i + 3]) // dateString - not currently used
                
                // Simple date parsing - could be enhanced
                let dateSent = Date() // For now, use current date
                
                results.append(EmailResult(id: id, subject: subject, sender: sender, dateSent: dateSent))
                print("📧 Found email: '\(subject)' from \(sender) (ID: \(id))")
            }
        }
        
        return results
    }
    
    // MARK: - Unread Emails
    
    func getUnreadEmails(accountFilter: String? = nil) async throws -> [EmailResult] {
        log.info("Getting unread emails with account filter: \(accountFilter ?? "none")")
        
        let script: String
        if let account = accountFilter {
            script = """
            tell application "Mail"
                set resultList to {}
                repeat with eachAccount in accounts
                    if name of eachAccount contains "\(account)" then
                        repeat with eachMailbox in mailboxes of eachAccount
                            if name of eachMailbox contains "INBOX" then
                                set unreadMessages to (messages of eachMailbox whose read status is false)
                                repeat with eachMessage in unreadMessages
                                    set messageInfo to {id of eachMessage, subject of eachMessage, sender of eachMessage, date sent of eachMessage}
                                    set end of resultList to messageInfo
                                end repeat
                            end if
                        end repeat
                    end if
                end repeat
                return resultList
            end tell
            """
        } else {
            script = """
            tell application "Mail"
                set resultList to {}
                repeat with eachAccount in accounts
                    repeat with eachMailbox in mailboxes of eachAccount
                        if name of eachMailbox contains "INBOX" then
                            set unreadMessages to (messages of eachMailbox whose read status is false)
                            repeat with eachMessage in unreadMessages
                                set messageInfo to {id of eachMessage, subject of eachMessage, sender of eachMessage, date sent of eachMessage}
                                set end of resultList to messageInfo
                            end repeat
                        end if
                    end repeat
                end repeat
                return resultList
            end tell
            """
        }
        
        let output = try await executeAppleScript(script)
        return parseEmailResults(output)
    }
    
    // MARK: - Email Reading
    
    func readEmailById(messageId: String, account: String) async throws -> EmailContent {
        log.info("Reading email with ID \(messageId) from account \(account)")
        
        // First, open and select the message
        let selectScript = """
        tell application "Mail"
            activate
            repeat with eachAccount in accounts
                if name of eachAccount contains "\(account)" then
                    repeat with eachMailbox in mailboxes of eachAccount
                        set targetMessages to (messages of eachMailbox whose id = \(messageId))
                        if (count of targetMessages) > 0 then
                            set targetMessage to item 1 of targetMessages
                            -- Open the message in a viewer
                            open targetMessage
                            delay 1
                            return "Message opened"
                        end if
                    end repeat
                end if
            end repeat
            error "Message not found with ID: \(messageId)"
        end tell
        """
        
        _ = try await executeAppleScript(selectScript)
        
        // Now read the selected message
        let readScript = """
        tell application "Mail"
            set selectedMessages to selection
            if (count of selectedMessages) > 0 then
                set theMessage to item 1 of selectedMessages
                set messageSubject to subject of theMessage
                set messageContent to content of theMessage
                set messageSender to sender of theMessage
                set messageDate to date sent of theMessage
                return messageSubject & "|||" & messageContent & "|||" & messageSender & "|||" & messageDate
            else
                error "No email selected"
            end if
        end tell
        """
        
        let output = try await executeAppleScript(readScript)
        return parseEmailContentDelimited(output)
    }
    
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
    
    private func parseEmailContentDelimited(_ output: String) -> EmailContent {
        print("🔍 Raw email content: '\(output)'")
        
        let components = output.split(separator: "|||").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // AppleScript returns: subject|||content|||sender|||date
        if components.count >= 4 {
            let subject = String(components[0])
            let content = String(components[1])
            let sender = String(components[2])
            let _ = String(components[3]) // dateString - not currently used
            
            print("📧 Parsed email: '\(subject)' from \(sender)")
            
            // Simple date parsing - could be enhanced
            let dateSent = Date() // For now, use current date
            
            return EmailContent(subject: subject, content: content, sender: sender, dateSent: dateSent)
        } else {
            print("❌ Failed to parse email content - insufficient components")
            return EmailContent(subject: "Unknown", content: "Failed to parse", sender: "Unknown", dateSent: Date())
        }
    }
    
    private func parseEmailContent(_ output: String) -> EmailContent {
        print("🔍 Raw email content: '\(output)'")
        
        let components = output.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // AppleScript returns: subject, content, sender, date
        if components.count >= 4 {
            let subject = String(components[0])
            let content = String(components[1])
            let sender = String(components[2])
            let _ = String(components[3]) // dateString - not currently used
            
            print("📧 Parsed email: '\(subject)' from \(sender)")
            
            // Simple date parsing - could be enhanced
            let dateSent = Date() // For now, use current date
            
            return EmailContent(subject: subject, content: content, sender: sender, dateSent: dateSent)
        } else {
            print("❌ Failed to parse email content - insufficient components")
            return EmailContent(subject: "Unknown", content: "Failed to parse", sender: "Unknown", dateSent: Date())
        }
    }
    
    // MARK: - Email Drafting & Sending
    
    func createDraft(to: String, subject: String, body: String, fromAccount: String? = nil) async throws {
        log.info("Creating email draft from \(fromAccount ?? "default") to \(to)")
        
        let fromAccountClause: String
        if let account = fromAccount {
            fromAccountClause = """
                set sender to "\(account)"
            """
        } else {
            fromAccountClause = ""
        }
        
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)"}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:"\(to)"}
                \(fromAccountClause)
            end tell
            activate
        end tell
        """
        _ = try await executeAppleScript(script)
    }
    
    func sendEmail(to: String, subject: String, body: String, fromAccount: String? = nil) async throws {
        log.info("Sending email from \(fromAccount ?? "default") to \(to)")
        
        let fromAccountClause: String
        if let account = fromAccount {
            fromAccountClause = """
            set sender to "\(account)"
            """
        } else {
            fromAccountClause = ""
        }
        
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)"}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:"\(to)"}
                \(fromAccountClause)
                send
            end tell
        end tell
        """
        _ = try await executeAppleScript(script)
    }
}

// MARK: - Data Models

struct MailAccount {
    let name: String
    let email: String
}

struct EmailResult {
    let id: String
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
    case activationFailed(String)
}
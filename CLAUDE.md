# AIVA Mail Integration Features

## Core Mail Service Features
- **Mail.swift service**: AppleScript-based integration with macOS Mail app
- **Keyboard shortcuts integration**: Use system keyboard commands for mail actions
- **Email search**: Find emails by sender, subject, content, date range
- **Email reading**: Retrieve and display email content
- **Email drafting**: Create new email drafts
- **Email sending**: Send emails through Mail app
- **Mail actions**: Reply, Reply All, Forward, Redirect functionality

## AppleScript Integration Rules
- Use `osascript` command to execute AppleScript from Swift
- Leverage Mail app's AppleScript dictionary for proper commands
- Handle Mail app activation and focus management

## Keyboard Shortcuts to Implement
- **⌘R**: Reply to selected email
- **⇧⌘R**: Reply All to selected email  
- **⇧⌘F**: Forward selected email
- **⇧⌘E**: Redirect selected email
- **⌘N**: New email (draft)

## AppleScript Commands Needed
```applescript
-- Activate Mail app
tell application "Mail" to activate

-- Reply shortcuts
tell application "System Events" to keystroke "r" using command down

-- Reply All shortcuts  
tell application "System Events" to keystroke "r" using {shift down, command down}

-- Forward shortcuts
tell application "System Events" to keystroke "f" using {shift down, command down}

-- Redirect shortcuts
tell application "System Events" to keystroke "e" using {shift down, command down}

-- Search emails
tell application "Mail" to search every message for "search term"

-- Read email content
tell application "Mail" to get content of selected message

-- Create new draft
tell application "Mail" to make new outgoing message
```

## Service Architecture
- Follow existing AIVA service patterns (see Speech.swift, Messages.swift)
- Implement Service protocol with isActivated and activate() methods
- Use Logger.service("mail") for consistent logging
- Handle async operations properly
- Error handling for Mail app not running or accessible

## Tools to Expose
1. `mail_search` - Search emails by criteria
2. `mail_read` - Read selected/specified email
3. `mail_reply` - Reply to email (with keyboard shortcut)
4. `mail_reply_all` - Reply all to email  
5. `mail_forward` - Forward email
6. `mail_redirect` - Redirect email
7. `mail_draft` - Create new email draft
8. `mail_send` - Send composed email

## Testing Rules
**IMPORTANT**: When testing mail functionality, ONLY use these accounts:
- **Gmail account**: MikeJShaffer@gmail.com (Google)
- **iCloud account**: mikejshaffer@icloud.com (iCloud)

**DO NOT test with the SHAFFER work account** (mike@shaffercon.com) to avoid sending test emails to work contacts.

## Implementation Priority
1. Basic Mail service setup with AppleScript execution
2. Keyboard shortcut integration for reply/forward actions
3. Email search functionality
4. Email reading capabilities
5. Draft and send functionality
6. Full testing with Mail app integration
- Do not try to restart or build the server. just speak to tell mike to do it for you when youre done with a change and ready to test it.
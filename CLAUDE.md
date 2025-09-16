# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# AIVA Development Guide

Essential context and guidance for working with the AIVA macOS application codebase.

## Project Overview

AIVA is a macOS app that connects your digital life with AI through the Model Context Protocol (MCP). It provides access to Calendar, Contacts, Messages, Mail, Weather, and other macOS services through MCP tools that can be used by Claude Desktop and other MCP clients.

### Key Architecture Components

- **App/**: SwiftUI macOS application with system permissions UI and MCP request processing
- **CLI/**: Command-line MCP server (`aiva-server`) using stdio transport as proxy  
- **Bundled Node.js Runtime**: Self-contained at `Contents/Resources/darwin-arm64/` for subprocess servers
- **Communication**: App and CLI communicate via Bonjour discovery on local network using `_mcp._tcp` service

**Critical Insight**: This is NOT a typical single-process MCP server. The CLI is a thin proxy that forwards stdio requests to the main app over the network. This design allows the app to maintain system permissions while providing standard MCP stdio interface to clients.

## Recent Major Settings Interface Changes

The settings interface has been significantly modernized and reorganized:

### Settings Navigation Order
1. **Agents** - Agent integrations and client management (combines old "Agent Integrations" menu + "Clients" view)
2. **Servers** - External MCP servers (SSE) and subprocess servers  
3. **Tools** - All available tools with grid layout and filtering
4. **Memory** - Neo4j knowledge graph integration
5. **Logs** - System logs and debugging

### Key Files Modified Recently

#### `/App/Views/Settings/AgentsView.swift` (New)
- Combines agent toggle controls with connected client management
- Maps known client IDs to friendly names:
  ```swift
  private var mappedClients: [String: String] = [
      "claude-ai": "Claude Desktop",
      "claude-code": "Claude Code CLI", 
      "codex-mcp-client": "Codex CLI",
      "gemini-cli-mcp-client-aiva": "Gemini CLI"
  ]
  ```
- Shows real-time connection status on agent toggles
- Includes confirmation dialogs for connecting/disconnecting
- Auto-unlinks clients when disconnecting agents

#### `/App/Views/Settings/ServersView.swift` (Heavily Modified)
- Modernized UI with dropdown form for adding servers
- Auto-displays tool count for both SSE and subprocess servers
- Supports both remote (SSE) and local subprocess MCP servers
- No icon picker (was removed due to compilation complexity)

#### `/App/Views/Settings/ToolsView.swift` (Complete Rewrite)
- Grid layout with fixed 120x120 square cards
- Search functionality across tool names and descriptions
- Sort functionality to group disabled tools at end
- Cleans snake_case tool names from remote servers to Title Case
- Shows service attribution with colored icons

#### `/App/Views/Settings/MemoryView.swift` (Simplified)
- Auto-displays Neo4j connection status and tool count
- Removed manual "Test Connection" and "Clear" buttons
- Streamlined UI focused on configuration

#### `/App/Views/ConnectionApprovalView.swift` (Fixed)
- Dynamic window sizing based on content
- Properly scales to fit approval dialog text

## Important Development Patterns

### Service Architecture
- All services implement the `Service` protocol
- Use `Logger.service("serviceName")` for consistent logging
- Services have `isActivated` state and `activate()` method
- Follow patterns in existing services like `Speech.swift`, `Messages.swift`

### SwiftUI Conventions
- Use `@ObservedObject` for `ServerController` 
- State management with `@State`, `@Binding`, `@AppStorage`
- Consistent padding: `.padding(20)` for main views, `.padding(12)` for cards
- Color scheme: Use `Color(NSColor.controlBackgroundColor)` for cards
- Animation: `.easeInOut(duration: 0.3)` for state changes

### MCP Server Integration
- Subprocess servers use bundled Node.js runtime
- SSE servers connect over HTTP
- Tool toggles stored in UserDefaults with key pattern: `"toolEnabled.{serviceId}.{toolName}"`
- Notification: `.aivaToolTogglesChanged` when tools change

## Build and Development Commands

### Building the Project
This is an Xcode project with dual targets:
- **AIVA.app**: Main macOS application (SwiftUI)  
- **aiva-server**: Command-line MCP server (Swift CLI)

```bash
# Build the full project (both app and CLI)
xcodebuild -project AIVA.xcodeproj -scheme AIVA -configuration Debug

# Build just the CLI server
xcodebuild -project AIVA.xcodeproj -target aiva-server -configuration Debug

# Run the CLI server directly (for testing)
./.build/debug/aiva-server
```

### Architecture: Dual-Process Design
The project uses a unique dual-process architecture:

1. **AIVA.app** (App target):
   - SwiftUI macOS app with menu bar interface
   - Handles system permissions (Calendar, Contacts, Messages, etc.)
   - Advertises Bonjour service `_mcp._tcp` on local network
   - Processes MCP requests and returns responses

2. **aiva-server** (CLI target):  
   - Lightweight Swift CLI that communicates via stdin/stdout
   - Discovers AIVA.app via Bonjour and proxies requests
   - Acts as stdio transport bridge for MCP clients
   - Located in `/CLI/main.swift` (single file implementation)

**Request Flow**: `MCP Client` → `aiva-server` (stdio) → `AIVA.app` (network) → `macOS APIs` → `Response`

### Testing and Development
- **Do NOT restart server during development** - Mike handles this manually
- Focus on code changes, then inform Mike when ready to test
- Use speech tool to update Mike on progress

### Common Compilation Issues to Avoid

1. **iOS-only modifiers on macOS**: 
   - Don't use `.navigationBarTitleDisplayMode` 
   - Avoid iOS-specific UI elements

2. **Complex expression timeouts**:
   - Break large arrays into smaller chunks
   - Use static arrays instead of computed properties for large data

3. **SwiftUI animation conflicts**:
   - Use `.id(UUID())` to force view refresh when needed
   - Consistent animation durations across related views

---

# AIVA Mail Integration Features ✅ COMPLETED

## Core Mail Service Features (ALL IMPLEMENTED)
- **✅ Mail.swift service**: Complete AppleScript-based integration with macOS Mail app
- **✅ Keyboard shortcuts integration**: System keyboard commands for mail actions
- **✅ Email search**: Find emails by sender, subject, content, date range
- **✅ Email reading**: Retrieve and display email content by ID or selection
- **✅ Email drafting**: Create new email drafts with custom content
- **✅ Email sending**: Send emails directly through Mail app
- **✅ Mail actions**: Reply, Reply All, Forward, Redirect functionality
- **✅ Account management**: List accounts, filter by account name
- **✅ Mailbox management**: List mailboxes/folders for accounts
- **✅ Email flagging**: Set colored flags on messages
- **✅ Unread email retrieval**: Get unread emails with account filtering

## Implemented MCP Tools (12 Total)
1. **✅ `mail_list_accounts`** - List all configured mail accounts
2. **✅ `mail_get_unread`** - Get unread emails with account filtering
3. **✅ `mail_reply`** - Reply to email by message ID with custom body
4. **✅ `mail_reply_all`** - Reply all to email by message ID
5. **✅ `mail_forward`** - Forward email by message ID to recipient
6. **✅ `mail_flag`** - Set colored flags on messages
7. **✅ `mail_list_mailboxes`** - List mailboxes/folders in account
8. **✅ `mail_redirect`** - Redirect selected email (keyboard shortcut)
9. **✅ `mail_search`** - Search emails by query string
10. **✅ `mail_read`** - Read email content by ID or current selection
11. **✅ `mail_draft`** - Create new email draft
12. **✅ `mail_send`** - Send email directly

## Testing Rules ⚠️ IMPORTANT
**ONLY use these accounts for testing:**
- **Gmail account**: MikeJShaffer@gmail.com (Google)
- **iCloud account**: mikejshaffer@icloud.com (iCloud)

**DO NOT test with the SHAFFER work account** (mike@shaffercon.com) to avoid sending test emails to work contacts.

## Technical Implementation Details
- **Service Protocol**: Fully implements AIVA Service protocol with activation
- **AppleScript Integration**: Robust error handling and timeout management
- **Async/Await**: Proper async operation handling throughout
- **Logging**: Comprehensive logging with Logger.service("mail")
- **Permission Handling**: Triggers macOS Mail automation permissions when needed
- **Account Support**: Multi-account filtering and management
- **Error Recovery**: Graceful error handling with descriptive messages

The Mail service is **production-ready** and provides comprehensive email management capabilities through MCP tools.

---

## Dependencies and Frameworks

### Key Swift Packages
- [Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk) - Official MCP implementation
- [Madrid](https://github.com/mattt/Madrid) - iMessage database reading
- [Ontology](https://github.com/mattt/Ontology) - JSON-LD structured data

### System Integrations
- **AppleScript**: Used for Mail.app integration via `osascript`
- **App Sandbox**: Manages permissions for Calendar, Contacts, Messages
- **Bonjour**: Local network discovery for app-CLI communication
- **SQLite**: Direct access to Messages database at `~/Library/Messages/chat.db`

## File Structure Patterns

```
App/
├── Controllers/ServerController.swift    # Main MCP server coordination
├── Services/                            # Individual service implementations
│   ├── Calendar.swift
│   ├── Mail.swift                       # Mail integration (newer)
│   └── ...
├── Views/
│   ├── ContentView.swift               # Main app menu bar interface
│   └── Settings/                       # Settings window views
│       ├── AgentsView.swift            # Agent configuration
│       ├── ServersView.swift           # External MCP servers
│       ├── ToolsView.swift             # Tool management
│       └── ...
└── Integrations/                       # External client configurations
    └── ClaudeDesktop.swift             # Claude Desktop config management
```

## JSON-LD and Schema.org

AIVA returns structured data using JSON-LD with Schema.org vocabularies:
```json
{
  "@context": "https://schema.org",
  "@type": "Person", 
  "name": "Mattt",
  "url": "https://mat.tt"
}
```

This provides standardized data format for AI and conventional software.

## Debugging Tools

### MCP Inspector
```bash
npx @modelcontextprotocol/inspector [aiva-server-command]
open http://127.0.0.1:6274
```

### Companion App
macOS utility for testing MCP servers with visual interface.

## Privacy and Security

- **App Sandbox**: Limits data access, uses file picker for Messages database
- **No Data Collection**: AIVA doesn't store or transmit user data
- **Local Processing**: All operations happen locally except MCP client interactions
- **Permission Model**: Standard macOS privacy controls for each service

## Contributing Guidelines

1. **Follow Existing Patterns**: Study similar services before implementing new ones
2. **Consistent Logging**: Use `Logger.service()` throughout
3. **Error Handling**: Graceful degradation when services unavailable  
4. **Memory Management**: Proper cleanup of resources and observers
5. **Testing**: Test with multiple MCP clients when possible

This codebase represents a sophisticated macOS application bridging system services with AI through standardized protocols. The recent settings modernization has created a more intuitive and maintainable interface while preserving all functionality.
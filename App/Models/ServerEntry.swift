import Foundation

enum ServerType: String, Codable, CaseIterable {
    case sse = "SSE"
    case subprocess = "Subprocess"
}

struct ServerEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var type: ServerType
    // SSE fields
    var url: String?
    var headerKey: String?
    var headerValue: String?
    // Subprocess fields
    var command: String?
    var arguments: [String]?
    var environment: [String: String]?
    var workingDirectory: String?

    init(id: UUID = UUID(), name: String, url: String, headerKey: String? = nil, headerValue: String? = nil) {
        self.id = id
        self.name = name
        self.type = .sse
        self.url = url
        self.headerKey = headerKey
        self.headerValue = headerValue
    }
    
    init(id: UUID = UUID(), name: String, command: String, arguments: [String] = [], environment: [String: String] = [:], workingDirectory: String? = nil) {
        self.id = id
        self.name = name
        self.type = .subprocess
        self.command = command
        self.arguments = arguments
        self.environment = environment.isEmpty ? nil : environment
        self.workingDirectory = workingDirectory
    }
}

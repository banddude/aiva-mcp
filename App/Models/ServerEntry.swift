import Foundation

struct ServerEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var headerKey: String?
    var headerValue: String?

    init(id: UUID = UUID(), name: String, url: String, headerKey: String? = nil, headerValue: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.headerKey = headerKey
        self.headerValue = headerValue
    }
}

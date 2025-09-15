@preconcurrency
protocol Service {
    @ToolBuilder var tools: [Tool] { get }

    @MainActor var isActivated: Bool { get async }
    @MainActor func activate() async throws
}

extension Service {
    @MainActor
    var isActivated: Bool {
        get async {
            return true
        }
    }

    @MainActor
    func activate() async throws {}

    @MainActor
    func call(tool name: String, with arguments: [String: Value]) async throws -> Value? {
        for tool in tools where tool.name == name {
            return try await tool.callAsFunction(arguments)
        }

        return nil
    }
}

@resultBuilder
struct ToolBuilder {
    // The component type is [Tool]; individual Tool expressions get wrapped
    static func buildBlock(_ components: [Tool]...) -> [Tool] {
        components.flatMap { $0 }
    }

    static func buildExpression(_ expression: Tool) -> [Tool] { [expression] }
    static func buildExpression(_ expression: [Tool]) -> [Tool] { expression }

    static func buildOptional(_ component: [Tool]?) -> [Tool] { component ?? [] }
    static func buildEither(first component: [Tool]) -> [Tool] { component }
    static func buildEither(second component: [Tool]) -> [Tool] { component }
    static func buildArray(_ components: [[Tool]]) -> [Tool] { components.flatMap { $0 } }
}

import Foundation
import JSONSchema
import MCP
import OSLog

private let log = Logger.service("memory")

// MARK: - Data Models (Exact copies from Neo4j MCP)

struct Entity: Codable, Sendable {
    let name: String
    let type: String
    let observations: [String]
}

struct Relation: Codable, Sendable {
    let source: String
    let target: String
    let relationType: String
}

struct KnowledgeGraph: Codable, Sendable {
    let entities: [Entity]
    let relations: [Relation]
}

struct ObservationAddition: Codable, Sendable {
    let entityName: String
    let observations: [String]
}

struct ObservationDeletion: Codable, Sendable {
    let entityName: String
    let observations: [String]
}

struct ObservationResult: Codable, Sendable {
    let entityName: String
    let addedObservations: [String]
}

// MARK: - Neo4j HTTP API Structures

struct Neo4jQuery: Codable {
    let statement: String
    let parameters: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case statement, parameters
    }
    
    init(statement: String, parameters: [String: Any]) {
        self.statement = statement
        self.parameters = parameters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statement = try container.decode(String.self, forKey: .statement)
        let parametersDict = try container.decode([String: AnyCodable].self, forKey: .parameters)
        parameters = parametersDict.mapValues { $0.value }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statement, forKey: .statement)
        try container.encode(parameters.mapValues(AnyCodable.init), forKey: .parameters)
    }
}

struct Neo4jRequest: Codable {
    let statements: [Neo4jQuery]
}

struct Neo4jResponse: Codable {
    let results: [Neo4jResult]
    let errors: [Neo4jError]
}

struct Neo4jResult: Codable {
    let columns: [String]
    let data: [Neo4jDataRow]
}

struct Neo4jDataRow: Codable {
    let row: [Any]
    let meta: [Any]?
    
    // Custom initializer for creating from direct values
    init(row: [Any], meta: [Any]? = nil) {
        self.row = row
        self.meta = meta
    }
    
    enum CodingKeys: String, CodingKey {
        case row, meta
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode as JSON values and convert to Any
        let rowData = try container.decode([AnyCodable].self, forKey: .row)
        self.row = rowData.map { $0.value }
        
        let metaData = try container.decodeIfPresent([AnyCodable].self, forKey: .meta)
        self.meta = metaData?.map { $0.value }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row.map(AnyCodable.init), forKey: .row)
        if let meta = meta {
            try container.encode(meta.map(AnyCodable.init), forKey: .meta)
        }
    }
}

struct Neo4jError: Codable {
    let code: String
    let message: String
}

// MARK: - Neo4j Query v2 API Models
struct Neo4jQueryV2Request: Codable {
    let statement: String
    let parameters: [String: AnyCodable]?
    
    init(statement: String, parameters: [String: Any] = [:]) {
        self.statement = statement
        self.parameters = parameters.isEmpty ? nil : parameters.mapValues(AnyCodable.init)
    }
}

struct Neo4jQueryV2Response: Codable {
    let data: Neo4jQueryV2Data
    let bookmarks: [String]?
}

struct Neo4jQueryV2Data: Codable {
    let fields: [String]
    let values: [[AnyCodable]]
}

// Helper for encoding/decoding Any
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Neo4j Memory Implementation (EXACT COPY)

@MainActor
class Neo4jMemory {
    private let neo4jUrl: String
    private let username: String
    private let password: String
    private let database: String
    let isConfigured: Bool
    
    init() {
        // Get settings from UserDefaults
        self.neo4jUrl = UserDefaults.standard.string(forKey: "memoryNeo4jUrl") ?? ""
        self.username = UserDefaults.standard.string(forKey: "memoryNeo4jUsername") ?? ""
        self.password = UserDefaults.standard.string(forKey: "memoryNeo4jPassword") ?? ""
        self.database = UserDefaults.standard.string(forKey: "memoryNeo4jDatabase") ?? "neo4j"
        
        // Check if configured
        self.isConfigured = !neo4jUrl.isEmpty && !username.isEmpty && !password.isEmpty
        
        if !isConfigured {
            log.warning("Neo4j Memory service not configured - Memory tools will not be available")
        }
    }
    
    // EXACT COPY of Python driver.execute_query() using HTTP API
    private func executeQuery(_ query: String, parameters: [String: Any] = [:]) async throws -> Neo4jResult {
        // Convert neo4j+s://host to https://host for AuraDB query v2 API
        let httpUrl = neo4jUrl
            .replacingOccurrences(of: "neo4j+s://", with: "https://")
            .replacingOccurrences(of: "neo4j://", with: "http://")
        let url = URL(string: "\(httpUrl)/db/\(database)/query/v2")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Basic auth like Python driver
        let credentials = "\(username):\(password)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        
        let neo4jRequest = Neo4jQueryV2Request(statement: query, parameters: parameters)
        request.httpBody = try JSONEncoder().encode(neo4jRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid response from Neo4j")
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MCPError.internalError("Neo4j HTTP error \(httpResponse.statusCode): \(errorMessage)")
        }
        
        let neo4jResponse = try JSONDecoder().decode(Neo4jQueryV2Response.self, from: data)
        
        // Convert v2 response to the format expected by existing code
        let columns = neo4jResponse.data.fields
        let dataRows = neo4jResponse.data.values.map { row in
            Neo4jDataRow(row: row.map { $0.value })
        }
        
        return Neo4jResult(columns: columns, data: dataRows)
    }
    
    // EXACT COPY from neo4j_memory.py
    func createFulltextIndex() async throws {
        log.info("Creating fulltext search index")
        let query = "CREATE FULLTEXT INDEX search IF NOT EXISTS FOR (m:Memory) ON EACH [m.name, m.type, m.observations];"
        do {
            _ = try await executeQuery(query)
            log.info("Created fulltext search index")
        } catch {
            log.debug("Fulltext index creation: \(error)")
        }
    }
    
    // EXACT COPY from neo4j_memory.py load_graph()
    private func loadGraph(_ filterQuery: String = "*") async throws -> KnowledgeGraph {
        log.info("Loading knowledge graph from Neo4j")
        let query = """
            CALL db.index.fulltext.queryNodes('search', $filter) yield node as entity, score
            OPTIONAL MATCH (entity)-[r]-(other)
            RETURN collect(distinct {
                name: entity.name, 
                type: entity.type, 
                observations: entity.observations
            }) as nodes,
            collect(distinct {
                source: startNode(r).name, 
                target: endNode(r).name, 
                relationType: type(r)
            }) as relations
        """
        
        let result = try await executeQuery(query, parameters: ["filter": filterQuery])
        
        if result.data.isEmpty {
            return KnowledgeGraph(entities: [], relations: [])
        }
        
        let record = result.data[0]
        let nodes = record.row[0] as? [[String: Any]] ?? []
        let rels = record.row[1] as? [[String: Any]] ?? []
        
        let entities = nodes.compactMap { node -> Entity? in
            guard let name = node["name"] as? String,
                  let type = node["type"] as? String else { return nil }
            let observations = node["observations"] as? [String] ?? []
            return Entity(name: name, type: type, observations: observations)
        }
        
        let relations = rels.compactMap { rel -> Relation? in
            guard let source = rel["source"] as? String,
                  let target = rel["target"] as? String,
                  let relationType = rel["relationType"] as? String else { return nil }
            return Relation(source: source, target: target, relationType: relationType)
        }
        
        return KnowledgeGraph(entities: entities, relations: relations)
    }
    
    func readGraph() async throws -> KnowledgeGraph {
        return try await loadGraph()
    }
    
    // EXACT COPY from neo4j_memory.py create_entities()
    func createEntities(_ entities: [Entity]) async throws -> [Entity] {
        log.info("Creating \(entities.count) entities in Neo4j")
        let query = """
            UNWIND $entities as entity
            MERGE (e:Memory { name: entity.name })
            SET e.type = entity.type, e.observations = entity.observations
            RETURN e.name as name, e.type as type, e.observations as observations
        """
        
        let entitiesData = entities.map { ["name": $0.name, "type": $0.type, "observations": $0.observations] }
        let result = try await executeQuery(query, parameters: ["entities": entitiesData])
        
        return result.data.map { row in
            let name = row.row[0] as? String ?? ""
            let type = row.row[1] as? String ?? ""
            let observations = row.row[2] as? [String] ?? []
            return Entity(name: name, type: type, observations: observations)
        }
    }
    
    // EXACT COPY from neo4j_memory.py create_relations()
    func createRelations(_ relations: [Relation]) async throws -> [Relation] {
        log.info("Creating \(relations.count) relations in Neo4j")
        
        for relation in relations {
            let query = """
                MATCH (source:Memory { name: $source })
                MATCH (target:Memory { name: $target })
                MERGE (source)-[r:\(relation.relationType)]->(target)
                RETURN type(r) as relationType
            """
            
            _ = try await executeQuery(query, parameters: [
                "source": relation.source,
                "target": relation.target
            ])
        }
        
        return relations
    }
    
    // EXACT COPY from neo4j_memory.py add_observations()
    func addObservations(_ observations: [ObservationAddition]) async throws -> [ObservationResult] {
        log.info("Adding observations to \(observations.count) entities")
        let query = """
            UNWIND $observations as obs  
            MATCH (e:Memory { name: obs.entityName })
            WITH e, [o in obs.observations WHERE NOT o IN e.observations] as new
            SET e.observations = coalesce(e.observations,[]) + new
            RETURN e.name as name, new
        """
        
        let obsData = observations.map { ["entityName": $0.entityName, "observations": $0.observations] }
        let result = try await executeQuery(query, parameters: ["observations": obsData])
        
        return result.data.map { row in
            let entityName = row.row[0] as? String ?? ""
            let addedObservations = row.row[1] as? [String] ?? []
            return ObservationResult(entityName: entityName, addedObservations: addedObservations)
        }
    }
    
    // EXACT COPY from neo4j_memory.py delete_entities()
    func deleteEntities(_ entityNames: [String]) async throws {
        log.info("Deleting \(entityNames.count) entities")
        let query = """
            UNWIND $entities as name
            MATCH (e:Memory { name: name })
            DETACH DELETE e
        """
        
        _ = try await executeQuery(query, parameters: ["entities": entityNames])
        log.info("Successfully deleted \(entityNames.count) entities")
    }
    
    // EXACT COPY from neo4j_memory.py delete_observations()
    func deleteObservations(_ deletions: [ObservationDeletion]) async throws {
        for deletion in deletions {
            let query = """
                MATCH (e:Memory { name: $entityName })
                SET e.observations = [o in e.observations WHERE NOT o IN $observations]
            """
            
            _ = try await executeQuery(query, parameters: [
                "entityName": deletion.entityName,
                "observations": deletion.observations
            ])
        }
        log.info("Successfully deleted observations from \(deletions.count) entities")
    }
    
    // EXACT COPY from neo4j_memory.py delete_relations()
    func deleteRelations(_ relations: [Relation]) async throws {
        for relation in relations {
            let query = """
                MATCH (source:Memory { name: $source })-[r:\(relation.relationType)]->(target:Memory { name: $target })
                DELETE r
            """
            
            _ = try await executeQuery(query, parameters: [
                "source": relation.source,
                "target": relation.target
            ])
        }
        log.info("Successfully deleted \(relations.count) relations")
    }
    
    // EXACT COPY from neo4j_memory.py search_memories()
    func searchMemories(_ query: String) async throws -> KnowledgeGraph {
        log.info("Searching for memories with query: '\(query)'")
        return try await loadGraph(query)
    }
    
    // EXACT COPY from neo4j_memory.py find_memories_by_name()
    func findMemoriesByName(_ names: [String]) async throws -> KnowledgeGraph {
        log.info("Finding \(names.count) memories by name")
        let query = """
            MATCH (e:Memory)
            WHERE e.name IN $names
            RETURN  e.name as name, 
                    e.type as type, 
                    e.observations as observations
        """
        
        let result = try await executeQuery(query, parameters: ["names": names])
        let entities = result.data.map { row in
            Entity(
                name: row.row[0] as? String ?? "",
                type: row.row[1] as? String ?? "",
                observations: row.row[2] as? [String] ?? []
            )
        }
        
        // Get relations for found entities
        let relationQuery = """
            MATCH (source:Memory)-[r]->(target:Memory)
            WHERE source.name IN $names OR target.name IN $names
            RETURN  source.name as source, 
                    target.name as target, 
                    type(r) as relationType
        """
        
        let relationResult = try await executeQuery(relationQuery, parameters: ["names": names])
        let relations = relationResult.data.map { row in
            Relation(
                source: row.row[0] as? String ?? "",
                target: row.row[1] as? String ?? "",
                relationType: row.row[2] as? String ?? ""
            )
        }
        
        return KnowledgeGraph(entities: entities, relations: relations)
    }
}

// MARK: - Service

@MainActor
class MemoryService: Service, Sendable {
    static let shared = MemoryService()
    private let memory = Neo4jMemory()
    
    private init() {}
    
    @ToolBuilder
    nonisolated var tools: [Tool] {
        Tool(
            name: "read_graph",
            description: "Read the entire knowledge graph",
            inputSchema: .object(properties: [:]),
            annotations: .init(
                title: "Read Graph",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: readGraph
        )
        
        Tool(
            name: "create_entities",
            description: "Create multiple new entities in the knowledge graph",
            inputSchema: .object(
                properties: [
                    "entities": .array(
                        description: "List of entities to create",
                        items: .object(
                            properties: [
                                "name": .string(description: "Entity name"),
                                "type": .string(description: "Entity type"),
                                "observations": .array(
                                    description: "List of observations about this entity",
                                    items: .string()
                                )
                            ],
                            required: ["name", "type", "observations"]
                        )
                    )
                ],
                required: ["entities"]
            ),
            annotations: .init(
                title: "Create Entities",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: createEntities
        )
        
        Tool(
            name: "create_relations",
            description: "Create multiple new relations between entities",
            inputSchema: .object(
                properties: [
                    "relations": .array(
                        description: "List of relations to create",
                        items: .object(
                            properties: [
                                "source": .string(description: "Source entity name"),
                                "target": .string(description: "Target entity name"),
                                "relationType": .string(description: "Type of relationship")
                            ],
                            required: ["source", "target", "relationType"]
                        )
                    )
                ],
                required: ["relations"]
            ),
            annotations: .init(
                title: "Create Relations",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: createRelations
        )
        
        Tool(
            name: "add_observations",
            description: "Add new observations to existing entities",
            inputSchema: .object(
                properties: [
                    "observations": .array(
                        description: "List of observations to add",
                        items: .object(
                            properties: [
                                "entityName": .string(description: "Entity name to add observations to"),
                                "observations": .array(
                                    description: "List of observations to add",
                                    items: .string()
                                )
                            ],
                            required: ["entityName", "observations"]
                        )
                    )
                ],
                required: ["observations"]
            ),
            annotations: .init(
                title: "Add Observations",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: addObservations
        )
        
        Tool(
            name: "delete_entities",
            description: "Delete multiple entities and their associated relations",
            inputSchema: .object(
                properties: [
                    "entityNames": .array(
                        description: "Array of entity names to delete",
                        items: .string()
                    )
                ],
                required: ["entityNames"]
            ),
            annotations: .init(
                title: "Delete Entities",
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: deleteEntities
        )
        
        Tool(
            name: "delete_observations",
            description: "Delete specific observations from entities",
            inputSchema: .object(
                properties: [
                    "deletions": .array(
                        description: "Array of observation deletions",
                        items: .object(
                            properties: [
                                "entityName": .string(description: "Entity name to delete observations from"),
                                "observations": .array(
                                    description: "List of observations to delete",
                                    items: .string()
                                )
                            ],
                            required: ["entityName", "observations"]
                        )
                    )
                ],
                required: ["deletions"]
            ),
            annotations: .init(
                title: "Delete Observations",
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: deleteObservations
        )
        
        Tool(
            name: "delete_relations",
            description: "Delete multiple relations from the graph",
            inputSchema: .object(
                properties: [
                    "relations": .array(
                        description: "Array of relations to delete",
                        items: .object(
                            properties: [
                                "source": .string(description: "Source entity name"),
                                "target": .string(description: "Target entity name"),
                                "relationType": .string(description: "Type of relationship")
                            ],
                            required: ["source", "target", "relationType"]
                        )
                    )
                ],
                required: ["relations"]
            ),
            annotations: .init(
                title: "Delete Relations",
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: deleteRelations
        )
        
        Tool(
            name: "search_memories",
            description: "Search for memories based on a query containing search terms",
            inputSchema: .object(
                properties: [
                    "query": .string(description: "Search query for nodes")
                ],
                required: ["query"]
            ),
            annotations: .init(
                title: "Search Memories",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: searchMemories
        )
        
        Tool(
            name: "find_memories_by_name",
            description: "Find specific memories by name",
            inputSchema: .object(
                properties: [
                    "names": .array(
                        description: "Array of node names to find",
                        items: .string()
                    )
                ],
                required: ["names"]
            ),
            annotations: .init(
                title: "Find Memories by Name",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            ),
            implementation: findMemoriesByName
        )
    }
    
    // MARK: - Implementation (EXACT Neo4j MCP behavior)
    
    @MainActor
    private func readGraph(_ input: [String: Value]) async throws -> KnowledgeGraph {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        log.info("MCP tool: read_graph")
        return try await memory.readGraph()
    }
    
    @MainActor
    private func createEntities(_ input: [String: Value]) async throws -> [Entity] {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(entitiesArray) = input["entities"] else {
            throw MCPError.invalidRequest("Missing or invalid 'entities' parameter")
        }
        
        log.info("MCP tool: create_entities (\(entitiesArray.count) entities)")
        
        let entities = try entitiesArray.map { entityValue in
            guard case let .object(entityObj) = entityValue,
                  case let .string(name) = entityObj["name"],
                  case let .string(type) = entityObj["type"],
                  case let .array(observationsArray) = entityObj["observations"] else {
                throw MCPError.invalidRequest("Invalid entity structure")
            }
            
            let observations = try observationsArray.map { obsValue in
                guard case let .string(obs) = obsValue else {
                    throw MCPError.invalidRequest("Invalid observation - must be string")
                }
                return obs
            }
            
            return Entity(name: name, type: type, observations: observations)
        }
        
        return try await memory.createEntities(entities)
    }
    
    
    @MainActor
    private func createRelations(_ input: [String: Value]) async throws -> [Relation] {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(relationsArray) = input["relations"] else {
            throw MCPError.invalidRequest("Missing or invalid 'relations' parameter")
        }
        
        log.info("MCP tool: create_relations (\(relationsArray.count) relations)")
        
        let relations = try relationsArray.map { relationValue in
            guard case let .object(relationObj) = relationValue,
                  case let .string(source) = relationObj["source"],
                  case let .string(target) = relationObj["target"],
                  case let .string(relationType) = relationObj["relationType"] else {
                throw MCPError.invalidRequest("Invalid relation structure")
            }
            
            return Relation(source: source, target: target, relationType: relationType)
        }
        
        return try await memory.createRelations(relations)
    }
    
    
    @MainActor
    private func addObservations(_ input: [String: Value]) async throws -> [ObservationResult] {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(observationsArray) = input["observations"] else {
            throw MCPError.invalidRequest("Missing or invalid 'observations' parameter")
        }
        
        log.info("MCP tool: add_observations (\(observationsArray.count) additions)")
        
        let observations = try observationsArray.map { obsValue in
            guard case let .object(obsObj) = obsValue,
                  case let .string(entityName) = obsObj["entityName"],
                  case let .array(observationsArray) = obsObj["observations"] else {
                throw MCPError.invalidRequest("Invalid observation addition structure")
            }
            
            let observationsStrings = try observationsArray.map { obsStringValue in
                guard case let .string(obs) = obsStringValue else {
                    throw MCPError.invalidRequest("Invalid observation - must be string")
                }
                return obs
            }
            
            return ObservationAddition(entityName: entityName, observations: observationsStrings)
        }
        
        return try await memory.addObservations(observations)
    }
    
    
    @MainActor
    private func deleteEntities(_ input: [String: Value]) async throws -> String {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(entityNamesArray) = input["entityNames"] else {
            throw MCPError.invalidRequest("Missing or invalid 'entityNames' parameter")
        }
        
        let entityNames = try entityNamesArray.map { nameValue in
            guard case let .string(name) = nameValue else {
                throw MCPError.invalidRequest("Invalid entity name - must be string")
            }
            return name
        }
        
        log.info("MCP tool: delete_entities (\(entityNames.count) entities)")
        
        try await memory.deleteEntities(entityNames)
        return "Entities deleted successfully"
    }
    
    
    @MainActor
    private func deleteObservations(_ input: [String: Value]) async throws -> String {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(deletionsArray) = input["deletions"] else {
            throw MCPError.invalidRequest("Missing or invalid 'deletions' parameter")
        }
        
        log.info("MCP tool: delete_observations (\(deletionsArray.count) deletions)")
        
        let deletions = try deletionsArray.map { deletionValue in
            guard case let .object(deletionObj) = deletionValue,
                  case let .string(entityName) = deletionObj["entityName"],
                  case let .array(observationsArray) = deletionObj["observations"] else {
                throw MCPError.invalidRequest("Invalid observation deletion structure")
            }
            
            let observations = try observationsArray.map { obsValue in
                guard case let .string(obs) = obsValue else {
                    throw MCPError.invalidRequest("Invalid observation - must be string")
                }
                return obs
            }
            
            return ObservationDeletion(entityName: entityName, observations: observations)
        }
        
        try await memory.deleteObservations(deletions)
        return "Observations deleted successfully"
    }
    
    
    @MainActor
    private func deleteRelations(_ input: [String: Value]) async throws -> String {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(relationsArray) = input["relations"] else {
            throw MCPError.invalidRequest("Missing or invalid 'relations' parameter")
        }
        
        log.info("MCP tool: delete_relations (\(relationsArray.count) relations)")
        
        let relations = try relationsArray.map { relationValue in
            guard case let .object(relationObj) = relationValue,
                  case let .string(source) = relationObj["source"],
                  case let .string(target) = relationObj["target"],
                  case let .string(relationType) = relationObj["relationType"] else {
                throw MCPError.invalidRequest("Invalid relation structure")
            }
            
            return Relation(source: source, target: target, relationType: relationType)
        }
        
        try await memory.deleteRelations(relations)
        return "Relations deleted successfully"
    }
    
    
    @MainActor
    private func searchMemories(_ input: [String: Value]) async throws -> KnowledgeGraph {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .string(query) = input["query"] else {
            throw MCPError.invalidRequest("Missing or invalid 'query' parameter")
        }
        
        log.info("MCP tool: search_memories ('\(query)')")
        return try await memory.searchMemories(query)
    }
    
    
    @MainActor
    private func findMemoriesByName(_ input: [String: Value]) async throws -> KnowledgeGraph {
        guard memory.isConfigured else {
            throw MCPError.internalError("Neo4j Memory service is not configured. Please configure Neo4j connection in settings.")
        }
        
        guard case let .array(namesArray) = input["names"] else {
            throw MCPError.invalidRequest("Missing or invalid 'names' parameter")
        }
        
        let names = try namesArray.map { nameValue in
            guard case let .string(name) = nameValue else {
                throw MCPError.invalidRequest("Invalid name - must be string")
            }
            return name
        }
        
        log.info("MCP tool: find_memories_by_name (\(names.count) names)")
        return try await memory.findMemoriesByName(names)
    }
}

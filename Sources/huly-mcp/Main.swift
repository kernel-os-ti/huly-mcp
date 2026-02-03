//
//  Main.swift
//  huly-mcp
//

import Foundation
import Logging
import MCP

@main
struct HulyMCPServer {
    static func main() async throws {
        // Bootstrap the logging system to output to stderr
        LoggingSystem.bootstrap { label in
            let isDebug = ProcessInfo.processInfo.environment["DEBUG"] != "0"
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = isDebug ? .debug : .info
            return handler
        }
        
        let args = CommandLine.arguments
        let isDebug = ProcessInfo.processInfo.environment["DEBUG"] != "0" && !args.contains("--no-debug")
        var logger = Logger(label: "com.huly.mcp.server")
        logger.logLevel = isDebug ? .debug : .info

        logger.info("Starting Huly MCP Server", metadata: ["version": "1.0.0"])

        let server = Server(
            name: "huly-mcp",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        let hulyClient = HulyClientNew()

        logger.info("Server initialized successfully")

        // MARK: - List Tools Handler

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(
                    name: "huly_list_projects",
                    description: "List all projects in the Huly workspace",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                    ])
                ),
                Tool(
                    name: "huly_get_project",
                    description: "Get a specific project by its identifier",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Project identifier (e.g., 'HULY')"),
                            ])
                        ]),
                        "required": .array([.string("identifier")]),
                    ])
                ),
                Tool(
                    name: "huly_list_issues",
                    description: "List issues, optionally filtered by project",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "project": .object([
                                "type": .string("string"),
                                "description": .string("Optional project identifier to filter issues"),
                            ]),
                            "limit": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of issues to return (default: 50)"),
                            ]),
                        ]),
                    ])
                ),
                Tool(
                    name: "huly_get_issue",
                    description: "Get a specific issue by its identifier",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Issue identifier (e.g., 'HULY-123')"),
                            ])
                        ]),
                        "required": .array([.string("identifier")]),
                    ])
                ),
                Tool(
                    name: "huly_create_issue",
                    description: "Create a new issue in a project",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "project": .object([
                                "type": .string("string"),
                                "description": .string("Project identifier where the issue will be created"),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("Issue title"),
                            ]),
                            "description": .object([
                                "type": .string("string"),
                                "description": .string("Issue description (supports markdown)"),
                            ]),
                            "priority": .object([
                                "type": .string("integer"),
                                "description": .string("Priority level: 0=No Priority, 1=Urgent, 2=High, 3=Medium, 4=Low"),
                            ]),
                        ]),
                        "required": .array([.string("project"), .string("title")]),
                    ])
                ),
                Tool(
                    name: "huly_update_issue",
                    description: "Update an existing issue",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Issue identifier to update (e.g., 'HULY-123')"),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("New title"),
                            ]),
                            "description": .object([
                                "type": .string("string"),
                                "description": .string("New description"),
                            ]),
                            "priority": .object([
                                "type": .string("integer"),
                                "description": .string("New priority level"),
                            ]),
                            "status": .object([
                                "type": .string("string"),
                                "description": .string("New status ID"),
                            ]),
                        ]),
                        "required": .array([.string("identifier")]),
                    ])
                ),
                Tool(
                    name: "huly_list_persons",
                    description: "List all persons/contacts in the workspace",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "limit": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of persons to return (default: 50)"),
                            ])
                        ]),
                    ])
                ),
                Tool(
                    name: "huly_search",
                    description: "Search across the workspace using full-text search",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("Search query"),
                            ]),
                            "limit": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of results (default: 20)"),
                            ]),
                        ]),
                        "required": .array([.string("query")]),
                    ])
                ),
                // Test tools
                Tool(
                    name: "huly_test_upload_blob",
                    description: "Test blob upload functionality",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Content to upload"),
                            ]),
                            "filename": .object([
                                "type": .string("string"),
                                "description": .string("Filename (default: 'content')"),
                            ]),
                        ]),
                        "required": .array([.string("content")]),
                    ])
                ),
                // Document tools
                Tool(
                    name: "huly_list_teamspaces",
                    description: "List all document teamspaces in the workspace",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "limit": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of teamspaces to return (default: 50)"),
                            ])
                        ]),
                    ])
                ),
                Tool(
                    name: "huly_list_documents",
                    description: "List documents, optionally filtered by teamspace",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "teamspace": .object([
                                "type": .string("string"),
                                "description": .string("Optional teamspace name to filter documents"),
                            ]),
                            "limit": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of documents to return (default: 50)"),
                            ]),
                            "fetch_content": .object([
                                "type": .string("boolean"),
                                "description": .string("Fetch full document content instead of just blob IDs (default: true)"),
                            ]),
                        ]),
                    ])
                ),
                Tool(
                    name: "huly_get_document",
                    description: "Get a specific document by its ID",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object([
                                "type": .string("string"),
                                "description": .string("Document ID"),
                            ])
                        ]),
                        "required": .array([.string("id")]),
                    ])
                ),
                Tool(
                    name: "huly_create_document",
                    description: "Create a new document in a teamspace",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "teamspace": .object([
                                "type": .string("string"),
                                "description": .string("Teamspace name where the document will be created"),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("Document title"),
                            ]),
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Document content (supports markdown)"),
                            ]),
                            "parent_id": .object([
                                "type": .string("string"),
                                "description": .string("Parent document ID (use 'document:ids:NoParent' for root level, or omit to default to root)"),
                            ]),
                        ]),
                        "required": .array([.string("teamspace"), .string("title")]),
                    ])
                ),
                Tool(
                    name: "huly_update_document",
                    description: "Update an existing document",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object([
                                "type": .string("string"),
                                "description": .string("Document ID to update"),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("New title"),
                            ]),
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("New content"),
                            ]),
                        ]),
                        "required": .array([.string("id")]),
                    ])
                ),
                // Delete tools
                Tool(
                    name: "huly_delete_issue",
                    description: "Delete an issue",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Issue identifier to delete (e.g., 'HULY-123')"),
                            ])
                        ]),
                        "required": .array([.string("identifier")]),
                    ])
                ),
                Tool(
                    name: "huly_delete_document",
                    description: "Delete a document",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object([
                                "type": .string("string"),
                                "description": .string("Document ID to delete"),
                            ])
                        ]),
                        "required": .array([.string("id")]),
                    ])
                ),
                // Collection tools
                Tool(
                    name: "huly_add_label_to_issue",
                    description: "Add a label/tag to an issue",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Issue identifier (e.g., 'HULY-123')"),
                            ]),
                            "label": .object([
                                "type": .string("string"),
                                "description": .string("Label title"),
                            ]),
                            "color": .object([
                                "type": .string("integer"),
                                "description": .string("Label color index (optional)"),
                            ]),
                        ]),
                        "required": .array([.string("identifier"), .string("label")]),
                    ])
                ),
                Tool(
                    name: "huly_add_comment_to_issue",
                    description: "Add a comment to an issue",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Issue identifier (e.g., 'HULY-123')"),
                            ]),
                            "message": .object([
                                "type": .string("string"),
                                "description": .string("Comment message"),
                            ]),
                        ]),
                        "required": .array([.string("identifier"), .string("message")]),
                    ])
                ),
                Tool(
                    name: "huly_assign_issue",
                    description: "Assign an issue to a person",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string("Issue identifier (e.g., 'HULY-123')"),
                            ]),
                            "person_id": .object([
                                "type": .string("string"),
                                "description": .string("Person ID to assign (use null or omit to unassign)"),
                            ]),
                        ]),
                        "required": .array([.string("identifier")]),
                    ])
                ),
            ])
        }

        // MARK: - Call Tool Handler

        await server.withMethodHandler(CallTool.self) { params in
            var toolLogger = Logger(label: "com.huly.mcp.tool")
            toolLogger.logLevel = isDebug ? .debug : .info
            
            toolLogger.debug("Handling tool call", metadata: ["tool": "\(params.name)"])
            do {
                switch params.name {
                case "huly_list_projects":
                    toolLogger.info("Calling huly_list_projects")
                    let projects = try await hulyClient.listProjects()
                    toolLogger.debug("Retrieved projects", metadata: ["count": "\(projects.count)"])
                    let json = try formatAsJSON(projects)
                    return CallTool.Result(content: [.text(json)])

                case "huly_get_project":
                    guard let identifier = params.arguments?["identifier"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' is required")],
                            isError: true
                        )
                    }
                    if let project = try await hulyClient.getProject(identifier: identifier) {
                        let json = try formatAsJSON(project)
                        return CallTool.Result(content: [.text(json)])
                    } else {
                        return CallTool.Result(
                            content: [.text("Project '\(identifier)' not found")],
                            isError: true
                        )
                    }

                case "huly_list_issues":
                    let project = params.arguments?["project"]?.stringValue
                    let limit = params.arguments?["limit"]?.intValue ?? 50
                    let issues = try await hulyClient.listIssues(projectIdentifier: project, limit: limit)
                    let json = try formatAsJSON(issues)
                    return CallTool.Result(content: [.text(json)])

                case "huly_get_issue":
                    guard let identifier = params.arguments?["identifier"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' is required")],
                            isError: true
                        )
                    }
                    if let issue = try await hulyClient.getIssue(identifier: identifier) {
                        let json = try formatAsJSON(issue)
                        return CallTool.Result(content: [.text(json)])
                    } else {
                        return CallTool.Result(
                            content: [.text("Issue '\(identifier)' not found")],
                            isError: true
                        )
                    }

                case "huly_create_issue":
                    guard let project = params.arguments?["project"]?.stringValue,
                        let title = params.arguments?["title"]?.stringValue
                    else {
                        return CallTool.Result(
                            content: [.text("Error: 'project' and 'title' are required")],
                            isError: true
                        )
                    }
                    let description = params.arguments?["description"]?.stringValue
                    let priority = params.arguments?["priority"]?.intValue ?? 0

                    let issue = try await hulyClient.createIssue(
                        projectIdentifier: project,
                        title: title,
                        description: description,
                        priority: priority
                    )
                    let json = try formatAsJSON(issue)
                    return CallTool.Result(content: [.text("Issue created successfully:\n\(json)")])

                case "huly_update_issue":
                    guard let identifier = params.arguments?["identifier"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' is required")],
                            isError: true
                        )
                    }
                    let title = params.arguments?["title"]?.stringValue
                    let description = params.arguments?["description"]?.stringValue
                    let priority = params.arguments?["priority"]?.intValue
                    let status = params.arguments?["status"]?.stringValue

                    let issue = try await hulyClient.updateIssue(
                        identifier: identifier,
                        title: title,
                        description: description,
                        priority: priority,
                        status: status
                    )
                    let json = try formatAsJSON(issue)
                    return CallTool.Result(content: [.text("Issue updated successfully:\n\(json)")])

                case "huly_list_persons":
                    let limit = params.arguments?["limit"]?.intValue ?? 50
                    let persons = try await hulyClient.listPersons(limit: limit)
                    let json = try formatAsJSON(persons)
                    return CallTool.Result(content: [.text(json)])

                case "huly_search":
                    guard let query = params.arguments?["query"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'query' is required")],
                            isError: true
                        )
                    }
                    let limit = params.arguments?["limit"]?.intValue ?? 20
                    let results = try await hulyClient.searchFulltext(query: query, limit: limit)
                    return CallTool.Result(content: [.text(results)])

                // Document handlers
                case "huly_list_teamspaces":
                    let limit = params.arguments?["limit"]?.intValue ?? 50
                    let teamspaces = try await hulyClient.listTeamspaces(limit: limit)
                    let json = try formatAsJSON(teamspaces)
                    return CallTool.Result(content: [.text(json)])

                case "huly_list_documents":
                    let teamspace = params.arguments?["teamspace"]?.stringValue
                    let limit = params.arguments?["limit"]?.intValue ?? 50
                    let fetchContent = params.arguments?["fetch_content"]?.boolValue ?? true
                    let documents = try await hulyClient.listDocuments(teamspace: teamspace, limit: limit, fetchContent: fetchContent)
                    let json = try formatAsJSON(documents)
                    return CallTool.Result(content: [.text(json)])

                case "huly_get_document":
                    guard let id = params.arguments?["id"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'id' is required")],
                            isError: true
                        )
                    }
                    if let document = try await hulyClient.getDocument(id: id) {
                        let json = try formatAsJSON(document)
                        return CallTool.Result(content: [.text(json)])
                    } else {
                        return CallTool.Result(
                            content: [.text("Document not found")],
                            isError: true
                        )
                    }

                case "huly_create_document":
                    guard let teamspace = params.arguments?["teamspace"]?.stringValue,
                        let title = params.arguments?["title"]?.stringValue
                    else {
                        return CallTool.Result(
                            content: [.text("Error: 'teamspace' and 'title' are required")],
                            isError: true
                        )
                    }
                    let content = params.arguments?["content"]?.stringValue
                    let parentId = params.arguments?["parent_id"]?.stringValue ?? DocumentSpace.noParent

                    // WebSocket write path
                    let docId = try await hulyClient.createDocumentViaWebSocket(
                        teamspace: teamspace,
                        title: title,
                        content: content,
                        parent: parentId
                    )

                    // Fetch and return the created document via REST
                    guard let document = try await hulyClient.getDocument(id: docId, fetchContent: true) else {
                        throw HulyError.requestFailed("Created document but failed to fetch it")
                    }

                    let json = try formatAsJSON(document)
                    return CallTool.Result(content: [.text("Document created successfully:\n\(json)")])

                case "huly_update_document":
                    guard let id = params.arguments?["id"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'id' is required")],
                            isError: true
                        )
                    }
                    let title = params.arguments?["title"]?.stringValue
                    let content = params.arguments?["content"]?.stringValue

                    // Need document to know teamspaceId
                    guard let existing = try await hulyClient.getDocument(id: id, fetchContent: false) else {
                        throw HulyError.notFound("Document '\(id)' not found")
                    }

                    // WebSocket write path
                    try await hulyClient.updateDocumentViaWebSocket(
                        documentId: id,
                        teamspaceId: existing.space,
                        title: title,
                        content: content
                    )

                    // Fetch updated
                    guard let document = try await hulyClient.getDocument(id: id, fetchContent: true) else {
                        throw HulyError.requestFailed("Updated document but failed to fetch it")
                    }

                    let json = try formatAsJSON(document)
                    return CallTool.Result(content: [.text("Document updated successfully:\n\(json)")])

                // Delete handlers
                case "huly_delete_issue":
                    guard let identifier = params.arguments?["identifier"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' is required")],
                            isError: true
                        )
                    }
                    try await hulyClient.deleteIssue(identifier: identifier)
                    return CallTool.Result(content: [.text("Issue '\(identifier)' deleted successfully")])

                case "huly_delete_document":
                    guard let id = params.arguments?["id"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'id' is required")],
                            isError: true
                        )
                    }

                    // Need document to know teamspaceId
                    guard let existing = try await hulyClient.getDocument(id: id, fetchContent: false) else {
                        throw HulyError.notFound("Document '\(id)' not found")
                    }

                    // WebSocket write path
                    try await hulyClient.deleteDocumentViaWebSocket(
                        documentId: id,
                        teamspaceId: existing.space
                    )

                    return CallTool.Result(content: [.text("Document deleted successfully")])

                // Collection handlers
                case "huly_add_label_to_issue":
                    guard let identifier = params.arguments?["identifier"]?.stringValue,
                        let label = params.arguments?["label"]?.stringValue
                    else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' and 'label' are required")],
                            isError: true
                        )
                    }
                    let color = params.arguments?["color"]?.intValue ?? 0
                    try await hulyClient.addLabelToIssue(issueIdentifier: identifier, labelTitle: label, color: color)
                    return CallTool.Result(content: [.text("Label '\(label)' added to issue '\(identifier)'")])

                case "huly_add_comment_to_issue":
                    guard let identifier = params.arguments?["identifier"]?.stringValue,
                        let message = params.arguments?["message"]?.stringValue
                    else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' and 'message' are required")],
                            isError: true
                        )
                    }
                    try await hulyClient.addCommentToIssue(issueIdentifier: identifier, message: message)
                    return CallTool.Result(content: [.text("Comment added to issue '\(identifier)'")])

                case "huly_assign_issue":
                    guard let identifier = params.arguments?["identifier"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'identifier' is required")],
                            isError: true
                        )
                    }
                    let personId = params.arguments?["person_id"]?.stringValue
                    let issue = try await hulyClient.assignIssue(identifier: identifier, personId: personId)
                    let json = try formatAsJSON(issue)
                    if personId != nil {
                        return CallTool.Result(content: [.text("Issue assigned successfully:\n\(json)")])
                    } else {
                        return CallTool.Result(content: [.text("Issue unassigned successfully:\n\(json)")])
                    }

                case "huly_test_upload_blob":
                    guard let content = params.arguments?["content"]?.stringValue else {
                        return CallTool.Result(
                            content: [.text("Error: 'content' is required")],
                            isError: true
                        )
                    }
                    let filename = params.arguments?["filename"]?.stringValue ?? "content"
                    let result = try await hulyClient.uploadBlob(content: content, filename: filename)
                    return CallTool.Result(content: [.text("Upload response:\n\(result)")])

                default:
                    return handleError(
                        HulyError.invalidInput("Unknown tool: \(params.name)"),
                        operation: params.name
                    )
                }
            } catch {
                return handleError(error, operation: params.name)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        logger.info("Server started and listening")
        await server.waitUntilCompleted()
    }
}

// MARK: - Error Handling

private struct ErrorResponse: Encodable {
    let error: ErrorDetail

    struct ErrorDetail: Encodable {
        let code: String
        let message: String
        let context: [String: String]?
    }
}

private func handleError(_ error: Error, operation: String) -> CallTool.Result {
    let errorDetail: ErrorResponse.ErrorDetail

    switch error {
    case let hulyError as HulyError:
        errorDetail = mapHulyError(hulyError, operation: operation)
    case let urlError as URLError:
        errorDetail = .init(
            code: "NETWORK_ERROR",
            message: "Network error: \(urlError.localizedDescription)",
            context: ["operation": operation, "code": "\(urlError.code.rawValue)"]
        )
    case let decodingError as DecodingError:
        errorDetail = .init(
            code: "DECODE_ERROR",
            message: "Failed to parse response",
            context: ["operation": operation, "detail": formatDecodingError(decodingError)]
        )
    default:
        errorDetail = .init(
            code: "UNKNOWN_ERROR",
            message: error.localizedDescription,
            context: ["operation": operation]
        )
    }

    let response = ErrorResponse(error: errorDetail)
    let jsonString = (try? formatAsJSON(response)) ?? "{\"error\":{\"code\":\"FORMAT_ERROR\",\"message\":\"Failed to format error\"}}"
    return CallTool.Result(content: [.text(jsonString)], isError: true)
}

private func mapHulyError(_ error: HulyError, operation: String) -> ErrorResponse.ErrorDetail {
    switch error {
    case .invalidInput(let msg):
        return .init(code: "INVALID_INPUT", message: msg, context: ["operation": operation])
    case .notAuthenticated:
        return .init(code: "AUTH_REQUIRED", message: "Authentication required", context: nil)
    case .authenticationFailed(let msg):
        return .init(code: "AUTH_FAILED", message: msg, context: ["operation": operation])
    case .notFound(let msg):
        return .init(code: "NOT_FOUND", message: msg, context: ["operation": operation])
    case .requestFailed(let msg):
        return .init(code: "REQUEST_FAILED", message: msg, context: ["operation": operation])
    case .invalidConfiguration(let msg):
        return .init(code: "CONFIG_ERROR", message: msg, context: nil)
    case .invalidURL(let msg):
        return .init(code: "URL_ERROR", message: msg, context: ["operation": operation])
    case .invalidResponse:
        return .init(code: "INVALID_RESPONSE", message: "Invalid response from server", context: ["operation": operation])
    case .notConnected:
        return .init(code: "WS_NOT_CONNECTED", message: "WebSocket not connected", context: ["operation": operation])
    case .connectionClosed:
        return .init(code: "WS_CONNECTION_CLOSED", message: "WebSocket connection was closed", context: ["operation": operation])
    case .timeout:
        return .init(code: "TIMEOUT", message: "Operation timed out", context: ["operation": operation])
    case .serverError(let code, let msg):
        return .init(code: "SERVER_ERROR_\(code)", message: msg, context: ["operation": operation, "error_code": code])
    }
}

private func formatDecodingError(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, _):
        return "Missing key: \(key.stringValue)"
    case .typeMismatch(let type, let context):
        return "Type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: ".")): expected \(type)"
    case .valueNotFound(let type, _):
        return "Missing value of type \(type)"
    case .dataCorrupted(let context):
        return "Data corrupted: \(context.debugDescription)"
    @unknown default:
        return "Unknown decoding error"
    }
}

// MARK: - Helpers

private func formatAsJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
}

//
//  HulyClient.swift
//  huly-mcp
//

import Foundation
import Logging

// MARK: - Models

struct HulyConfig: Sendable {
    let baseURL: String
    let email: String
    let password: String
    let workspace: String

    init(
        baseURL: String = ProcessInfo.processInfo.environment["HULY_URL"] ?? "https://huly.io",
        email: String = ProcessInfo.processInfo.environment["HULY_EMAIL"] ?? "",
        password: String = ProcessInfo.processInfo.environment["HULY_PASSWORD"] ?? "",
        workspace: String = ProcessInfo.processInfo.environment["HULY_WORKSPACE"] ?? ""
    ) {
        self.baseURL = baseURL
        self.email = email
        self.password = password
        self.workspace = workspace
    }
}

struct ServerConfig: Codable, Sendable {
    let ACCOUNTS_URL: String
    let COLLABORATOR_URL: String?
    let FILES_URL: String?
    let UPLOAD_URL: String?
}

struct RPCRequest: Encodable {
    let method: String
    let params: [String: String]
}

struct RPCResponse<T: Decodable>: Decodable {
    let result: T?
    let error: RPCError?
}

struct RPCError: Decodable {
    let severity: String?
    let code: String?
}

struct LoginInfo: Codable, Sendable {
    let token: String
    let account: String
    let name: String?
}

struct SocialId: Codable, Sendable {
    let _id: String
    let type: String
    let value: String
}

struct WorkspaceInfo: Codable, Sendable {
    let uuid: String
    let name: String
    let url: String
}

struct WorkspaceLoginInfo: Codable, Sendable {
    let token: String
    let endpoint: String
    let workspace: String
    let workspaceUrl: String
}

/// API response wrapper for find-all queries
struct FindAllResponse<T: Decodable>: Decodable {
    let dataType: String?
    let total: Int?
    let value: [T]
}

struct HulyProject: Codable, Sendable {
    let _id: String
    let identifier: String?
    let name: String
    let description: String?
    let defaultIssueStatus: String?
    let sequence: Int?

    enum CodingKeys: String, CodingKey {
        case _id, identifier, name, description, defaultIssueStatus, sequence
    }
}

struct HulyIssue: Codable, Sendable {
    let _id: String
    let identifier: String?
    let title: String
    let description: String?
    let status: String?
    let priority: Int?
    let number: Int?
    let assignee: String?
    let dueDate: Int?

    enum CodingKeys: String, CodingKey {
        case _id, identifier, title, description, status, priority, number, assignee, dueDate
    }
}

struct HulyPerson: Codable, Sendable {
    let _id: String
    let name: String
    let city: String?

    enum CodingKeys: String, CodingKey {
        case _id, name, city
    }
}

struct HulyTeamspace: Codable, Sendable {
    let _id: String
    let name: String
    let description: String?
    let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case _id, name, description, archived
    }
}

struct HulyDocument: Codable, Sendable {
    let _id: String?
    let title: String
    let content: String?
    let space: String?
    let parent: String?
    let attachedTo: String?
    let attachments: Int?
    let children: Int?

    enum CodingKeys: String, CodingKey {
        case _id, title, content, space, parent, attachedTo, attachments, children
    }
}

// MARK: - Validation

private struct Validation {
    /// Valida formato de identificador de issue (e.g., "PROJ-123")
    static func validateIdentifier(_ identifier: String, context: String) throws {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw HulyError.invalidInput("\(context): identifier cannot be empty")
        }
        guard trimmed.count <= 50 else {
            throw HulyError.invalidInput("\(context): identifier too long (max 50 chars)")
        }
        // Padrão básico: LETRAS-NUMEROS
        let pattern = /^[A-Z0-9]+-[0-9]+$/
        guard trimmed.wholeMatch(of: pattern) != nil else {
            throw HulyError.invalidInput("\(context): invalid format (expected 'PROJ-123')")
        }
    }

    /// Valida identificador de projeto (e.g., "CLICK", "KRNL", "$")
    static func validateProjectIdentifier(_ identifier: String, context: String) throws {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw HulyError.invalidInput("\(context): project identifier cannot be empty")
        }
        guard trimmed.count <= 50 else {
            throw HulyError.invalidInput("\(context): project identifier too long (max 50 chars)")
        }
    }

    /// Valida títulos/nomes
    static func validateTitle(_ title: String, context: String, maxLength: Int = 500) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HulyError.invalidInput("\(context): title cannot be empty")
        }
        guard trimmed.count <= maxLength else {
            throw HulyError.invalidInput("\(context): title too long (max \(maxLength) chars)")
        }
    }

    /// Valida descrições
    static func validateDescription(_ description: String?, maxLength: Int = 10000) throws {
        if let desc = description, desc.count > maxLength {
            throw HulyError.invalidInput("Description too long (max \(maxLength) chars)")
        }
    }

    /// Valida prioridade (0-4)
    static func validatePriority(_ priority: Int) throws {
        guard (0...4).contains(priority) else {
            throw HulyError.invalidInput("Invalid priority: \(priority) (must be 0-4)")
        }
    }

    /// Valida limite de resultados
    static func validateLimit(_ limit: Int) throws {
        guard limit > 0 else {
            throw HulyError.invalidInput("Limit must be positive (got \(limit))")
        }
        guard limit <= 1000 else {
            throw HulyError.invalidInput("Limit too large (max 1000, got \(limit))")
        }
    }
}

// MARK: - Huly Client

actor HulyClient {
    private let config: HulyConfig
    private let session: URLSession
    private var accountsURL: String?
    private var token: String?
    private var workspaceToken: String?
    private var workspaceEndpoint: String?
    private var workspaceId: String?
    private var accountId: String?
    private var filesURL: String?
    private let logger: Logger

    init(config: HulyConfig = HulyConfig()) {
        self.config = config
        self.session = URLSession.shared

        var logger = Logger(label: "com.huly.mcp.client")
        logger.logLevel = ProcessInfo.processInfo.environment["DEBUG"] == "1" ? .debug : .info
        self.logger = logger
    }

    // MARK: - Authentication

    func authenticate() async throws {
        logger.info("Starting authentication", metadata: ["workspace": "\(config.workspace)"])

        // Step 1: Get server config to find ACCOUNTS_URL
        logger.debug("Fetching server config")
        guard let configURL = URL(string: "\(config.baseURL)/config.json") else {
            logger.error("Invalid base URL", metadata: ["url": "\(config.baseURL)"])
            throw HulyError.invalidConfiguration("Invalid base URL: \(config.baseURL)")
        }
        let (configData, configResponse) = try await session.data(from: configURL)

        guard let httpResponse = configResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            logger.error("Failed to fetch server config")
            throw HulyError.authenticationFailed("Failed to fetch server config")
        }

        let serverConfig = try JSONDecoder().decode(ServerConfig.self, from: configData)
        self.accountsURL = serverConfig.ACCOUNTS_URL
        self.filesURL = serverConfig.FILES_URL
        logger.debug("Config fetched successfully")

        // Step 2: Login via JSON-RPC
        logger.debug("Logging in")
        guard let loginURL = URL(string: serverConfig.ACCOUNTS_URL) else {
            logger.error("Invalid ACCOUNTS_URL", metadata: ["url": "\(serverConfig.ACCOUNTS_URL)"])
            throw HulyError.invalidConfiguration("Invalid ACCOUNTS_URL: \(serverConfig.ACCOUNTS_URL)")
        }
        var loginRequest = URLRequest(url: loginURL)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let loginBody: [String: Any] = [
            "method": "login",
            "params": [
                "email": config.email,
                "password": config.password,
            ],
        ]
        loginRequest.httpBody = try JSONSerialization.data(withJSONObject: loginBody)

        let (loginData, loginResponse) = try await session.data(for: loginRequest)

        guard let loginHttpResponse = loginResponse as? HTTPURLResponse, loginHttpResponse.statusCode == 200 else {
            let errorBody = String(data: loginData, encoding: .utf8) ?? "Unknown error"
            throw HulyError.authenticationFailed("Login failed: \(errorBody)")
        }

        let loginResult = try JSONDecoder().decode(RPCResponse<LoginInfo>.self, from: loginData)

        guard let loginInfo = loginResult.result else {
            let errorCode = loginResult.error?.code ?? "Unknown"
            throw HulyError.authenticationFailed("Login failed: \(errorCode)")
        }

        self.token = loginInfo.token

        // Step 3: Get social IDs to get the PersonId
        var socialIdsRequest = URLRequest(url: loginURL)
        socialIdsRequest.httpMethod = "POST"
        socialIdsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        socialIdsRequest.setValue("Bearer \(loginInfo.token)", forHTTPHeaderField: "Authorization")

        let socialIdsBody: [String: Any] = [
            "method": "getSocialIds",
            "params": [:],
        ]
        socialIdsRequest.httpBody = try JSONSerialization.data(withJSONObject: socialIdsBody)

        let (socialIdsData, _) = try await session.data(for: socialIdsRequest)
        let socialIdsResult = try JSONDecoder().decode(RPCResponse<[SocialId]>.self, from: socialIdsData)

        guard let socialIds = socialIdsResult.result, let primarySocialId = socialIds.first else {
            throw HulyError.authenticationFailed("Failed to get social IDs")
        }

        self.accountId = primarySocialId._id

        // Step 4: Get workspaces to find the correct workspace URL
        var workspacesRequest = URLRequest(url: loginURL)
        workspacesRequest.httpMethod = "POST"
        workspacesRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        workspacesRequest.setValue("Bearer \(loginInfo.token)", forHTTPHeaderField: "Authorization")

        let workspacesBody: [String: Any] = [
            "method": "getUserWorkspaces",
            "params": [:],
        ]
        workspacesRequest.httpBody = try JSONSerialization.data(withJSONObject: workspacesBody)

        let (workspacesData, _) = try await session.data(for: workspacesRequest)
        let workspacesResult = try JSONDecoder().decode(RPCResponse<[WorkspaceInfo]>.self, from: workspacesData)

        // Find the workspace by name
        var workspaceUrl = config.workspace
        if let workspaces = workspacesResult.result {
            if let ws = workspaces.first(where: {
                $0.name.lowercased() == config.workspace.lowercased() || $0.url.lowercased() == config.workspace.lowercased()
            }) {
                workspaceUrl = ws.url
            }
        }

        // Step 5: Select workspace via JSON-RPC
        var selectRequest = URLRequest(url: loginURL)
        selectRequest.httpMethod = "POST"
        selectRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        selectRequest.setValue("Bearer \(loginInfo.token)", forHTTPHeaderField: "Authorization")

        let selectBody: [String: Any] = [
            "method": "selectWorkspace",
            "params": ["workspaceUrl": workspaceUrl],
        ]
        selectRequest.httpBody = try JSONSerialization.data(withJSONObject: selectBody)

        let (wsData, wsResponse) = try await session.data(for: selectRequest)

        guard let wsHttpResponse = wsResponse as? HTTPURLResponse, wsHttpResponse.statusCode == 200 else {
            let errorBody = String(data: wsData, encoding: .utf8) ?? "Unknown error"
            throw HulyError.authenticationFailed("Workspace selection failed: \(errorBody)")
        }

        let wsResult = try JSONDecoder().decode(RPCResponse<WorkspaceLoginInfo>.self, from: wsData)

        guard let wsInfo = wsResult.result else {
            let errorCode = wsResult.error?.code ?? "Unknown"
            throw HulyError.authenticationFailed("Workspace selection failed: \(errorCode)")
        }

        self.workspaceToken = wsInfo.token
        self.workspaceEndpoint = wsInfo.endpoint.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(
            of: "ws://",
            with: "http://"
        )
        self.workspaceId = wsInfo.workspace

        logger.info("Authentication successful", metadata: ["workspace_id": "\(wsInfo.workspace)"])
    }

    private func ensureAuthenticated() async throws {
        if workspaceToken == nil {
            try await authenticate()
        }
    }

    private func apiURL(path: String) throws -> URL {
        var endpoint = workspaceEndpoint ?? config.baseURL
        // Remove trailing slash to avoid double slashes
        if endpoint.hasSuffix("/") {
            endpoint = String(endpoint.dropLast())
        }
        guard let url = URL(string: "\(endpoint)\(path)") else {
            throw HulyError.invalidURL("Failed to construct URL: \(endpoint)\(path)")
        }
        return url
    }

    private func authorizedRequest(url: URL, method: String = "GET") throws -> URLRequest {
        guard let token = workspaceToken else {
            throw HulyError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    // MARK: - Projects

    func listProjects() async throws -> [HulyProject] {
        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "_class": "tracker:class:Project",
            "query": [:],
            "options": ["limit": 100],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to list projects")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyProject>.self, from: data)
        return result.value
    }

    func getProject(identifier: String) async throws -> HulyProject? {
        try Validation.validateProjectIdentifier(identifier, context: "getProject")

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "_class": "tracker:class:Project",
            "query": ["identifier": identifier],
            "options": ["limit": 1],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to get project")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyProject>.self, from: data)
        return result.value.first
    }

    // MARK: - Issues

    func listIssues(projectIdentifier: String? = nil, limit: Int = 50) async throws -> [HulyIssue] {
        try Validation.validateLimit(limit)
        if let projectIdentifier = projectIdentifier {
            try Validation.validateProjectIdentifier(projectIdentifier, context: "listIssues")
        }

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        var query: [String: Any] = [:]
        if let projectId = projectIdentifier {
            if let project = try await getProject(identifier: projectId) {
                query["space"] = project._id
            }
        }

        let body: [String: Any] = [
            "_class": "tracker:class:Issue",
            "query": query,
            "options": [
                "limit": limit,
                "sort": ["modifiedOn": -1],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to list issues")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyIssue>.self, from: data)
        return result.value
    }

    func getIssue(identifier: String) async throws -> HulyIssue? {
        try Validation.validateIdentifier(identifier, context: "getIssue")

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "_class": "tracker:class:Issue",
            "query": ["identifier": identifier],
            "options": ["limit": 1],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to get issue")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyIssue>.self, from: data)
        return result.value.first
    }

    func createIssue(
        projectIdentifier: String,
        title: String,
        description: String? = nil,
        priority: Int = 0
    ) async throws -> HulyIssue {
        // Validate inputs
        try Validation.validateProjectIdentifier(projectIdentifier, context: "createIssue")
        try Validation.validateTitle(title, context: "createIssue")
        try Validation.validateDescription(description)
        try Validation.validatePriority(priority)

        logger.debug("Creating issue", metadata: ["project": "\(projectIdentifier)", "title": "\(title)"])

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let project = try await getProject(identifier: projectIdentifier) else {
            throw HulyError.notFound("Project \(projectIdentifier) not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let issueId = UUID().uuidString.lowercased()
        let sequence = (project.sequence ?? 0) + 1

        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxCreateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "createdBy": accountId,
            "objectId": issueId,
            "objectClass": "tracker:class:Issue",
            "objectSpace": project._id,
            "attachedTo": project._id,
            "attachedToClass": "tracker:class:Project",
            "collection": "issues",
            "attributes": [
                "title": title,
                "description": description ?? "",
                "status": project.defaultIssueStatus ?? "",
                "priority": priority,
                "number": sequence,
                "identifier": "\(projectIdentifier)-\(sequence)",
                "kind": "tracker:taskTypes:Issue",
                "assignee": NSNull(),
                "component": NSNull(),
                "estimation": 0,
                "remainingTime": 0,
                "reportedTime": 0,
                "reports": 0,
                "subIssues": 0,
                "parents": [],
                "childInfo": [],
                "dueDate": NSNull(),
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to create issue: \(errorBody)")
        }

        // Fetch the created issue
        if let issue = try await getIssue(identifier: "\(projectIdentifier)-\(sequence)") {
            logger.info("Issue created", metadata: ["identifier": "\(issue.identifier ?? "unknown")"])
            return issue
        }

        // Return a basic issue if fetch fails
        logger.info("Issue created (basic response)", metadata: ["identifier": "\(projectIdentifier)-\(sequence)"])
        return HulyIssue(
            _id: issueId,
            identifier: "\(projectIdentifier)-\(sequence)",
            title: title,
            description: description,
            status: project.defaultIssueStatus,
            priority: priority,
            number: sequence,
            assignee: nil,
            dueDate: nil
        )
    }

    func updateIssue(
        identifier: String,
        title: String? = nil,
        description: String? = nil,
        priority: Int? = nil,
        status: String? = nil
    ) async throws -> HulyIssue {
        try Validation.validateIdentifier(identifier, context: "updateIssue")
        if let title = title {
            try Validation.validateTitle(title, context: "updateIssue")
        }
        try Validation.validateDescription(description)
        if let priority = priority {
            try Validation.validatePriority(priority)
        }

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let issue = try await getIssue(identifier: identifier) else {
            throw HulyError.notFound("Issue \(identifier) not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        var operations: [String: Any] = [:]
        if let title = title { operations["title"] = title }
        if let description = description { operations["description"] = description }
        if let priority = priority { operations["priority"] = priority }
        if let status = status { operations["status"] = status }

        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxUpdateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "objectId": issue._id,
            "objectClass": "tracker:class:Issue",
            "objectSpace": "core:space:Space",
            "operations": operations,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to update issue: \(errorBody)")
        }

        // Fetch the updated issue
        if let updatedIssue = try await getIssue(identifier: identifier) {
            return updatedIssue
        }

        return issue
    }

    // MARK: - Contacts/Persons

    func listPersons(limit: Int = 50) async throws -> [HulyPerson] {
        try Validation.validateLimit(limit)

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "_class": "contact:class:Person",
            "query": [:],
            "options": ["limit": limit],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to list persons")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyPerson>.self, from: data)
        return result.value
    }

    // MARK: - Blob Storage

    private func fetchBlobContent(blobId: String) async throws -> String? {
        guard let filesURLTemplate = filesURL else {
            logger.warning("FILES_URL not configured, cannot fetch blob content")
            return nil
        }

        try await ensureAuthenticated()

        guard let token = workspaceToken else {
            throw HulyError.notAuthenticated
        }

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        // Construct the blob URL
        // FILES_URL is a template like "/files/:workspace/:filename?file=:blobId&workspace=:workspace"
        // We need to replace placeholders and make it absolute
        let urlPath = filesURLTemplate
            .replacingOccurrences(of: ":workspace", with: wsId)
            .replacingOccurrences(of: ":blobId", with: blobId)
            .replacingOccurrences(of: ":filename", with: "content")

        // If it's a relative path, combine with workspace endpoint
        let urlString: String
        if urlPath.hasPrefix("/") {
            guard let endpoint = workspaceEndpoint else {
                logger.error("No workspace endpoint available")
                return nil
            }
            var baseURL = endpoint
            if baseURL.hasSuffix("/") {
                baseURL = String(baseURL.dropLast())
            }
            urlString = "\(baseURL)\(urlPath)"
        } else {
            urlString = urlPath
        }

        logger.debug("Attempting to fetch blob", metadata: [
            "blobId": "\(blobId)",
            "filesURLTemplate": "\(filesURLTemplate)",
            "constructedURL": "\(urlString)"
        ])

        guard let url = URL(string: urlString) else {
            logger.error("Failed to construct blob URL", metadata: [
                "blobId": "\(blobId)",
                "urlString": "\(urlString)"
            ])
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type for blob fetch")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Failed to fetch blob", metadata: [
                    "statusCode": "\(httpResponse.statusCode)",
                    "blobId": "\(blobId)"
                ])
                return nil
            }

            // Try to decode as string (assuming it's text content)
            if let content = String(data: data, encoding: .utf8) {
                return content
            } else {
                logger.warning("Blob content is not valid UTF-8", metadata: ["blobId": "\(blobId)"])
                return nil
            }
        } catch {
            logger.error("Error fetching blob", metadata: [
                "error": "\(error.localizedDescription)",
                "blobId": "\(blobId)"
            ])
            return nil
        }
    }

    func uploadBlob(content: String, filename: String = "content") async throws -> String {
        try await ensureAuthenticated()

        guard let token = workspaceToken else {
            throw HulyError.notAuthenticated
        }

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let endpoint = workspaceEndpoint else {
            throw HulyError.notAuthenticated
        }

        var baseURL = endpoint
        if baseURL.hasSuffix("/") {
            baseURL = String(baseURL.dropLast())
        }

        guard let url = URL(string: "\(baseURL)/files?space=\(wsId)") else {
            throw HulyError.invalidURL("Failed to construct upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add workspace field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"workspace\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(wsId)\r\n".data(using: .utf8)!)

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(content.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HulyError.invalidResponse
        }

        logger.debug("Upload response status", metadata: ["statusCode": "\(httpResponse.statusCode)"])

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to upload blob: \(errorBody)")
        }

        // Return the response as string to see what we get
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Teamspaces

    func listTeamspaces(limit: Int = 50) async throws -> [HulyTeamspace] {
        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "_class": "document:class:Teamspace",
            "query": ["archived": false],
            "options": ["limit": limit],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to list teamspaces")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyTeamspace>.self, from: data)
        return result.value
    }

    func getTeamspace(name: String) async throws -> HulyTeamspace? {
        let allTeamspaces = try await listTeamspaces(limit: 100)
        return allTeamspaces.first { $0.name.lowercased() == name.lowercased() }
    }

    // MARK: - Documents

    func listDocuments(teamspaceName: String? = nil, limit: Int = 50, fetchContent: Bool = false) async throws -> [HulyDocument] {
        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        var query: [String: Any] = [:]
        if let tsName = teamspaceName {
            if let teamspace = try await getTeamspace(name: tsName) {
                query["space"] = teamspace._id
            }
        }

        let body: [String: Any] = [
            "_class": "document:class:Document",
            "query": query,
            "options": [
                "limit": limit,
                "sort": ["modifiedOn": -1],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to list documents")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyDocument>.self, from: data)
        var documents = result.value

        // If fetchContent is true, fetch the real content for each document
        if fetchContent {
            logger.debug("Fetching content for \(documents.count) documents")
            var documentsWithContent: [HulyDocument] = []

            for document in documents {
                var doc = document
                if let contentId = document.content, contentId.contains("-content-") {
                    if let blobContent = try await fetchBlobContent(blobId: contentId) {
                        doc = HulyDocument(
                            _id: document._id,
                            title: document.title,
                            content: blobContent,
                            space: document.space,
                            parent: document.parent,
                            attachedTo: document.attachedTo,
                            attachments: document.attachments,
                            children: document.children
                        )
                    }
                }
                documentsWithContent.append(doc)
            }
            documents = documentsWithContent
        }

        return documents
    }

    func getDocument(id: String) async throws -> HulyDocument? {
        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "_class": "document:class:Document",
            "query": ["_id": id],
            "options": ["limit": 1],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Failed to get document")
        }

        let result = try JSONDecoder().decode(FindAllResponse<HulyDocument>.self, from: data)
        guard var document = result.value.first else {
            return nil
        }

        // If content is a blob ID (contains "-content-"), fetch the real content
        if let contentId = document.content, contentId.contains("-content-") {
            logger.debug("Fetching blob content", metadata: ["blobId": "\(contentId)"])
            if let blobContent = try await fetchBlobContent(blobId: contentId) {
                document = HulyDocument(
                    _id: document._id,
                    title: document.title,
                    content: blobContent,
                    space: document.space,
                    parent: document.parent,
                    attachedTo: document.attachedTo,
                    attachments: document.attachments,
                    children: document.children
                )
                logger.debug("Blob content fetched successfully")
            } else {
                logger.warning("Failed to fetch blob content, returning blob ID")
            }
        }

        return document
    }

    func createDocument(
        teamspaceName: String,
        title: String,
        content: String? = nil,
        parentId: String? = nil
    ) async throws -> HulyDocument {
        try Validation.validateTitle(teamspaceName, context: "createDocument.teamspace", maxLength: 100)
        try Validation.validateTitle(title, context: "createDocument")

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let teamspace = try await getTeamspace(name: teamspaceName) else {
            throw HulyError.notFound("Teamspace '\(teamspaceName)' not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let docId = UUID().uuidString.lowercased()
        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxCreateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "createdBy": accountId,
            "objectId": docId,
            "objectClass": "document:class:Document",
            "objectSpace": teamspace._id,
            "attributes": [
                "title": title,
                "content": content ?? "",
                "parent": parentId ?? "document:ids:NoParent",
                "attachments": 0,
                "children": 0,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to create document: \(errorBody)")
        }

        // Return the created document
        return HulyDocument(
            _id: docId,
            title: title,
            content: content,
            space: teamspace._id,
            parent: parentId ?? "document:ids:NoParent",
            attachedTo: nil,
            attachments: 0,
            children: 0
        )
    }

    func updateDocument(
        id: String,
        title: String? = nil,
        content: String? = nil
    ) async throws -> HulyDocument {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw HulyError.invalidInput("updateDocument: id cannot be empty")
        }
        if let title = title {
            try Validation.validateTitle(title, context: "updateDocument")
        }

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        var operations: [String: Any] = [:]
        if let title = title { operations["title"] = title }
        if let content = content { operations["content"] = content }

        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxUpdateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "objectId": id,
            "objectClass": "document:class:Document",
            "objectSpace": "core:space:Space",
            "operations": operations,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to update document: \(errorBody)")
        }

        // Return a basic document structure
        return HulyDocument(
            _id: id,
            title: title ?? "",
            content: content,
            space: nil,
            parent: nil,
            attachedTo: nil,
            attachments: nil,
            children: nil
        )
    }

    // MARK: - Delete Operations

    func deleteIssue(identifier: String) async throws {
        try Validation.validateIdentifier(identifier, context: "deleteIssue")

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let issue = try await getIssue(identifier: identifier) else {
            throw HulyError.notFound("Issue \(identifier) not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxRemoveDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "objectId": issue._id,
            "objectClass": "tracker:class:Issue",
            "objectSpace": "core:space:Space",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to delete issue: \(errorBody)")
        }
    }

    func deleteDocument(id: String) async throws {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw HulyError.invalidInput("deleteDocument: id cannot be empty")
        }

        try await ensureAuthenticated()

        guard let wsId = workspaceId else{
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxRemoveDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "objectId": id,
            "objectClass": "document:class:Document",
            "objectSpace": "core:space:Space",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to delete document: \(errorBody)")
        }
    }

    // MARK: - Labels (Collections)

    func addLabelToIssue(issueIdentifier: String, labelTitle: String, color: Int = 0) async throws {
        try Validation.validateIdentifier(issueIdentifier, context: "addLabelToIssue")
        try Validation.validateTitle(labelTitle, context: "addLabelToIssue.label", maxLength: 50)

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let issue = try await getIssue(identifier: issueIdentifier) else {
            throw HulyError.notFound("Issue \(issueIdentifier) not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let labelId = UUID().uuidString.lowercased()
        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxCreateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "createdBy": accountId,
            "objectId": labelId,
            "objectClass": "tags:class:TagElement",
            "objectSpace": "core:space:Space",
            "attachedTo": issue._id,
            "attachedToClass": "tracker:class:Issue",
            "collection": "labels",
            "attributes": [
                "title": labelTitle,
                "color": color,
                "tag": issue._id,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to add label: \(errorBody)")
        }
    }

    // MARK: - Comments

    func addCommentToIssue(issueIdentifier: String, message: String) async throws {
        try Validation.validateIdentifier(issueIdentifier, context: "addCommentToIssue")
        try Validation.validateTitle(message, context: "addCommentToIssue.message", maxLength: 10000)

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let issue = try await getIssue(identifier: issueIdentifier) else {
            throw HulyError.notFound("Issue \(issueIdentifier) not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let commentId = UUID().uuidString.lowercased()
        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxCreateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "createdBy": accountId,
            "objectId": commentId,
            "objectClass": "chunter:class:ChatMessage",
            "objectSpace": "core:space:Space",
            "attachedTo": issue._id,
            "attachedToClass": "tracker:class:Issue",
            "collection": "comments",
            "attributes": [
                "message": message,
                "attachedTo": issue._id,
                "attachedToClass": "tracker:class:Issue",
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to add comment: \(errorBody)")
        }
    }

    // MARK: - Assign Issue

    func assignIssue(identifier: String, personId: String?) async throws -> HulyIssue {
        try Validation.validateIdentifier(identifier, context: "assignIssue")

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        guard let issue = try await getIssue(identifier: identifier) else {
            throw HulyError.notFound("Issue \(identifier) not found")
        }

        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        var operations: [String: Any] = [:]
        if let personId = personId {
            operations["assignee"] = personId
        } else {
            operations["assignee"] = NSNull()
        }

        let txId = UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970 * 1000)

        guard let accountId = accountId else {
            throw HulyError.notAuthenticated
        }

        let txBody: [String: Any] = [
            "_id": txId,
            "_class": "core:class:TxUpdateDoc",
            "space": "core:space:Tx",
            "modifiedOn": now,
            "modifiedBy": accountId,
            "objectId": issue._id,
            "objectClass": "tracker:class:Issue",
            "objectSpace": "core:space:Space",
            "operations": operations,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: txBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to assign issue: \(errorBody)")
        }

        if let updatedIssue = try await getIssue(identifier: identifier) {
            return updatedIssue
        }

        return issue
    }

    // MARK: - Search

    func searchFulltext(query: String, limit: Int = 20) async throws -> String {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw HulyError.invalidInput("searchFulltext: query cannot be empty")
        }
        try Validation.validateLimit(limit)

        try await ensureAuthenticated()

        guard let wsId = workspaceId else {
            throw HulyError.notAuthenticated
        }

        let url = try apiURL(path: "/api/v1/search-fulltext/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "query": query,
            "options": ["limit": limit],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HulyError.requestFailed("Search failed")
        }

        // Parse and re-serialize with pretty printing
        let json = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: prettyData, encoding: .utf8) ?? "[]"
    }
}

// MARK: - Errors

enum HulyError: Error, LocalizedError {
    case invalidResponse
    case authenticationFailed(String)
    case notAuthenticated
    case requestFailed(String)
    case notFound(String)
    case invalidConfiguration(String)
    case invalidURL(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .notAuthenticated:
            return "Not authenticated. Call authenticate() first."
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .notFound(let message):
            return message
        case .invalidConfiguration(let message):
            return "Configuration error: \(message)"
        case .invalidURL(let message):
            return "URL error: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}

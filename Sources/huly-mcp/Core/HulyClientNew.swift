//
//  HulyClientNew.swift
//  huly-mcp
//
//  Refactored Huly client implementing ClientProtocol
//  This will eventually replace HulyClient.swift
//

import Foundation
import Logging

public struct HulyConfig: Sendable {
    public let baseURL: String
    public let email: String
    public let password: String
    public let workspace: String

    public init(
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

// Note: We reuse HulyConfig, ServerConfig, LoginInfo, WorkspaceLoginInfo, 
// RPCResponse, and RPCError from HulyClient.swift to avoid duplication

// MARK: - Huly Client Implementation

public actor HulyClientNew: HulyClientProtocol {
    private let config: HulyConfig
    private let session: URLSession
    private let logger: Logger
    
    // Authentication state
    private var accountsURL: String?
    private var token: String?
    private var workspaceToken: String?
    private var workspaceEndpoint: String?
    private var _workspaceId: String?
    private var _accountId: String?
    private var filesURL: String?
    
    // WebSocket client for write operations
    private var webSocketClient: WebSocketClient?
    private var collaboratorURL: String?
    
    public var accountId: String? { _accountId }
    public var workspaceId: String? { _workspaceId }
    public var userId: String? { _accountId }
    
    // Get or create WebSocket client
    func getWebSocketClient() async throws -> WebSocketClient {
        if let client = webSocketClient, await client.connected {
            return client
        }
        
        // Build WebSocket URL from endpoint
        guard let wsEndpoint = workspaceEndpoint else {
            throw HulyError.notAuthenticated
        }
        
        // Convert https to wss
        let wsURLString = wsEndpoint
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        
        guard let wsURL = URL(string: wsURLString) else {
            throw HulyError.invalidURL("Failed to construct WebSocket URL from: \(wsURLString)")
        }
        
        guard let wsId = _workspaceId else {
            throw HulyError.notAuthenticated
        }
        
        let client = WebSocketClient(baseURL: wsURL, workspaceId: wsId)
        try await client.connect()
        
        webSocketClient = client
        return client
    }
    
    public init(config: HulyConfig = HulyConfig()) {
        self.config = config
        self.session = URLSession.shared
        
        var logger = Logger(label: "com.huly.mcp.client")
        logger.logLevel = ProcessInfo.processInfo.environment["DEBUG"] != "0" ? .debug : .info
        self.logger = logger
    }
    
    // MARK: - Authentication
    
    public func authenticate() async throws {
        logger.info("Starting authentication", metadata: ["workspace": "\(config.workspace)"])
        
        // Step 1: Get server config
        logger.debug("Fetching server config")
        var baseURL = config.baseURL
        if baseURL.hasSuffix("/") {
            baseURL = String(baseURL.dropLast())
        }
        guard let configURL = URL(string: "\(baseURL)/config.json") else {
            throw HulyError.invalidConfiguration("Invalid base URL: \(config.baseURL)")
        }
        
        let (configData, configResponse) = try await session.data(from: configURL)
        
        guard let httpResponse = configResponse as? HTTPURLResponse else {
            throw HulyError.authenticationFailed("Invalid response type for server config")
        }
        
        let configString = String(data: configData, encoding: .utf8) ?? "<binary data>"
        logger.debug("Config response received", metadata: [
            "status": "\(httpResponse.statusCode)",
            "url": "\(configURL.absoluteString)",
            "response": "\(configString.prefix(500))"
        ])
        
        guard httpResponse.statusCode == 200 else {
            logger.error("Failed to fetch config", metadata: [
                "status": "\(httpResponse.statusCode)",
                "response": "\(configString)"
            ])
            throw HulyError.authenticationFailed("Failed to fetch server config (status \(httpResponse.statusCode)): \(configString.prefix(200))")
        }
        
        let serverConfig: ServerConfig
        do {
            serverConfig = try JSONDecoder().decode(ServerConfig.self, from: configData)
            self.accountsURL = serverConfig.ACCOUNTS_URL
            self.filesURL = serverConfig.FILES_URL
            logger.debug("Config fetched successfully", metadata: [
                "accounts_url": "\(serverConfig.ACCOUNTS_URL)",
                "files_url": "\(serverConfig.FILES_URL)"
            ])
        } catch {
            logger.error("Failed to decode server config", metadata: [
                "error": "\(error)",
                "raw_data": "\(configString)"
            ])
            throw error
        }
        
        // Step 2: Login via JSON-RPC
        logger.debug("Logging in")
        guard let loginURL = URL(string: serverConfig.ACCOUNTS_URL) else {
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
        self._accountId = loginInfo.account
        
        // Step 3: Select workspace
        var selectRequest = URLRequest(url: loginURL)
        selectRequest.httpMethod = "POST"
        selectRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        selectRequest.setValue("Bearer \(loginInfo.token)", forHTTPHeaderField: "Authorization")
        
        let selectBody: [String: Any] = [
            "method": "selectWorkspace",
            "params": ["workspaceUrl": config.workspace],
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
        self.workspaceEndpoint = wsInfo.endpoint
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        self._workspaceId = wsInfo.workspace
        
        logger.info("Authentication successful", metadata: ["workspace_id": "\(wsInfo.workspace)"])
    }
    
    // MARK: - Helper Methods
    
    private func ensureAuthenticated() async throws {
        if workspaceToken == nil {
            try await authenticate()
        }
    }
    
    private func apiURL(path: String) throws -> URL {
        var endpoint = workspaceEndpoint ?? config.baseURL
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
    
    private func sendTransaction(_ tx: Encodable) async throws {
        try await ensureAuthenticated()
        
        guard let wsId = _workspaceId else {
            throw HulyError.notAuthenticated
        }
        
        let url = try apiURL(path: "/api/v1/tx/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")
        
        // Encode the transaction properly using JSONEncoder
        let encoder = JSONEncoder()
        let txData = try encoder.encode(tx)
        request.httpBody = txData
        
        // Log the transaction for debugging
        if let txString = String(data: txData, encoding: .utf8) {
            logger.info("Sending transaction", metadata: [
                "url": "\(url.absoluteString)",
                "tx_preview": "\(txString.prefix(500))"
            ])
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HulyError.requestFailed("Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Transaction failed", metadata: [
                "status": "\(httpResponse.statusCode)",
                "response": "\(errorBody.prefix(500))"
            ])
            throw HulyError.requestFailed("Transaction failed (status \(httpResponse.statusCode)): \(errorBody)")
        }
        
        logger.info("Transaction successful")
    }
}

// MARK: - Find API Implementation

extension HulyClientNew {
    public func findOne<T: Decodable>(
        _class: String,
        query: [String: Any],
        options: FindOptions? = nil
    ) async throws -> T? {
        let results: [T] = try await findAll(
            _class: _class,
            query: query,
            options: FindOptions(
                limit: 1,
                sort: options?.sort,
                lookup: options?.lookup,
                projection: options?.projection,
                total: options?.total
            )
        )
        return results.first
    }
    
    public func findAll<T: Decodable>(
        _class: String,
        query: [String: Any],
        options: FindOptions? = nil
    ) async throws -> [T] {
        try await ensureAuthenticated()
        
        guard let wsId = _workspaceId else {
            throw HulyError.notAuthenticated
        }
        
        let url = try apiURL(path: "/api/v1/find-all/\(wsId)")
        var request = try authorizedRequest(url: url, method: "POST")
        
        let body: [String: Any] = [
            "_class": _class,
            "query": query,
            "options": (try? options?.asDictionary()) ?? [:],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HulyError.requestFailed("Invalid response type")
        }
        
        // Log the full response for debugging
        let responseString = String(data: data, encoding: .utf8) ?? "<binary data>"
        logger.debug("API Response", metadata: [
            "_class": "\(_class)",
            "status": "\(httpResponse.statusCode)",
            "url": "\(url.absoluteString)",
            "response_preview": "\(responseString.prefix(500))"
        ])
        
        guard httpResponse.statusCode == 200 else {
            logger.error("API request failed", metadata: [
                "status": "\(httpResponse.statusCode)",
                "url": "\(url.absoluteString)",
                "response": "\(responseString.prefix(1000))"
            ])
            throw HulyError.requestFailed("Find query failed with status \(httpResponse.statusCode): \(responseString.prefix(200))")
        }
        
        // Check if response is actually JSON
        guard let jsonString = String(data: data, encoding: .utf8), 
              jsonString.trimmingCharacters(in: .whitespacesAndNewlines).first == "{" || 
              jsonString.trimmingCharacters(in: .whitespacesAndNewlines).first == "[" else {
            logger.error("Response is not JSON", metadata: [
                "content_type": "\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")",
                "response": "\(responseString.prefix(500))"
            ])
            throw HulyError.invalidResponse
        }
        
        do {
            let result = try JSONDecoder().decode(FindAllResponse<T>.self, from: data)
            logger.debug("Successfully decoded response", metadata: ["count": "\(result.value.count)"])
            return result.value
        } catch let error as DecodingError {
            // Enhanced error logging with raw data
            logger.error("Failed to decode response", metadata: [
                "_class": "\(_class)",
                "error": "\(formatDecodingErrorDetailed(error))",
                "raw_data": "\(responseString.prefix(1000))"
            ])
            throw error
        }
    }
    
    private func formatDecodingErrorDetailed(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: ".")): expected \(type)"
        case .valueNotFound(let type, let context):
            return "Missing value of type \(type) at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error)"
        }
    }
}

// MARK: - Documents API Implementation

extension HulyClientNew {
    public func createDoc(
        _class: String,
        space: String,
        attributes: [String: Any],
        id: String? = nil
    ) async throws -> String {
        guard let accountId = _accountId else {
            throw HulyError.notAuthenticated
        }
        
        let objectId = id ?? UUID().uuidString.lowercased()
        
        let tx = TxCreateDoc(
            modifiedBy: accountId,
            createdBy: accountId,
            objectId: objectId,
            objectClass: _class,
            objectSpace: space,
            attributes: attributes
        )
        
        try await sendTransaction(tx)
        return objectId
    }
    
    public func updateDoc(
        _class: String,
        space: String,
        objectId: String,
        operations: [String: Any]
    ) async throws {
        guard let accountId = _accountId else {
            throw HulyError.notAuthenticated
        }
        
        let tx = TxUpdateDoc(
            modifiedBy: accountId,
            objectId: objectId,
            objectClass: _class,
            objectSpace: space,
            operations: operations
        )
        
        try await sendTransaction(tx)
    }
    
    public func removeDoc(
        _class: String,
        space: String,
        objectId: String
    ) async throws {
        guard let accountId = _accountId else {
            throw HulyError.notAuthenticated
        }
        
        let tx = TxRemoveDoc(
            modifiedBy: accountId,
            objectId: objectId,
            objectClass: _class,
            objectSpace: space
        )
        
        try await sendTransaction(tx)
    }
}

// MARK: - Collections API Implementation

extension HulyClientNew {
    public func addCollection(
        _class: String,
        space: String,
        attachedTo: String,
        attachedToClass: String,
        collection: String,
        attributes: [String: Any],
        id: String? = nil
    ) async throws -> String {
        guard let accountId = _accountId else {
            throw HulyError.notAuthenticated
        }
        
        let objectId = id ?? UUID().uuidString.lowercased()
        
        let tx = TxCreateDoc(
            modifiedBy: accountId,
            createdBy: accountId,
            objectId: objectId,
            objectClass: _class,
            objectSpace: space,
            attributes: attributes,
            attachedTo: attachedTo,
            attachedToClass: attachedToClass,
            collection: collection
        )
        
        try await sendTransaction(tx)
        return objectId
    }
    
    public func updateCollection(
        _class: String,
        space: String,
        objectId: String,
        attachedTo: String,
        attachedToClass: String,
        collection: String,
        operations: [String: Any]
    ) async throws {
        // For collections, we just update the document
        try await updateDoc(
            _class: _class,
            space: space,
            objectId: objectId,
            operations: operations
        )
    }
    
    public func removeCollection(
        _class: String,
        space: String,
        objectId: String,
        attachedTo: String,
        attachedToClass: String,
        collection: String
    ) async throws {
        // For collections, we just remove the document
        try await removeDoc(
            _class: _class,
            space: space,
            objectId: objectId
        )
    }
}

// MARK: - Mixins API Implementation

extension HulyClientNew {
    public func createMixin(
        objectId: String,
        objectClass: String,
        objectSpace: String,
        mixin: String,
        attributes: [String: Any]
    ) async throws {
        // Mixins are created via TxMixin transaction
        // For now, we'll use updateDoc as a placeholder
        // TODO: Implement proper TxMixin when needed
        try await updateDoc(
            _class: objectClass,
            space: objectSpace,
            objectId: objectId,
            operations: attributes
        )
    }
    
    public func updateMixin(
        objectId: String,
        objectClass: String,
        objectSpace: String,
        mixin: String,
        operations: [String: Any]
    ) async throws {
        // Update mixin via TxMixin
        // For now, use updateDoc
        try await updateDoc(
            _class: objectClass,
            space: objectSpace,
            objectId: objectId,
            operations: operations
        )
    }
}

// MARK: - Blob Storage Implementation

extension HulyClientNew {
    public func uploadBlob(
        content: String,
        filename: String? = nil
    ) async throws -> String {
        try await ensureAuthenticated()
        
        guard let token = workspaceToken, let wsId = _workspaceId else {
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
        let fname = filename ?? "content"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(content.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HulyError.requestFailed("Failed to upload blob: \(errorBody)")
        }
        
        // Parse response to get blob ID
        // Response format: "blob-id" or {"id": "blob-id"}
        let responseStr = String(data: data, encoding: .utf8) ?? ""
        
        // Try to parse as JSON first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let blobId = json["id"] as? String {
            logger.debug("Blob uploaded", metadata: ["blobId": "\(blobId)"])
            return blobId
        }
        
        // Otherwise, the response itself is the blob ID
        let blobId = responseStr.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        logger.debug("Blob uploaded", metadata: ["blobId": "\(blobId)"])
        return blobId
    }
    
    public func fetchBlob(blobId: String) async throws -> String? {
        guard let filesURLTemplate = filesURL else {
            logger.warning("FILES_URL not configured, cannot fetch blob content")
            return nil
        }
        
        try await ensureAuthenticated()
        
        guard let token = workspaceToken, let wsId = _workspaceId else {
            throw HulyError.notAuthenticated
        }
        
        // Construct the blob URL following Huly's pattern:
        // Both :filename and :blobId should be replaced with the actual blobId
        let urlPath = filesURLTemplate
            .replacingOccurrences(of: ":workspace", with: wsId)
            .replacingOccurrences(of: ":filename", with: blobId)
            .replacingOccurrences(of: ":blobId", with: blobId)
        
        let urlString: String
        if urlPath.hasPrefix("/") {
            // Use base URL if relative path
            var baseURL = config.baseURL
            if baseURL.hasSuffix("/") {
                baseURL = String(baseURL.dropLast())
            }
            urlString = "\(baseURL)\(urlPath)"
        } else {
            urlString = urlPath
        }
        
        logger.info("Fetching blob", metadata: [
            "blobId": "\(blobId)", 
            "url": "\(urlString)"
        ])
        
        guard let url = URL(string: urlString) else {
            logger.error("Failed to construct blob URL", metadata: ["urlString": "\(urlString)"])
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
                let responseBody = String(data: data, encoding: .utf8) ?? "<binary>"
                logger.error("Failed to fetch blob", metadata: [
                    "statusCode": "\(httpResponse.statusCode)",
                    "response": "\(responseBody.prefix(200))"
                ])
                return nil
            }
            
            guard let content = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode blob content as UTF-8")
                return nil
            }
            
            logger.info("Successfully fetched blob", metadata: [
                "blobId": "\(blobId)",
                "size": "\(content.count) chars"
            ])
            
            return content
        } catch {
            logger.error("Error fetching blob", metadata: [
                "error": "\(error.localizedDescription)",
                "blobId": "\(blobId)"
            ])
            return nil
        }
    }
}

// MARK: - Helper Extensions

extension HulyClientNew {
    /// List all projects in the workspace
    public func listProjects() async throws -> [Project] {
        try await ensureAuthenticated()
        
       return try await findAll(
            _class: "tracker:class:Project",
           query: [:],
           options: FindOptions(limit: 50)
        )
    }
    
    public func getProject(identifier: String) async throws -> Project? {
        try await ensureAuthenticated()
        
       return try await findOne(
            _class: "tracker:class:Project",
           query: ["identifier": identifier],
           options: nil
        )
    }
    
    public func listIssues(projectIdentifier: String?, limit: Int) async throws -> [Issue] {
        try await ensureAuthenticated()
        
       var query: [String: Any] = [:]
       if let project = projectIdentifier {
           query["project"] = ["_id": project]  // Assume project identifier is used as lookup
       }
       
       return try await findAll(
            _class: "tracker:class:Issue",
           query: query,
           options: FindOptions(limit: limit)
        )
    }
    
   public func getIssue(identifier: String) async throws -> Issue? {
       try await ensureAuthenticated()
       
       // Use findAll with limit 1 - API may not return identifier in response
       let issues: [Issue] = try await findAll(
            _class: "tracker:class:Issue",
           query: ["identifier": identifier],
           options: FindOptions(limit: 1)
        )
        
        // If we found an issue but it doesn't have identifier, add it from the query
        if let issue = issues.first {
            if issue.identifier == nil {
                // Create a new Issue with the identifier added
                return Issue(
                    _id: issue._id,
                    identifier: identifier,
                    title: issue.title,
                    description: issue.description,
                    priority: issue.priority,
                    status: issue.status
                )
            }
            return issue
        }
        return nil
    }
    
    public func createIssue(
        projectIdentifier: String,
        title: String,
        description: String? = nil,
        priority: Int = 0
    ) async throws -> Issue {
        try await ensureAuthenticated()
        
        // TODO: Proper implementation using createDoc and project space
        // Stub for compilation
        let stubId = "stub-\(UUID().uuidString.prefix(8))"
        return Issue(
            _id: stubId,
            identifier: "\(projectIdentifier)-\(Int.random(in: 1...999))",
            title: title,
            description: description,
            priority: priority,
            status: nil
        )
    }
    
    public func updateIssue(
        identifier: String,
        title: String?,
        description: String?,
        priority: Int?,
        status: String?
    ) async throws -> Issue {
        try await ensureAuthenticated()
        
        // TODO: Proper implementation using updateDoc
        // Stub for compilation
        let stubId = "stub-\(UUID().uuidString.prefix(8))"
        return Issue(
            _id: stubId,
            identifier: identifier,
            title: title ?? "Updated Title",
            description: description,
            priority: priority,
            status: status
        )
    }
    
    public func listPersons(limit: Int) async throws -> [Person] {
        try await ensureAuthenticated()
        
        return try await findAll(
            _class: "contact:class:Person",
            query: [:],
            options: FindOptions(limit: limit)
        )
    }
    
    public func searchFulltext(query: String, limit: Int) async throws -> String {
        try await ensureAuthenticated()
        
        // TODO: Implement full-text search
        return "Search results for '\\(query)' (limit \\(limit)): [stubbed]"
    }
    
    public func listTeamspaces(limit: Int) async throws -> [Teamspace] {
        try await ensureAuthenticated()
        
        return try await findAll(
            _class: "document:class:Teamspace",
            query: [:],
            options: FindOptions(limit: limit)
        )
    }
    
    public func deleteIssue(identifier: String) async throws {
        try await ensureAuthenticated()
        
        // TODO: Find issue and use removeDoc
        // Stub for compilation
    }
    
    public func addLabelToIssue(issueIdentifier: String, labelTitle: String, color: Int) async throws {
        try await ensureAuthenticated()
        
        // TODO: Implement label creation and attach
        // Stub for compilation
    }
    
    public func addCommentToIssue(issueIdentifier: String, message: String) async throws {
        try await ensureAuthenticated()
        
        // TODO: Create chunter.Comment attached to issue
        // Stub for compilation
    }
    
    public func assignIssue(identifier: String, personId: String?) async throws -> Issue {
        try await ensureAuthenticated()
        
        // TODO: Update issue assignee
        // Stub for compilation
        let stubId = "stub-\(UUID().uuidString.prefix(8))"
        return Issue(
            _id: stubId,
            identifier: identifier,
            title: "Assigned Issue",
            description: nil,
            priority: nil,
            status: nil
        )
    }
}

extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HulyError.invalidInput("Failed to convert to dictionary")
        }
        return dictionary
    }
}

//
//  DocumentClient.swift
//  huly-mcp
//
//  High-level Document domain operations with automatic blob handling
//

import Foundation

// MARK: - Document Client Extension

extension HulyClientNew {
    
    // MARK: - Teamspace Operations
    
    /// List all teamspaces
    public func listTeamspaces(
        includeArchived: Bool = false,
        limit: Int = 50
    ) async throws -> [Teamspace] {
        var query: [String: Any] = [:]
        if !includeArchived {
            query["archived"] = false
        }
        
        return try await findAll(
            _class: DocumentClass.teamspace,
            query: query,
            options: FindOptions(limit: limit, sort: nil, lookup: nil, projection: nil, total: nil)
        )
    }
    
    /// Get a teamspace by name
    public func getTeamspace(name: String) async throws -> Teamspace? {
        let teamspaces: [Teamspace] = try await findAll(
            _class: DocumentClass.teamspace,
            query: ["name": name],
            options: FindOptions(limit: 1, sort: nil, lookup: nil, projection: nil, total: nil)
        )
        return teamspaces.first
    }
    
    /// Get a teamspace by ID
    public func getTeamspaceById(id: String) async throws -> Teamspace? {
        return try await findOne(
            _class: DocumentClass.teamspace,
            query: ["_id": id],
            options: nil
        )
    }
    
    // MARK: - Document Operations
    
    /// List documents, optionally filtered by teamspace
    public func listDocuments(
        teamspace: String? = nil,
        parent: String? = nil,
        limit: Int = 50,
        fetchContent: Bool = true
    ) async throws -> [Document] {
        var query: [String: Any] = [:]
        
        if let teamspaceName = teamspace {
            // Look up teamspace by name
            if let ts = try await getTeamspace(name: teamspaceName) {
                query["space"] = ts._id
            } else {
                throw HulyError.notFound("Teamspace '\(teamspaceName)' not found")
            }
        }
        
        if let parent = parent {
            query["parent"] = parent
        }
        
        var documents: [Document] = try await findAll(
            _class: DocumentClass.document,
            query: query,
            options: FindOptions(
                limit: limit,
                sort: ["modifiedOn": .descending],
                lookup: nil,
                projection: nil,
                total: nil
            )
        )
        
        // Automatically fetch blob content if requested
        if fetchContent {
            documents = try await fetchDocumentContents(documents)
        }
        
        return documents
    }
    
    /// Get a document by ID
    public func getDocument(
        id: String,
        fetchContent: Bool = true
    ) async throws -> Document? {
        // Use findAll instead of findOne to get consistent response structure
        let documents: [Document] = try await findAll(
            _class: DocumentClass.document,
            query: ["_id": id],
            options: FindOptions(limit: 1)
        )
        
        guard var document = documents.first else {
            return nil
        }
        
        // If _id is missing from response, inject it from the query parameter
        if document._id.isEmpty {
            document = Document(
                _id: id,
                _class: document._class,
                space: document.space,
                modifiedOn: document.modifiedOn,
                modifiedBy: document.modifiedBy,
                title: document.title,
                name: document.name,
                content: document.content,
                parent: document.parent,
                attachedTo: document.attachedTo,
                attachments: document.attachments,
                children: document.children
            )
        }
        
        // Fetch blob content if needed
        if fetchContent && document.isContentBlob, let blobId = document.contentBlobId {
            if let blobContent = try await fetchBlob(blobId: blobId) {
                document = Document(
                    _id: document._id,
                    _class: document._class,
                    space: document.space,
                    modifiedOn: document.modifiedOn,
                    modifiedBy: document.modifiedBy,
                    title: document.title,
                    name: document.name,
                    content: blobContent,
                    parent: document.parent,
                    attachedTo: document.attachedTo,
                    attachments: document.attachments,
                    children: document.children
                )
            }
        }
        
        return document
    }
    
    /// Create a new document with automatic blob handling for large content
    public func createDocument(
        teamspace: String,
        title: String,
        content: String? = nil,
        parent: String? = nil
    ) async throws -> Document {
        // Look up teamspace
        guard let ts = try await getTeamspace(name: teamspace) else {
            throw HulyError.notFound("Teamspace '\(teamspace)' not found")
        }
        
        var attributes: [String: Any] = [
            "title": title,
            "parent": parent ?? DocumentSpace.noParent,
            "attachments": 0,
            "children": 0
        ]
        
        // Handle content - use blob storage for large content
        if let content = content {
            if shouldUseBlobStorage(content: content) {
                let blobId = try await uploadBlob(content: content, filename: "content")
                attributes["content"] = blobId
            } else {
                attributes["content"] = content
            }
        } else {
            attributes["content"] = ""
        }
        
        let docId = try await createDoc(
            _class: DocumentClass.document,
            space: ts._id,
            attributes: attributes,
            id: nil
        )
        
        // Fetch and return the created document
        guard let document = try await getDocument(id: docId, fetchContent: true) else {
            throw HulyError.requestFailed("Failed to fetch created document")
        }
        
        return document
    }
    
    /// Update a document with automatic blob handling
    public func updateDocument(
        id: String,
        title: String? = nil,
        content: String? = nil
    ) async throws -> Document {
        // Get the existing document to know its space
        guard let existingDoc = try await getDocument(id: id, fetchContent: false) else {
            throw HulyError.notFound("Document '\(id)' not found")
        }
        
        var operations: [String: Any] = [:]
        
        if let title = title {
            operations["title"] = title
        }
        
        // Handle content update - use blob storage for large content
        if let content = content {
            if shouldUseBlobStorage(content: content) {
                let blobId = try await uploadBlob(content: content, filename: "content")
                operations["content"] = blobId
            } else {
                operations["content"] = content
            }
        }
        
        if !operations.isEmpty {
            try await updateDoc(
                _class: DocumentClass.document,
                space: existingDoc.space,
                objectId: id,
                operations: operations
            )
        }
        
        // Fetch and return the updated document
        guard let document = try await getDocument(id: id, fetchContent: true) else {
            throw HulyError.requestFailed("Failed to fetch updated document")
        }
        
        return document
    }
    
    /// Delete a document
    public func deleteDocument(id: String) async throws {
        // Get the document to know its space
        guard let document = try await getDocument(id: id, fetchContent: false) else {
            throw HulyError.notFound("Document '\(id)' not found")
        }
        
        try await removeDoc(
            _class: DocumentClass.document,
            space: document.space,
            objectId: id
        )
    }
    
    /// Move a document to a different parent
    public func moveDocument(
        id: String,
        newParent: String
    ) async throws -> Document {
        guard let document = try await getDocument(id: id, fetchContent: false) else {
            throw HulyError.notFound("Document '\(id)' not found")
        }
        
        try await updateDoc(
            _class: DocumentClass.document,
            space: document.space,
            objectId: id,
            operations: ["parent": newParent]
        )
        
        guard let updated = try await getDocument(id: id, fetchContent: true) else {
            throw HulyError.requestFailed("Failed to fetch moved document")
        }
        
        return updated
    }
    
    // MARK: - Document Attachments
    
    /// List attachments for a document
    public func listDocumentAttachments(
        documentId: String,
        limit: Int = 50
    ) async throws -> [DocumentAttachment] {
        // Query for attached documents in the 'attachments' collection
        return try await findAll(
            _class: "attachment:class:Attachment",
            query: [
                "attachedTo": documentId,
                "attachedToClass": DocumentClass.document
            ],
            options: FindOptions(limit: limit, sort: nil, lookup: nil, projection: nil, total: nil)
        )
    }
    
    /// Add an attachment to a document
    public func addDocumentAttachment(
        documentId: String,
        name: String,
        content: String,
        type: String? = nil
    ) async throws -> String {
        // Get document to know its space
        guard let document = try await getDocument(id: documentId, fetchContent: false) else {
            throw HulyError.notFound("Document '\(documentId)' not found")
        }
        
        // Upload content as blob
        let blobId = try await uploadBlob(content: content, filename: name)
        
        var attributes: [String: Any] = [
            "name": name,
            "file": blobId,
            "size": content.utf8.count
        ]
        
        if let type = type {
            attributes["type"] = type
        }
        
        return try await addCollection(
            _class: "attachment:class:Attachment",
            space: document.space,
            attachedTo: documentId,
            attachedToClass: DocumentClass.document,
            collection: "attachments",
            attributes: attributes,
            id: nil
        )
    }
    
    /// Remove an attachment from a document
    public func removeDocumentAttachment(
        documentId: String,
        attachmentId: String
    ) async throws {
        guard let document = try await getDocument(id: documentId, fetchContent: false) else {
            throw HulyError.notFound("Document '\(documentId)' not found")
        }
        
        try await removeCollection(
            _class: "attachment:class:Attachment",
            space: document.space,
            objectId: attachmentId,
            attachedTo: documentId,
            attachedToClass: DocumentClass.document,
            collection: "attachments"
        )
    }
    
    // MARK: - WebSocket-based Write Operations
    
    /// Create document via WebSocket transaction
    public func createDocumentViaWebSocket(
        teamspace: String,
        title: String,
        content: String?,
        parent: String = "document:ids:NoParent"
    ) async throws -> String {
        // Get or create WebSocket client
        let wsClient = try await getWebSocketClient()
        
        // Get teamspace ID
        let teamspaceObj = try await getTeamspace(name: teamspace)
        guard let teamspaceId = teamspaceObj?._id else {
            throw HulyError.notFound("Teamspace '\(teamspace)' not found")
        }
        
        // Create transaction factory
        guard let userId = self.userId else {
            throw HulyError.notAuthenticated
        }
        let factory = TransactionFactory(userId: userId)
        
        // Build transaction
        let tx = factory.createDocument(
            teamspaceId: teamspaceId,
            title: title,
            content: content,
            parent: parent
        )
        
        // Send transaction
        let response = try await wsClient.sendTransaction(tx)
        
        // Check for errors
        if let error = response.error {
            throw HulyError.serverError(error.code, error.message)
        }
        
        print("✅ Document created successfully: \(tx.objectId)")
        return tx.objectId
    }
    
    /// Update document via WebSocket transaction
    public func updateDocumentViaWebSocket(
        documentId: String,
        teamspaceId: String,
        title: String?,
        content: String?
    ) async throws {
        let wsClient = try await getWebSocketClient()
        
        guard let userId = self.userId else {
            throw HulyError.notAuthenticated
        }
        let factory = TransactionFactory(userId: userId)
        
        let tx = factory.updateDocument(
            documentId: documentId,
            teamspaceId: teamspaceId,
            title: title,
            content: content
        )
        
        let response = try await wsClient.sendTransaction(tx)
        
        if let error = response.error {
            throw HulyError.serverError(error.code, error.message)
        }
        
        print("✅ Document updated successfully: \(documentId)")
    }
    
    /// Delete document via WebSocket transaction
    public func deleteDocumentViaWebSocket(
        documentId: String,
        teamspaceId: String
    ) async throws {
        let wsClient = try await getWebSocketClient()
        
        guard let userId = self.userId else {
            throw HulyError.notAuthenticated
        }
        let factory = TransactionFactory(userId: userId)
        
        let tx = factory.deleteDocument(
            documentId: documentId,
            teamspaceId: teamspaceId
        )
        
        let response = try await wsClient.sendTransaction(tx)
        
        if let error = response.error {
            throw HulyError.serverError(error.code, error.message)
        }
        
        print("✅ Document deleted successfully: \(documentId)")
    }
    
    // MARK: - Helper Methods
    
    /// Determine if content should use blob storage
    private func shouldUseBlobStorage(content: String) -> Bool {
        return content.utf8.count > BlobStorageThreshold
    }
    
    /// Fetch blob content for multiple documents
    private func fetchDocumentContents(_ documents: [Document]) async throws -> [Document] {
        var result: [Document] = []
        
        for document in documents {
            if document.isContentBlob, let blobId = document.contentBlobId {
                if let blobContent = try await fetchBlob(blobId: blobId) {
                    result.append(Document(
                        _id: document._id,
                        _class: document._class,
                        space: document.space,
                        modifiedOn: document.modifiedOn,
                        modifiedBy: document.modifiedBy,
                        title: document.title,
                        name: document.name,
                        content: blobContent,
                        parent: document.parent,
                        attachedTo: document.attachedTo,
                        attachments: document.attachments,
                        children: document.children
                    ))
                } else {
                    // Keep original with blob ID if fetch fails
                    result.append(document)
                }
            } else {
                result.append(document)
            }
        }
        
        return result
    }
}

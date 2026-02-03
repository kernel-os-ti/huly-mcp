//
//  ClientProtocol.swift
//  huly-mcp
//
//  Client protocol matching @hcengineering/api-client interface
//

import Foundation

/// Main Huly client protocol matching the JavaScript API client
public protocol HulyClientProtocol: Actor {
    
    // MARK: - Authentication
    
    /// Authenticate with the Huly server
    func authenticate() async throws
    
    /// Current account ID (after authentication)
    var accountId: String? { get async }
    
    /// Current workspace ID (after authentication)
    var workspaceId: String? { get async }
    
    // MARK: - Find API
    
    /// Find a single document matching the query
    /// - Parameters:
    ///   - _class: Class of the object to find (results include subclasses)
    ///   - query: Query criteria
    ///   - options: Find options (limit, sort, lookup, projection, total)
    /// - Returns: First matching document or nil
    func findOne<T: Decodable>(
        _class: String,
        query: [String: Any],
        options: FindOptions?
    ) async throws -> T?
    
    /// Find all documents matching the query
    /// - Parameters:
    ///   - _class: Class of the object to find (results include subclasses)
    ///   - query: Query criteria
    ///   - options: Find options (limit, sort, lookup, projection, total)
    /// - Returns: Array of matching documents
    func findAll<T: Decodable>(
        _class: String,
        query: [String: Any],
        options: FindOptions?
    ) async throws -> [T]
    
    // MARK: - Documents API
    
    /// Create a new document
    /// - Parameters:
    ///   - _class: Class of the object
    ///   - space: Space of the object
    ///   - attributes: Attributes of the object
    ///   - id: Optional ID (will be generated if not provided)
    /// - Returns: ID of the created document
    func createDoc(
        _class: String,
        space: String,
        attributes: [String: Any],
        id: String?
    ) async throws -> String
    
    /// Update an existing document
    /// - Parameters:
    ///   - _class: Class of the object
    ///   - space: Space of the object
    ///   - objectId: ID of the object to update
    ///   - operations: Attributes to update
    func updateDoc(
        _class: String,
        space: String,
        objectId: String,
        operations: [String: Any]
    ) async throws
    
    /// Remove a document
    /// - Parameters:
    ///   - _class: Class of the object
    ///   - space: Space of the object
    ///   - objectId: ID of the object to remove
    func removeDoc(
        _class: String,
        space: String,
        objectId: String
    ) async throws
    
    // MARK: - Collections API
    
    /// Add an item to a collection (create attached document)
    /// - Parameters:
    ///   - _class: Class of the object to create
    ///   - space: Space of the object
    ///   - attachedTo: ID of the parent object
    ///   - attachedToClass: Class of the parent object
    ///   - collection: Name of the collection
    ///   - attributes: Attributes of the object
    ///   - id: Optional ID (will be generated if not provided)
    /// - Returns: ID of the created document
    func addCollection(
        _class: String,
        space: String,
        attachedTo: String,
        attachedToClass: String,
        collection: String,
        attributes: [String: Any],
        id: String?
    ) async throws -> String
    
    /// Update an item in a collection
    /// - Parameters:
    ///   - _class: Class of the object
    ///   - space: Space of the object
    ///   - objectId: ID of the object to update
    ///   - attachedTo: ID of the parent object
    ///   - attachedToClass: Class of the parent object
    ///   - collection: Name of the collection
    ///   - operations: Attributes to update
    func updateCollection(
        _class: String,
        space: String,
        objectId: String,
        attachedTo: String,
        attachedToClass: String,
        collection: String,
        operations: [String: Any]
    ) async throws
    
    /// Remove an item from a collection
    /// - Parameters:
    ///   - _class: Class of the object
    ///   - space: Space of the object
    ///   - objectId: ID of the object to remove
    ///   - attachedTo: ID of the parent object
    ///   - attachedToClass: Class of the parent object
    ///   - collection: Name of the collection
    func removeCollection(
        _class: String,
        space: String,
        objectId: String,
        attachedTo: String,
        attachedToClass: String,
        collection: String
    ) async throws
    
    // MARK: - Mixins API
    
    /// Create a mixin for a document
    /// - Parameters:
    ///   - objectId: ID of the object to attach mixin to
    ///   - objectClass: Class of the object
    ///   - objectSpace: Space of the object
    ///   - mixin: Mixin class to create
    ///   - attributes: Mixin attributes
    func createMixin(
        objectId: String,
        objectClass: String,
        objectSpace: String,
        mixin: String,
        attributes: [String: Any]
    ) async throws
    
    /// Update a mixin on a document
    /// - Parameters:
    ///   - objectId: ID of the object
    ///   - objectClass: Class of the object
    ///   - objectSpace: Space of the object
    ///   - mixin: Mixin class to update
    ///   - operations: Attributes to update
    func updateMixin(
        objectId: String,
        objectClass: String,
        objectSpace: String,
        mixin: String,
        operations: [String: Any]
    ) async throws
    
    // MARK: - Blob Storage
    
    /// Upload content as a blob
    /// - Parameters:
    ///   - content: Content to upload
    ///   - filename: Optional filename
    /// - Returns: Blob ID
    func uploadBlob(
        content: String,
        filename: String?
    ) async throws -> String
    
    /// Fetch blob content
    /// - Parameter blobId: ID of the blob
    /// - Returns: Blob content as string
    func fetchBlob(
        blobId: String
    ) async throws -> String?
}

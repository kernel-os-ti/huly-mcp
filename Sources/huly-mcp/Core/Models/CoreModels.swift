//
//  CoreModels.swift
//  huly-mcp
//
//  Core Huly Platform data models matching @hcengineering/core
//

import Foundation

// MARK: - Reference Types

/// Huly Ref - unique identifier for objects
public typealias Ref<T> = String

/// Timestamp in milliseconds since epoch
public typealias Timestamp = Int

// MARK: - Core Classes

/// Base class for all Huly objects
public protocol Doc: Codable, Sendable {
    var _id: String { get }
    var _class: String { get }
    var space: String { get }
    var modifiedOn: Timestamp? { get }
    var modifiedBy: String? { get }
}

/// Attached document (part of a collection)
public protocol AttachedDoc: Doc {
    var attachedTo: String { get }
    var attachedToClass: String { get }
    var collection: String { get }
}

// MARK: - Query Options

public struct FindOptions: Encodable {
    public let limit: Int?
    public let sort: [String: SortingOrder]?
    public let lookup: [String: Any]?
    public let projection: [String: Int]?
    public let total: Bool?
    
    public init(
        limit: Int? = nil,
        sort: [String: SortingOrder]? = nil,
        lookup: [String: Any]? = nil,
        projection: [String: Int]? = nil,
        total: Bool? = nil
    ) {
        self.limit = limit
        self.sort = sort
        self.lookup = lookup
        self.projection = projection
        self.total = total
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(sort, forKey: .sort)
        try container.encodeIfPresent(total, forKey: .total)
        // Note: lookup and projection contain Any, need custom encoding if used
    }
    
    private enum CodingKeys: String, CodingKey {
        case limit, sort, lookup, projection, total
    }
}

public enum SortingOrder: Int, Codable {
    case ascending = 1
    case descending = -1
}

// MARK: - Response Wrappers

// Note: FindAllResponse is defined in HulyClient.swift to avoid redeclaration

// MARK: - Core Class Names

public enum CoreClass {
    public static let tx = "core:class:Tx"
    public static let txCreateDoc = "core:class:TxCreateDoc"
    public static let txUpdateDoc = "core:class:TxUpdateDoc"
    public static let txRemoveDoc = "core:class:TxRemoveDoc"
    public static let doc = "core:class:Doc"
    public static let attachedDoc = "core:class:AttachedDoc"
    public static let space = "core:class:Space"
}

public enum CoreSpace {
    public static let tx = "core:space:Tx"
    public static let space = "core:space:Space"
}

// MARK: - Blob Storage

/// Blob reference (content stored externally)
public struct BlobRef: Codable, Sendable {
    public let id: String
    public let name: String?
    public let size: Int?
    public let type: String?
    
    public init(id: String, name: String? = nil, size: Int? = nil, type: String? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.type = type
    }
}

/// Threshold for using blob storage (10KB)
public let BlobStorageThreshold = 10_240

// MARK: - Auth Models (from HulyClient.swift)

/// Server configuration from /config.json
public struct ServerConfig: Codable, Sendable {
    public let ACCOUNTS_URL: String
    public let FILES_URL: String
}

/// RPC response wrapper for auth endpoints
public struct RPCResponse<T: Decodable>: Decodable {
    public let result: T?
    public let error: RPCError?
}

/// RPC error from auth endpoints
public struct RPCError: Codable {
    public let code: String
    public let message: String?
}

/// Login response info
public struct LoginInfo: Codable, Sendable {
    public let token: String
    public let account: String
}

/// Workspace login response info
public struct WorkspaceLoginInfo: Codable, Sendable {
    public let token: String
    public let endpoint: String
    public let workspace: String
}

/// FindAll response wrapper
public struct FindAllResponse<T: Decodable>: Decodable {
    public let value: [T]
}

/// Project model - matches Huly's project.Project class
/// Made flexible to handle various fields the API may return
public struct Project: Codable, Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let name: String
    public let identifier: String?
    public let description: String?
    public let modifiedOn: Timestamp?
    public let modifiedBy: String?
    public let createdOn: Timestamp?
    public let createdBy: String?
    
    // Use CodingKeys to handle optional fields gracefully
    private enum CodingKeys: String, CodingKey {
        case _id, _class, space, name, identifier, description
        case modifiedOn, modifiedBy, createdOn, createdBy
    }
    
    // Custom decoder that allows missing optional fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        _class = try container.decode(String.self, forKey: ._class)
        space = try container.decode(String.self, forKey: .space)
        name = try container.decode(String.self, forKey: .name)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        modifiedOn = try container.decodeIfPresent(Timestamp.self, forKey: .modifiedOn)
        modifiedBy = try container.decodeIfPresent(String.self, forKey: .modifiedBy)
        createdOn = try container.decodeIfPresent(Timestamp.self, forKey: .createdOn)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
    }
}

/// Minimal Issue model
public struct Issue: Codable, Sendable {
    public let _id: String
    public let identifier: String?
    public let title: String
    public let description: String?
    public let priority: Int?
    public let status: String?
    
    public init(
        _id: String,
        identifier: String?,
        title: String,
        description: String? = nil,
        priority: Int? = nil,
        status: String? = nil
    ) {
        self._id = _id
        self.identifier = identifier
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, identifier, title, description, priority, status
    }
}

/// Minimal Person model
public struct Person: Codable, Sendable {
    public let _id: String
    public let name: String
    public let email: String?
}





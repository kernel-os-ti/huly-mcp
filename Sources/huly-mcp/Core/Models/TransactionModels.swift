//
//  TransactionModels.swift
//  huly-mcp
//
//  Transaction models for Huly Platform operations
//

import Foundation

// MARK: - Transaction Base

/// Base transaction type (only needs to be encodable for sending to server)
public protocol Tx: Encodable {
    var _id: String { get }
    var _class: String { get }
    var space: String { get }
    var modifiedOn: Timestamp { get }
    var modifiedBy: String { get }
}

// MARK: - Document Transactions

/// Transaction to create a new document
public struct TxCreateDoc: Tx, Encodable, @unchecked Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let modifiedOn: Timestamp
    public let modifiedBy: String
    public let createdOn: Timestamp
    public let createdBy: String
    public let objectId: String
    public let objectClass: String
    public let objectSpace: String
    public let attributes: [String: Any]
    
    // Optional for attached documents
    public let attachedTo: String?
    public let attachedToClass: String?
    public let collection: String?
    
    public init(
        id: String = UUID().uuidString.lowercased(),
        modifiedOn: Timestamp = Timestamp(Date().timeIntervalSince1970 * 1000),
        modifiedBy: String,
        createdOn: Timestamp? = nil,
        createdBy: String? = nil,
        objectId: String,
        objectClass: String,
        objectSpace: String,
        attributes: [String: Any],
        attachedTo: String? = nil,
        attachedToClass: String? = nil,
        collection: String? = nil
    ) {
        self._id = id
        self._class = CoreClass.txCreateDoc
        self.space = CoreSpace.tx
        self.modifiedOn = modifiedOn
        self.modifiedBy = modifiedBy
        self.createdOn = createdOn ?? modifiedOn
        self.createdBy = createdBy ?? modifiedBy
        self.objectId = objectId
        self.objectClass = objectClass
        self.objectSpace = objectSpace
        self.attributes = attributes
        self.attachedTo = attachedTo
        self.attachedToClass = attachedToClass
        self.collection = collection
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(_class, forKey: ._class)
        try container.encode(space, forKey: .space)
        try container.encode(modifiedOn, forKey: .modifiedOn)
        try container.encode(modifiedBy, forKey: .modifiedBy)
        try container.encode(createdOn, forKey: .createdOn)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(objectId, forKey: .objectId)
        try container.encode(objectClass, forKey: .objectClass)
        try container.encode(objectSpace, forKey: .objectSpace)
        
        // Encode attributes by converting to AnyCodable
        let convertedAttributes = attributes.mapValues { AnyCodable($0) }
        try container.encode(convertedAttributes, forKey: .attributes)
        
        try container.encodeIfPresent(attachedTo, forKey: .attachedTo)
        try container.encodeIfPresent(attachedToClass, forKey: .attachedToClass)
        try container.encodeIfPresent(collection, forKey: .collection)
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy, createdOn, createdBy
        case objectId, objectClass, objectSpace, attributes
        case attachedTo, attachedToClass, collection
    }
}

/// Transaction to update an existing document
public struct TxUpdateDoc: Tx, Encodable, @unchecked Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let modifiedOn: Timestamp
    public let modifiedBy: String
    public let objectId: String
    public let objectClass: String
    public let objectSpace: String
    public let operations: [String: Any]
    
    public init(
        id: String = UUID().uuidString.lowercased(),
        modifiedOn: Timestamp = Timestamp(Date().timeIntervalSince1970 * 1000),
        modifiedBy: String,
        objectId: String,
        objectClass: String,
        objectSpace: String,
        operations: [String: Any]
    ) {
        self._id = id
        self._class = CoreClass.txUpdateDoc
        self.space = CoreSpace.tx
        self.modifiedOn = modifiedOn
        self.modifiedBy = modifiedBy
        self.objectId = objectId
        self.objectClass = objectClass
        self.objectSpace = objectSpace
        self.operations = operations
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(_class, forKey: ._class)
        try container.encode(space, forKey: .space)
        try container.encode(modifiedOn, forKey: .modifiedOn)
        try container.encode(modifiedBy, forKey: .modifiedBy)
        try container.encode(objectId, forKey: .objectId)
        try container.encode(objectClass, forKey: .objectClass)
        try container.encode(objectSpace, forKey: .objectSpace)
        
        // Encode operations by converting to AnyCodable
        let convertedOperations = operations.mapValues { AnyCodable($0) }
        try container.encode(convertedOperations, forKey: .operations)
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy
        case objectId, objectClass, objectSpace, operations
    }
}

/// Transaction to remove a document
public struct TxRemoveDoc: Tx, Encodable, @unchecked Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let modifiedOn: Timestamp
    public let modifiedBy: String
    public let objectId: String
    public let objectClass: String
    public let objectSpace: String
    
    public init(
        id: String = UUID().uuidString.lowercased(),
        modifiedOn: Timestamp = Timestamp(Date().timeIntervalSince1970 * 1000),
        modifiedBy: String,
        objectId: String,
        objectClass: String,
        objectSpace: String
    ) {
        self._id = id
        self._class = CoreClass.txRemoveDoc
        self.space = CoreSpace.tx
        self.modifiedOn = modifiedOn
        self.modifiedBy = modifiedBy
        self.objectId = objectId
        self.objectClass = objectClass
        self.objectSpace = objectSpace
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy
        case objectId, objectClass, objectSpace
    }
}

// MARK: - Helper for Any encoding

private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
}

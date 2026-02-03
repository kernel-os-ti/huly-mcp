//
//  DocumentModels.swift
//  huly-mcp
//
//  Document domain models matching document:class:* types
//

import Foundation

// MARK: - Document Classes

public enum DocumentClass {
    public static let document = "document:class:Document"
    public static let teamspace = "document:class:Teamspace"
}

public enum DocumentSpace {
    public static let noParent = "document:ids:NoParent"
}

// MARK: - Document Model

public struct Document: Codable, Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let modifiedOn: Timestamp?
    public let modifiedBy: String?
    
    // Document-specific fields
    public let title: String?
    public let name: String?  // Some documents may use 'name' instead of 'title'
    public let content: String?
    public let parent: String?
    public let attachedTo: String?
    public let attachments: Int?
    public let children: Int?
    
    public init(
        _id: String,
        _class: String = DocumentClass.document,
        space: String,
        modifiedOn: Timestamp? = nil,
        modifiedBy: String? = nil,
        title: String? = nil,
        name: String? = nil,
        content: String? = nil,
        parent: String? = nil,
        attachedTo: String? = nil,
        attachments: Int? = nil,
        children: Int? = nil
    ) {
        self._id = _id
        self._class = _class
        self.space = space
        self.modifiedOn = modifiedOn
        self.modifiedBy = modifiedBy
        self.title = title
        self.name = name
        self.content = content
        self.parent = parent
        self.attachedTo = attachedTo
        self.attachments = attachments
        self.children = children
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Use decodeIfPresent for all fields to handle API inconsistencies
        _id = try container.decodeIfPresent(String.self, forKey: ._id) ?? ""
        _class = try container.decodeIfPresent(String.self, forKey: ._class) ?? DocumentClass.document
        space = try container.decodeIfPresent(String.self, forKey: .space) ?? ""
        modifiedOn = try container.decodeIfPresent(Timestamp.self, forKey: .modifiedOn)
        modifiedBy = try container.decodeIfPresent(String.self, forKey: .modifiedBy)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        attachedTo = try container.decodeIfPresent(String.self, forKey: .attachedTo)
        attachments = try container.decodeIfPresent(Int.self, forKey: .attachments)
        children = try container.decodeIfPresent(Int.self, forKey: .children)
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy
        case title, name, content, parent, attachedTo, attachments, children
    }
    
    /// Get the display name (prefer title over name)
    public var displayName: String {
        return title ?? name ?? "Untitled"
    }
    
    /// Check if content is a blob reference
    public var isContentBlob: Bool {
        content?.contains("-content-") ?? false
    }
    
    /// Get blob ID if content is a blob reference
    public var contentBlobId: String? {
        isContentBlob ? content : nil
    }
}

// MARK: - Teamspace Model

public struct Teamspace: Codable, Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let modifiedOn: Timestamp?
    public let modifiedBy: String?
    
    // Teamspace-specific fields
    public let name: String
    public let description: String?
    public let archived: Bool?
    public let private_: Bool?
    
    public init(
        _id: String,
        _class: String = DocumentClass.teamspace,
        space: String,
        modifiedOn: Timestamp? = nil,
        modifiedBy: String? = nil,
        name: String,
        description: String? = nil,
        archived: Bool? = nil,
        private_: Bool? = nil
    ) {
        self._id = _id
        self._class = _class
        self.space = space
        self.modifiedOn = modifiedOn
        self.modifiedBy = modifiedBy
        self.name = name
        self.description = description
        self.archived = archived
        self.private_ = private_
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Use decodeIfPresent for flexibility with API responses
        _id = try container.decodeIfPresent(String.self, forKey: ._id) ?? ""
        _class = try container.decodeIfPresent(String.self, forKey: ._class) ?? DocumentClass.teamspace
        space = try container.decodeIfPresent(String.self, forKey: .space) ?? ""
        modifiedOn = try container.decodeIfPresent(Timestamp.self, forKey: .modifiedOn)
        modifiedBy = try container.decodeIfPresent(String.self, forKey: .modifiedBy)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        private_ = try container.decodeIfPresent(Bool.self, forKey: .private_)
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy
        case name, description, archived
        case private_ = "private"
    }
}

// MARK: - Document Attachment Model

public struct DocumentAttachment: Codable, Sendable {
    public let _id: String
    public let _class: String
    public let space: String
    public let modifiedOn: Timestamp?
    public let modifiedBy: String?
    
    // Attached document fields
    public let attachedTo: String
    public let attachedToClass: String
    public let collection: String
    
    // Attachment-specific fields
    public let name: String
    public let file: String // Blob reference
    public let type: String?
    public let size: Int?
    
    public init(
        _id: String,
        _class: String,
        space: String,
        modifiedOn: Timestamp? = nil,
        modifiedBy: String? = nil,
        attachedTo: String,
        attachedToClass: String,
        collection: String,
        name: String,
        file: String,
        type: String? = nil,
        size: Int? = nil
    ) {
        self._id = _id
        self._class = _class
        self.space = space
        self.modifiedOn = modifiedOn
        self.modifiedBy = modifiedBy
        self.attachedTo = attachedTo
        self.attachedToClass = attachedToClass
        self.collection = collection
        self.name = name
        self.file = file
        self.type = type
        self.size = size
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy
        case attachedTo, attachedToClass, collection
        case name, file, type, size
    }
}

import Foundation

// Copy the transaction models
struct Timestamp: Codable {
    let value: Int64
    
    init(_ value: Double) {
        self.value = Int64(value)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct CoreClass {
    static let txCreateDoc = "core:class:TxCreateDoc"
}

struct CoreSpace {
    static let tx = "core:space:Tx"
}

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
        default:
            try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        value = ""
    }
}

struct TxCreateDoc: Encodable {
    let _id: String
    let _class: String
    let space: String
    let modifiedOn: Timestamp
    let modifiedBy: String
    let createdOn: Timestamp
    let createdBy: String
    let objectId: String
    let objectClass: String
    let objectSpace: String
    let attributes: [String: Any]
    
    func encode(to encoder: Encoder) throws {
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
        
        let convertedAttributes = attributes.mapValues { AnyCodable($0) }
        try container.encode(convertedAttributes, forKey: .attributes)
    }
    
    enum CodingKeys: String, CodingKey {
        case _id, _class, space, modifiedOn, modifiedBy, createdOn, createdBy
        case objectId, objectClass, objectSpace, attributes
    }
}

// Create a test transaction
let tx = TxCreateDoc(
    _id: "test-tx-123",
    _class: CoreClass.txCreateDoc,
    space: CoreSpace.tx,
    modifiedOn: Timestamp(Date().timeIntervalSince1970 * 1000),
    modifiedBy: "1110107082410557441",
    createdOn: Timestamp(Date().timeIntervalSince1970 * 1000),
    createdBy: "1110107082410557441",
    objectId: "test-doc-456",
    objectClass: "document:class:Document",
    objectSpace: "68af966cbe25d6a2d5740e91",
    attributes: [
        "title": "Test Document",
        "parent": "document:ids:NoParent",
        "content": "Test content",
        "attachments": 0,
        "children": 0
    ]
)

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
let data = try encoder.encode(tx)
print(String(data: data, encoding: .utf8)!)

import Foundation

/// Factory for creating Huly transactions
class TransactionFactory {
    let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    // MARK: - Document Transactions
    
    func createDocument(
        teamspaceId: String,
        title: String,
        content: String?,
        parent: String?
    ) -> TxCreateDoc {
        let docId = "document:\(UUID().uuidString.lowercased())"
        
        var attributes: [String: Any] = [
            "title": title,
            "name": title,
            "parent": parent ?? "document:ids:NoParent",
            "attachments": 0,
            "children": 0
        ]
        
        if let content = content {
            attributes["content"] = content
        } else {
            attributes["content"] = ""
        }
        
        return TxCreateDoc(
            modifiedBy: userId,
            createdBy: userId,
            objectId: docId,
            objectClass: DocumentClass.document,
            objectSpace: teamspaceId,
            attributes: attributes
        )
    }
    
    func updateDocument(
        documentId: String,
        teamspaceId: String,
        title: String?,
        content: String?
    ) -> TxUpdateDoc {
        var operations: [String: Any] = [:]
        
        if let title = title {
            operations["title"] = title
            operations["name"] = title
        }
        
        if let content = content {
            operations["content"] = content
        }
        
        return TxUpdateDoc(
            modifiedBy: userId,
            objectId: documentId,
            objectClass: DocumentClass.document,
            objectSpace: teamspaceId,
            operations: operations
        )
    }
    
    func deleteDocument(
        documentId: String,
        teamspaceId: String
    ) -> TxRemoveDoc {
        return TxRemoveDoc(
            modifiedBy: userId,
            objectId: documentId,
            objectClass: DocumentClass.document,
            objectSpace: teamspaceId
        )
    }
}

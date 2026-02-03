import Foundation

/// WebSocket client for Huly platform communication
actor WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var isConnected = false
    private var pendingRequests: [Int: CheckedContinuation<TransactionResponse, Error>] = [:]
    private var currentRequestId = 0
    private var receiveTask: Task<Void, Never>?
    
    let baseURL: URL
    let workspaceId: String
    
    var url: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sessionId", value: UUID().uuidString)]
        return components.url!
    }
    
    init(baseURL: URL, workspaceId: String) {
        self.baseURL = baseURL
        self.workspaceId = workspaceId
        self.session = URLSession(configuration: .default)
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard !isConnected else { return }
        
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveTask = Task {
            await receiveMessages()
        }
        
        // Send hello handshake
        let hello = HelloRequest(method: "hello", params: [], id: -1)
        let encoder = JSONEncoder()
        let data = try encoder.encode(hello)
        let message = URLSessionWebSocketTask.Message.data(data)
        
        try await webSocketTask?.send(message)
        
        // Wait for hello response
        let response: HelloResponse = try await withTimeout(seconds: 10) {
            try await self.receiveHelloResponse()
        }
        
        isConnected = true
        print("WebSocket connected: \(response)")
    }
    
    func disconnect() async {
        isConnected = false
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: HulyError.connectionClosed)
        }
        pendingRequests.removeAll()
    }
    
    var connected: Bool {
        isConnected
    }
    
    // MARK: - Transaction Handling
    
    func sendTransaction(_ tx: Tx) async throws -> TransactionResponse {
        guard isConnected else {
            throw HulyError.notConnected
        }
        
        currentRequestId += 1
        let requestId = currentRequestId
        
        let request = TransactionRequest(
            method: "tx",
            params: [AnyEncodable(tx)],
            id: requestId
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let message = URLSessionWebSocketTask.Message.data(data)
        
        return try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.registerRequest(id: requestId, continuation: continuation)
                    try await self.webSocketTask?.send(message)
                }
            }
        }
    }
    
    private func registerRequest(id: Int, continuation: CheckedContinuation<TransactionResponse, Error>) {
        pendingRequests[id] = continuation
    }
    
    // MARK: - Message Receiving
    
    private func receiveMessages() async {
        while isConnected {
            do {
                guard let message = try await webSocketTask?.receive() else {
                    break
                }
                
                switch message {
                case .data(let data):
                    await handleMessage(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        await handleMessage(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                print("WebSocket receive error: \(error)")
                break
            }
        }
    }
    
    private func handleMessage(_ data: Data) async {
        do {
            let decoder = JSONDecoder()
            
            // Try to decode as transaction response
            if let response = try? decoder.decode(TransactionResponse.self, from: data) {
                if let continuation = pendingRequests.removeValue(forKey: response.id) {
                    if let error = response.error {
                        continuation.resume(throwing: HulyError.serverError(error.code, error.message))
                    } else {
                        continuation.resume(returning: response)
                    }
                }
                return
            }
            
            // Try to decode as hello response (id: -1)
            if let hello = try? decoder.decode(HelloResponse.self, from: data) {
                print("Hello response: \(hello)")
                return
            }
            
            print("Unknown message format: \(String(data: data, encoding: .utf8) ?? "invalid")")
        }
    }
    
    private func receiveHelloResponse() async throws -> HelloResponse {
        guard let message = try await webSocketTask?.receive() else {
            throw HulyError.connectionClosed
        }
        
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let text):
            guard let d = text.data(using: .utf8) else {
                throw HulyError.invalidResponse
            }
            data = d
        @unknown default:
            throw HulyError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(HelloResponse.self, from: data)
    }
}

// MARK: - Helper Functions

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw HulyError.timeout
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Message Models

struct HelloRequest: Encodable {
    let method: String
    let params: [String]
    let id: Int
}

struct HelloResponse: Decodable {
    let id: Int
    let result: HelloResult
    
    struct HelloResult: Decodable {
        let binary: Bool
        let reconnect: Bool?
        let session: String?
    }
}

struct TransactionRequest: Encodable {
    let method: String
    let params: [AnyEncodable]
    let id: Int
}

struct TransactionResponse: Decodable {
    let id: Int
    let error: WSErrorResponse?
    
    enum CodingKeys: String, CodingKey {
        case id, error, result
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        error = try? container.decode(WSErrorResponse.self, forKey: .error)
        // We don't need to decode result for now
    }
}

struct WSErrorResponse: Codable {
    let code: String
    let message: String
}

// MARK: - AnyEncodable Helper

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    
    init<T: Encodable>(_ value: T) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

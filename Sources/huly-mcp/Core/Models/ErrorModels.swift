// ErrorModels.swift
// Shared error types for Huly MCP client

import Foundation

public enum HulyError: Error, LocalizedError {
    case invalidResponse
    case authenticationFailed(String)
    case notAuthenticated
    case requestFailed(String)
    case notFound(String)
    case invalidConfiguration(String)
    case invalidURL(String)
    case invalidInput(String)
    case notConnected
    case connectionClosed
    case timeout
    case serverError(String, String)

    public var errorDescription: String? {
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
        case .notConnected:
            return "WebSocket not connected"
        case .connectionClosed:
            return "WebSocket connection closed"
        case .timeout:
            return "Operation timed out"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

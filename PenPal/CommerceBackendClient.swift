import Foundation
import FirebaseAuth
import FirebaseCore

// MARK: Monetization Foundation

enum CommerceBackendClientError: Error, LocalizedError {
    case notSignedIn
    case missingProjectID
    case invalidResponse
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You need to be signed in."
        case .missingProjectID:
            return "Firebase project configuration is missing."
        case .invalidResponse:
            return "The payment server returned an invalid response."
        case .backend(let message):
            return message
        }
    }
}

final class CommerceBackendClient {
    static let shared = CommerceBackendClient()

    private let region = "us-central1"
    private init() {}

    func getOrCreateAppAccountToken() async throws -> UUID {
        let response = try await callFunction(
            "getOrCreateAppAccountToken",
            payload: [:]
        )

        guard let rawToken = response["appAccountToken"] as? String,
              let token = UUID(uuidString: rawToken) else {
            throw CommerceBackendClientError.invalidResponse
        }

        return token
    }

    func processAppStoreTransaction(signedTransactionInfo: String) async throws {
        _ = try await callFunction(
            "processAppStoreTransaction",
            payload: ["signedTransactionInfo": signedTransactionInfo]
        )
    }

    func reconcileAppStoreEntitlements() async throws {
        _ = try await callFunction(
            "reconcileAppStoreEntitlements",
            payload: [:]
        )
    }

    func deleteMyAccountData() async throws {
        _ = try await callFunction("deleteMyAccountData", payload: [:])
    }

    private func callFunction(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else {
            throw CommerceBackendClientError.notSignedIn
        }

        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://\(region)-\(projectID).cloudfunctions.net/\(name)") else {
            throw CommerceBackendClientError.missingProjectID
        }

        let idToken = try await idToken(for: user)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommerceBackendClientError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if (200..<300).contains(httpResponse.statusCode),
           let result = object?["result"] as? [String: Any] {
            return result
        }

        if let error = object?["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw CommerceBackendClientError.backend(message)
        }

        throw CommerceBackendClientError.invalidResponse
    }

    private func idToken(for user: User) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: CommerceBackendClientError.notSignedIn)
                }
            }
        }
    }
}

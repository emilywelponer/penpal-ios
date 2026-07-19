import Foundation
import FirebaseAuth

enum AuthTokenRefreshOutcome {
    case valid
    case invalidUser
    case transientFailure
}

enum AuthEventTracker {
    private static let queue = DispatchQueue(label: "penpal.auth-events")
    private static var lastAction: (name: String, date: Date)?

    static func record(_ action: String) {
        queue.sync {
            lastAction = (action, Date())
        }
        print(action)
    }

    static func recentActionSummary(limit: TimeInterval = 10) -> String {
        queue.sync {
            guard let lastAction else { return "none" }
            let elapsed = Date().timeIntervalSince(lastAction.date)
            guard elapsed <= limit else {
                return "none recent; last=\(lastAction.name) \(Int(elapsed))s ago"
            }
            return "\(lastAction.name) \(String(format: "%.1f", elapsed))s ago"
        }
    }

    static func logTokenResult(
        context: String,
        completion: ((AuthTokenRefreshOutcome) -> Void)? = nil
    ) {
        guard let user = Auth.auth().currentUser else {
            print("TOKEN_REFRESH_FAILURE", context, "no current user")
            completion?(.invalidUser)
            return
        }

        print("TOKEN_REFRESH_START", context, user.uid)
        user.getIDTokenResult(forcingRefresh: true) { result, error in
            if let error {
                print("TOKEN_REFRESH_FAILURE", context, error.localizedDescription)
                let code = (error as NSError).code
                let invalidUserCodes = [
                    AuthErrorCode.userNotFound.rawValue,
                    AuthErrorCode.userDisabled.rawValue,
                    AuthErrorCode.invalidUserToken.rawValue,
                    AuthErrorCode.userTokenExpired.rawValue
                ]
                completion?(invalidUserCodes.contains(code) ? .invalidUser : .transientFailure)
                return
            }

            print("TOKEN_REFRESH_SUCCESS", context, user.uid)
            if let result {
                print("TOKEN_REFRESH_SUCCESS issueDate", result.issuedAtDate)
                print("TOKEN_REFRESH_SUCCESS expirationDate", result.expirationDate)
            }
            completion?(.valid)
        }
    }
}

import Foundation

/// Decides which header values are secrets (API keys, tokens, cookies) that the UI hides by default.
public enum SensitiveHeaders {
    private static let exactNames: Set<String> = ["authorization", "proxyauthorization", "cookie", "setcookie"]
    private static let fragments = ["token", "apikey", "secret", "password", "passwd", "auth", "session", "signature", "credential", "csrf", "xsrf"]
    /// Challenge headers contain "auth" but only describe the scheme, never a secret.
    private static let notSecret: Set<String> = ["wwwauthenticate", "proxyauthenticate"]

    public static func isSensitive(_ name: String) -> Bool {
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.isEmpty, !notSecret.contains(normalized) else { return false }
        if exactNames.contains(normalized) { return true }
        if normalized.hasSuffix("key") { return true }
        return fragments.contains { normalized.contains($0) }
    }

    /// Fixed length, so the mask doesn't reveal how long the secret is.
    public static let mask = String(repeating: "•", count: 10)
}

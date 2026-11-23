import Foundation

/// Payment-profile links for a coach's saved payment handles (Payments tab and the coach payment sheet).
/// Coaches save handles in many shapes — "@name", "name" or a pasted profile URL — so normalize first.
/// Mirrors PaymentLinks.kt in the Android app.
enum PaymentLinks {

    static func deepLink(platform: String, handle raw: String) -> URL? {
        guard let handle = normalizedHandle(raw) else { return nil }
        switch platform.lowercased().replacingOccurrences(of: " ", with: "") {
        case "venmo":
            let name = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
            return isUsername(name) ? URL(string: "https://venmo.com/u/\(name)") : nil
        case "paypal":
            // paypal.me only takes a PayPal.Me name; an email (what many coaches save) has no profile page
            return isUsername(handle) ? URL(string: "https://paypal.me/\(handle)") : nil
        case "cashapp":
            // Cash App profile pages need the $cashtag
            let tag = handle.hasPrefix("$") ? String(handle.dropFirst()) : handle
            return isUsername(tag) ? URL(string: "https://cash.app/$\(tag)") : nil
        default:
            return nil // Zelle and others have no profile link
        }
    }

    /// Strips a pasted profile URL down to the handle: scheme, query, "www."/"account." and the
    /// venmo.com/(u/), paypal.me/, paypal.com/paypalme/ and cash.app/ prefixes.
    static func normalizedHandle(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        for scheme in ["https://", "http://"] where s.lowercased().hasPrefix(scheme) { s = String(s.dropFirst(scheme.count)) }
        for host in ["www.", "account."] where s.lowercased().hasPrefix(host) { s = String(s.dropFirst(host.count)) }
        for prefix in ["venmo.com/u/", "venmo.com/", "paypal.me/", "paypal.com/paypalme/", "cash.app/"] where s.lowercased().hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s
    }

    private static func isUsername(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }
}

import Foundation

/// Round-robin key rotator with cooldown per key on rate limit / auth / server errors.
final class KeyRotator: @unchecked Sendable {
    static let shared = KeyRotator()

    private let lock = NSLock()
    private var cursor: [String: Int] = [:]
    private var cooldownUntil: [String: Date] = [:]

    private init() {}

    func orderedKeys(pool: String, keys: [String]) -> [String] {
        let clean = KeychainHelper.cleanKeys(keys)
        guard !clean.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let start = (cursor[pool] ?? 0) % clean.count
        let rotated = Array(clean[start...]) + Array(clean[..<start])

        var active: [String] = []
        var cooling: [(String, Date)] = []
        for k in rotated {
            let ck = "\(pool)|\(k)"
            if let until = cooldownUntil[ck], until > now {
                cooling.append((k, until))
            } else {
                active.append(k)
            }
        }
        if active.isEmpty {
            cooling.sort { $0.1 < $1.1 }
            return cooling.map(\.0)
        }
        return active + cooling.map(\.0)
    }

    func markSuccess(pool: String, key: String, allKeys: [String]) {
        let clean = KeychainHelper.cleanKeys(allKeys)
        guard !clean.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        cooldownUntil.removeValue(forKey: "\(pool)|\(key)")
        if let idx = clean.firstIndex(of: key) {
            cursor[pool] = (idx + 1) % clean.count
        }
    }

    func markFailure(pool: String, key: String, statusCode: Int, retryAfter: TimeInterval = 0) {
        let ttl: TimeInterval
        if statusCode == 429 {
            ttl = max(60, min(retryAfter, 600))
        } else if statusCode == 401 || statusCode == 403 {
            ttl = 3600
        } else if statusCode >= 500 || statusCode == 0 {
            ttl = 15
        } else {
            ttl = 5
        }
        lock.lock()
        cooldownUntil["\(pool)|\(key)"] = Date().addingTimeInterval(ttl)
        lock.unlock()
    }

    static func mask(_ key: String) -> String {
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if t.count <= 8 { return String(repeating: "*", count: t.count) }
        return "********" + t.suffix(4)
    }
}

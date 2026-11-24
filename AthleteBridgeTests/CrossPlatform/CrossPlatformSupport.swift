import XCTest
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
@testable import AthleteBridge

// Harness for the cross-platform contract tests (cross-platform/README.md). Android has the same pieces in
// app/src/test/java/com/athletebridge/android/crossplatform/CrossPlatform.kt; keep the two in step.

// MARK: - Contract

enum CrossPlatform {
    /// <repo>/cross-platform, found from this file: AthleteBridgeTests/CrossPlatform/CrossPlatformSupport.swift.
    static let dir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("cross-platform")

    static let contract: [String: Any] = {
        let url = dir.appendingPathComponent("contract.json")
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) else {
            fatalError("Can't read \(url.path)")
        }
        return Typed.fromJSONObject(json) as! [String: Any]
    }()

    /// Set by cross-platform/check.sh --record (xcodebuild passes TEST_RUNNER_CROSS_PLATFORM_RECORD through).
    static var recording: Bool { ProcessInfo.processInfo.environment["CROSS_PLATFORM_RECORD"] == "1" }

    static func fixtureURL(_ writer: String, _ story: String) -> URL {
        dir.appendingPathComponent("fixtures/\(writer)/\(story).json")
    }

    static var storyNames: [String] { ((contract["stories"] as? [String: Any]) ?? [:]).keys.sorted() }
}

/// One story from contract.json: its checkpoints and the values both apps use for it.
struct Story {
    let name: String
    let checkpoints: [String]
    private let values: [String: Any]
    private let expectations: [String: Any]

    init(_ name: String) {
        guard let spec = (CrossPlatform.contract["stories"] as? [String: Any])?[name] as? [String: Any] else {
            fatalError("contract.json has no story '\(name)'")
        }
        self.name = name
        checkpoints = spec["checkpoints"] as! [String]
        values = spec["values"] as! [String: Any]
        expectations = spec["expect"] as? [String: Any] ?? [:]
    }

    func str(_ k: String) -> String { values[k] as! String }
    func dbl(_ k: String) -> Double { Typed.double(values[k])! }
    func int(_ k: String) -> Int { Int(values[k] as! Int64) }
    func date(_ k: String) -> Date { Typed.parseISO(str(k))! }
    func obj(_ k: String) -> [String: Any] { values[k] as! [String: Any] }
    func strings(_ k: String) -> [String] { values[k] as! [String] }
    func stringMap(_ k: String) -> [String: String] { values[k] as! [String: String] }
    func expect(_ checkpoint: String) -> [String: Any] { expectations[checkpoint] as? [String: Any] ?? [:] }
}

/// contract.json "actors". iOS tests sign in as Auth emulator accounts with fixed ids i-<actor>.
enum Actors {
    static let keys = ["coach", "coach2", "client", "client2"]
    static let password = "cross-platform-123"
    private static func field(_ k: String, _ f: String) -> String {
        ((CrossPlatform.contract["actors"] as! [String: Any])[k] as! [String: Any])[f] as! String
    }
    static func first(_ k: String) -> String { field(k, "first") }
    static func last(_ k: String) -> String { field(k, "last") }
    static func name(_ k: String) -> String { "\(first(k)) \(last(k))" }
    static func role(_ k: String) -> String { field(k, "role") }
    /// The address tests sign up with; fixtures store it as {{<actor>-email}}.
    static func email(_ k: String) -> String { "\(first(k)).\(last(k))@example.com".lowercased() }
    static func uid(_ k: String) -> String { "i-\(k)" }
    static var uids: [String: String] { Dictionary(uniqueKeysWithValues: keys.map { ($0, uid($0)) }) }
}

// MARK: - Typed JSON

/// The fixture format shared with Android (cross-platform/README.md): plain JSON for strings, booleans, null,
/// integers, maps and arrays; one-key tags for {"$double"}, {"$timestamp"}, {"$ref"}, {"$geo"}, {"$bytes"}.
/// In memory: Bool, Int64, Double (only inside tags), String, NSNull, [String: Any], [Any].
enum Typed {

    static func fromJSONObject(_ v: Any) -> Any {
        switch v {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            if CFNumberIsFloatType(n) || n is NSDecimalNumber && n.doubleValue != n.doubleValue.rounded() { return n.doubleValue }
            return n.int64Value
        case let s as String: return s
        case let d as [String: Any]: return d.mapValues { fromJSONObject($0) }
        case let a as [Any]: return a.map { fromJSONObject($0) }
        default: return NSNull()
        }
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int64 { return Double(i) }
        if let i = v as? Int { return Double(i) }
        return (v as? NSNumber)?.doubleValue
    }

    /// A Firestore REST Value (what the emulator returns) → typed JSON.
    static func fromREST(_ value: [String: Any]) -> Any {
        if let s = value["stringValue"] as? String { return s }
        if let b = value["booleanValue"] as? Bool { return b }
        if let i = value["integerValue"] as? String { return Int64(i) ?? 0 }
        if let d = value["doubleValue"] { return ["$double": double(d) ?? Double(d as? String ?? "") ?? .nan] }
        if let t = value["timestampValue"] as? String { return ["$timestamp": isoNormalized(t)] }
        if value["nullValue"] != nil { return NSNull() }
        if let r = value["referenceValue"] as? String { return ["$ref": Emulator.relativePath(r)] }
        if let g = value["geoPointValue"] as? [String: Any] { return ["$geo": [double(g["latitude"]) ?? 0, double(g["longitude"]) ?? 0]] }
        if let b = value["bytesValue"] as? String { return ["$bytes": b] }
        if let m = value["mapValue"] as? [String: Any] { return fields(m["fields"] as? [String: Any] ?? [:]) }
        if let a = value["arrayValue"] as? [String: Any] { return (a["values"] as? [[String: Any]] ?? []).map { fromREST($0) } }
        return NSNull()
    }

    static func fields(_ f: [String: Any]) -> [String: Any] { f.mapValues { fromREST($0 as? [String: Any] ?? [:]) } }

    /// Typed JSON → a Firestore REST Value (for seeding the emulator with exact types).
    static func toREST(_ v: Any) -> [String: Any] {
        switch v {
        case is NSNull: return ["nullValue": NSNull()]
        case let b as Bool: return ["booleanValue": b]
        case let i as Int64: return ["integerValue": String(i)]
        case let i as Int: return ["integerValue": String(i)]
        case let d as Double: return ["doubleValue": d]
        case let s as String: return ["stringValue": s]
        case let a as [Any]: return ["arrayValue": ["values": a.map { toREST($0) }]]
        case let m as [String: Any]:
            if m.count == 1, let entry = m.first {
                switch entry.key {
                case "$double": return ["doubleValue": double(entry.value) ?? 0]
                case "$timestamp": return ["timestampValue": entry.value as! String]
                case "$ref": return ["referenceValue": Emulator.documentName(entry.value as! String)]
                case "$geo":
                    let p = entry.value as! [Any]
                    return ["geoPointValue": ["latitude": double(p[0]) ?? 0, "longitude": double(p[1]) ?? 0]]
                case "$bytes": return ["bytesValue": entry.value as! String]
                default: break
                }
            }
            return ["mapValue": ["fields": m.mapValues { toREST($0) }]]
        default: return ["nullValue": NSNull()]
        }
    }

    static func isTimestamp(_ v: Any) -> String? {
        guard let m = v as? [String: Any], m.count == 1 else { return nil }
        return m["$timestamp"] as? String
    }

    // ISO-8601 in the form Android's Instant.toString() prints: whole seconds without a fraction.
    static func parseISO(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: trimmed) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    static func formatISO(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = d.timeIntervalSince1970.rounded() == d.timeIntervalSince1970
            ? [.withInternetDateTime] : [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    static func isoNormalized(_ s: String) -> String { parseISO(s).map(formatISO) ?? s }

    // Printing matches Android's Json.print so both apps' fixtures read the same.

    static func print(_ v: Any) -> String {
        var s = ""
        write(&s, v, 0)
        return s + "\n"
    }

    static func compact(_ v: Any) -> String {
        switch v {
        case let m as [String: Any]:
            return "{" + sortedKeys(m).map { quoted($0) + ": " + compact(m[$0]!) }.joined(separator: ", ") + "}"
        case let a as [Any]: return "[" + a.map { compact($0) }.joined(separator: ", ") + "]"
        default:
            var s = ""
            write(&s, v, 0)
            return s
        }
    }

    /// Sorted like Kotlin's String.compareTo (UTF-16 code units).
    static func sortedKeys(_ m: [String: Any]) -> [String] {
        m.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    private static func isScalar(_ v: Any) -> Bool {
        v is NSNull || v is Bool || v is Int64 || v is Int || v is Double || v is String
    }

    private static func write(_ s: inout String, _ v: Any, _ indent: Int) {
        func pad(_ n: Int) { s += String(repeating: "  ", count: n) }
        switch v {
        case is NSNull: s += "null"
        case let b as Bool: s += b ? "true" : "false"
        case let i as Int64: s += String(i)
        case let i as Int: s += String(i)
        case let d as Double: s += "\(d)"
        case let str as String: s += quoted(str)
        case let m as [String: Any]:
            if m.isEmpty { s += "{}"; return }
            s += "{\n"
            let keys = sortedKeys(m)
            for (i, k) in keys.enumerated() {
                pad(indent + 1)
                s += quoted(k) + ": "
                write(&s, m[k]!, indent + 1)
                s += i < keys.count - 1 ? ",\n" : "\n"
            }
            pad(indent)
            s += "}"
        case let a as [Any]:
            if a.isEmpty { s += "[]"; return }
            if a.count <= 8 && a.allSatisfy(isScalar) {
                s += "[" + a.map { compact($0) }.joined(separator: ", ") + "]"
                return
            }
            s += "[\n"
            for (i, x) in a.enumerated() {
                pad(indent + 1)
                write(&s, x, indent + 1)
                s += i < a.count - 1 ? ",\n" : "\n"
            }
            pad(indent)
            s += "]"
        default: s += "null"
        }
    }

    private static func quoted(_ str: String) -> String {
        var out = "\""
        for c in str.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }
}

// MARK: - Emulator REST (owner access: bypasses the rules, keeps exact types)

enum EmulatorError: Error, CustomStringConvertible {
    case http(Int, String)
    case notLocal(String)
    var description: String {
        switch self {
        case .http(let code, let body): return "emulator HTTP \(code): \(body.prefix(300))"
        case .notLocal(let url): return "refusing to call \(url): not the local emulator"
        }
    }
}

enum Emulator {
    static let project = "athletebridge-63176"
    static var host: String { AppDelegate.emulatorFirestoreHost }
    static var documentsURL: String { "http://\(host)/v1/projects/\(project)/databases/(default)/documents" }
    static let namePrefix = "projects/athletebridge-63176/databases/(default)/documents/"
    static func documentName(_ path: String) -> String { namePrefix + path }
    static func relativePath(_ name: String) -> String { name.hasPrefix(namePrefix) ? String(name.dropFirst(namePrefix.count)) : name }

    @discardableResult
    static func call(_ method: String, _ url: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let u = URL(string: url), u.host == "127.0.0.1" || u.host == "localhost" else { throw EmulatorError.notLocal(url) }
        var request = URLRequest(url: u)
        request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw EmulatorError.http(code, String(decoding: data, as: UTF8.self)) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Deletes every document in the emulator (the test-only /emulator endpoint; production has none).
    static func wipeFirestore() async throws {
        try await call("DELETE", "http://\(host)/emulator/v1/projects/\(project)/databases/(default)/documents")
    }

    /// Auth emulator account with a fixed uid (the Admin SDK's createUser call); an existing one is kept.
    static func ensureUser(uid: String, email: String, password: String) async throws {
        do {
            try await call("POST", "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/\(project)/accounts",
                           ["localId": uid, "email": email, "password": password])
        } catch EmulatorError.http(_, let body) where body.contains("DUPLICATE_LOCAL_ID") || body.contains("EMAIL_EXISTS") {}
    }

    private static func collectionIds(_ parent: String) async throws -> [String] {
        let url = parent.isEmpty ? "\(documentsURL):listCollectionIds" : "\(documentsURL)/\(parent):listCollectionIds"
        return try await call("POST", url, ["pageSize": 500])["collectionIds"] as? [String] ?? []
    }

    /// Every document in the database, path → typed fields.
    static func exportAll() async throws -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        func walk(_ parent: String) async throws {
            for collection in try await collectionIds(parent) {
                let path = parent.isEmpty ? collection : "\(parent)/\(collection)"
                var token: String?
                repeat {
                    var url = "\(documentsURL)/\(path)?pageSize=300&showMissing=true"
                    if let token { url += "&pageToken=\(token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? token)" }
                    let page = try await call("GET", url)
                    for doc in page["documents"] as? [[String: Any]] ?? [] {
                        let docPath = relativePath(doc["name"] as! String)
                        if doc["createTime"] != nil { out[docPath] = Typed.fields(doc["fields"] as? [String: Any] ?? [:]) }
                        try await walk(docPath)
                    }
                    token = page["nextPageToken"] as? String
                } while token != nil
            }
        }
        try await walk("")
        return out
    }

    /// Writes documents with exactly these fields (replacing any existing ones).
    static func commit(_ docs: [String: [String: Any]]) async throws {
        let writes: [[String: Any]] = docs.map { path, fields in
            ["update": ["name": documentName(path), "fields": fields.mapValues { Typed.toREST($0) }]]
        }
        for start in stride(from: 0, to: writes.count, by: 400) {
            try await call("POST", "\(documentsURL):commit", ["writes": Array(writes[start..<min(start + 400, writes.count)])])
        }
    }
}

// MARK: - Fixtures

/// What one app's real code wrote at each checkpoint of a story: only the documents that changed (NSNull = deleted).
struct Fixture {
    struct Checkpoint {
        let name: String
        let changed: [String: Any]
    }

    let story: String
    let writer: String
    let checkpoints: [Checkpoint]

    func has(_ name: String) -> Bool { checkpoints.contains { $0.name == name } }

    /// Every document as it stood at `name`: setup and each later checkpoint applied in order.
    func state(_ name: String) -> [String: [String: Any]] {
        var docs: [String: [String: Any]] = [:]
        for cp in checkpoints {
            for (path, doc) in cp.changed {
                if let d = doc as? [String: Any] { docs[path] = d } else { docs[path] = nil }
            }
            if cp.name == name { break }
        }
        return docs
    }

    func changed(_ name: String) -> [String: Any] { checkpoints.first { $0.name == name }?.changed ?? [:] }

    /// Pushes queued at `name`: pendingNotifications/{uid}/notifications docs created in that step.
    func pushes(_ name: String) -> [(recipient: String, doc: [String: Any])] {
        changed(name).sorted { $0.key < $1.key }.compactMap { path, doc in
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 4, parts[0] == "pendingNotifications", let d = doc as? [String: Any] else { return nil }
            return (parts[1], d)
        }
    }

    var json: [String: Any] {
        ["story": story, "writer": writer,
         "checkpoints": checkpoints.map { ["name": $0.name, "changed": $0.changed] as [String: Any] }]
    }

    static func load(_ writer: String, _ story: String) -> Fixture? {
        guard let data = try? Data(contentsOf: CrossPlatform.fixtureURL(writer, story)) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Fixture? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let root = Typed.fromJSONObject(raw) as? [String: Any] else { return nil }
        let cps = (root["checkpoints"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
            Checkpoint(name: $0["name"] as! String, changed: $0["changed"] as? [String: Any] ?? [:])
        }
        return Fixture(story: root["story"] as! String, writer: root["writer"] as! String, checkpoints: cps)
    }
}

// MARK: - Recording

/// Ids written into documents, swapped for {{name}} placeholders so fixtures are the same on every run.
enum Ids {
    private static let uuid = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
    private static func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
    /// A generated document id (only trusted where a document id goes: field names can be 20 letters too).
    static func isDocId(_ s: String) -> Bool { matches(s, "^auto[0-9]+$") || matches(s, "^[A-Za-z0-9]{20}$") || matches(s, uuid) }
    /// A generated map key or value (signup keys, group ids).
    static func isKeyId(_ s: String) -> Bool { matches(s, "^auto[0-9]+$") || matches(s, uuid) }

    /// Replace each raw id where it stands alone ("auto1" but not inside "auto12"), longest first.
    static func replaceIn(_ s: String, _ ids: [String: String]) -> String {
        var out = s
        for (raw, name) in ids.sorted(by: { $0.key.count > $1.key.count }) where !raw.isEmpty && out.contains(raw) {
            var result = ""
            var i = out.startIndex
            while let r = out.range(of: raw, range: i..<out.endIndex) {
                let before: Character? = r.lowerBound > out.startIndex ? out[out.index(before: r.lowerBound)] : nil
                let after: Character? = r.upperBound < out.endIndex ? out[r.upperBound] : nil
                let alone = !(before.map { $0.isLetter || $0.isNumber } ?? false) && !(after.map { $0.isLetter || $0.isNumber } ?? false)
                result += out[i..<r.lowerBound]
                result += alone ? "{{\(name)}}" : raw
                i = r.upperBound
            }
            result += out[i...]
            out = result
        }
        return out
    }

    static func replaceTree(_ v: Any, _ ids: [String: String]) -> Any {
        switch v {
        case let s as String: return replaceIn(s, ids)
        case let m as [String: Any]:
            var out: [String: Any] = [:]
            for (k, x) in m { out[replaceIn(k, ids)] = replaceTree(x, ids) }
            return out
        case let a as [Any]: return a.map { replaceTree($0, ids) }
        default: return v
        }
    }

    static func replace(_ docs: [String: Any], _ ids: [String: String]) -> [String: Any] {
        guard !ids.isEmpty else { return docs }
        var out: [String: Any] = [:]
        for (p, d) in docs { out[replaceIn(p, ids)] = replaceTree(d, ids) }
        return out
    }
}

/// Turns the exported database into fixture form (see the Android Normalizer, which this mirrors): known ids as
/// {{name}}, times written while the story ran as {{now:<first step that wrote them>}}, other generated ids as
/// {{h:xxxxxxxx}} from a hash of where they first appeared.
final class Normalizer {
    private let known: [String: String]
    private(set) var assigned: [String: String]
    private(set) var firstSeen: [String: String]
    private let checkpoint: String
    private let now = Date()

    init(known: [String: String], assigned: [String: String], firstSeen: [String: String], checkpoint: String) {
        self.known = known
        self.assigned = assigned
        self.firstSeen = firstSeen
        self.checkpoint = checkpoint
    }

    func normalize(_ raw: [String: [String: Any]]) -> [String: [String: Any]] {
        var docs: [String: Any] = raw
        docs = Ids.replace(docs, known)
        docs = docs.mapValues { nowify($0) }
        docs = Ids.replace(docs, assigned)
        let fresh = generatedIds(docs)
        if !fresh.isEmpty {
            let mask = Dictionary(uniqueKeysWithValues: fresh.map { ($0, "?") })
            var contexts: [String: String] = [:]
            for g in fresh { contexts[g] = contextOf(g, docs, mask) }
            var uses: [String: Int] = [:]
            for g in fresh.sorted(by: { (contexts[$0]!, $0) < (contexts[$1]!, $1) }) {
                let base = "h:" + String(sha1(contexts[g]!).prefix(8))
                let n = (uses[base] ?? 0) + 1
                uses[base] = n
                assigned[g] = n == 1 ? base : "\(base)-\(n)"
            }
            docs = Ids.replace(docs, assigned.filter { fresh.contains($0.key) })
        }
        return docs.mapValues { $0 as! [String: Any] }
    }

    private func nowify(_ v: Any) -> Any {
        if let t = Typed.isTimestamp(v), let d = Typed.parseISO(t), abs(d.timeIntervalSince(now)) <= 2 * 86_400 {
            let label = firstSeen[t] ?? checkpoint
            firstSeen[t] = label
            return ["$timestamp": "{{now:\(label)}}"]
        }
        if let m = v as? [String: Any] { return m.mapValues { nowify($0) } }
        if let a = v as? [Any] { return a.map { nowify($0) } }
        return v
    }

    private func generatedIds(_ docs: [String: Any]) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        func docIds(_ path: String) -> [String] {
            path.split(separator: "/", omittingEmptySubsequences: false).enumerated()
                .filter { $0.offset % 2 == 1 && !$0.element.hasPrefix("{{") && Ids.isDocId(String($0.element)) }
                .map { String($0.element) }
        }
        let paths = docs.keys.sorted()
        for p in paths { docIds(p).forEach(add) }
        let pathIds = Set(out)
        func scan(_ v: Any) {
            switch v {
            case let s as String:
                if s.hasPrefix("{{") { return }
                if pathIds.contains(s) || Ids.isKeyId(s) { add(s) } else if s.filter({ $0 == "/" }).count % 2 == 1 { docIds(s).forEach(add) }
            case let m as [String: Any]:
                for k in m.keys.sorted() {
                    if Ids.isKeyId(k) { add(k) }
                    scan(m[k]!)
                }
            case let a as [Any]: a.forEach(scan)
            default: break
            }
        }
        for p in paths { scan(docs[p]!) }
        return out
    }

    private func contextOf(_ g: String, _ docs: [String: Any], _ mask: [String: String]) -> String {
        var found: [(Int, String)] = []
        for (path, doc) in docs {
            let masked = Ids.replaceIn(path, mask)
            let content = Typed.compact(Ids.replaceTree(doc, mask))
            let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if segments.last == g { found.append((0, "doc|\(masked)|\(content)")) } else if segments.contains(g) { found.append((2, "parent|\(masked)|\(content)")) }
            func walk(_ v: Any, _ at: String) {
                switch v {
                case let m as [String: Any]:
                    for (k, x) in m {
                        if k == g { found.append((1, "key|\(masked)|\(at)/{{?}}|" + Typed.compact(Ids.replaceTree(x, mask)))) }
                        walk(x, "\(at)/" + Ids.replaceIn(k, mask))
                    }
                case let a as [Any]: for (i, x) in a.enumerated() { walk(x, "\(at)[\(i)]") }
                case let s as String: if Ids.replaceIn(s, [g: "?"]) != s { found.append((3, "value|\(masked)|\(at)")) }
                default: break
                }
            }
            walk(doc, "")
        }
        return found.min { ($0.0, $0.1) < ($1.0, $1.1) }?.1 ?? g
    }

    private func sha1(_ s: String) -> String {
        Insecure.SHA1.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Records a story as the iOS app's real code runs it: `checkpoint` exports the emulator after each step, and
/// `finish` either writes cross-platform/fixtures/ios/<story>.json (record mode) or checks the committed fixture
/// still matches — if iOS starts writing something different, Android has to be re-checked against it.
@MainActor
final class Recorder {
    let story: String
    private var known: [String: String] = [:]
    private var assigned: [String: String] = [:]
    private var firstSeen: [String: String] = [:]
    private var checkpoints: [Fixture.Checkpoint] = []
    private var previous: [String: [String: Any]] = [:]
    private let expected: [String]

    init(_ story: String) {
        self.story = story
        expected = Story(story).checkpoints
    }

    /// Name an id the story created ("booking", "club", ...) so fixtures and the other app's tests can refer to it.
    func register(_ raw: String, _ name: String) {
        precondition(!raw.isEmpty, "empty id for \(name)")
        known[raw] = name
    }

    func checkpoint(_ name: String) async throws {
        precondition(expected.contains(name), "'\(name)' is not a checkpoint of '\(story)' in contract.json")
        let normalizer = Normalizer(known: known, assigned: assigned, firstSeen: firstSeen, checkpoint: name)
        let state = normalizer.normalize(try await Emulator.exportAll())
        assigned = normalizer.assigned
        firstSeen = normalizer.firstSeen
        var changed: [String: Any] = [:]
        for (path, doc) in state where previous[path].map({ Typed.print($0) }) != Typed.print(doc) { changed[path] = doc }
        for path in previous.keys where state[path] == nil { changed[path] = NSNull() }
        checkpoints.append(.init(name: name, changed: changed))
        previous = state
    }

    func finish(file: StaticString = #filePath, line: UInt = #line) throws {
        let recorded = Fixture(story: story, writer: "ios", checkpoints: checkpoints)
        let url = CrossPlatform.fixtureURL("ios", story)
        if CrossPlatform.recording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Typed.print(recorded.json).write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let committed = Fixture.load("ios", story) else {
            XCTFail("No iOS fixture for '\(story)' yet. Record it with: cross-platform/check.sh --record", file: file, line: line)
            return
        }
        let problems = FixtureDiff.describe(committed, recorded)
        if !problems.isEmpty {
            XCTFail("iOS now writes different data in the '\(story)' story than cross-platform/fixtures/ios/\(story).json, "
                    + "which the Android app was last checked against:\n  " + problems.joined(separator: "\n  ")
                    + "\nIf the change is intended, re-record and re-check both apps with: cross-platform/check.sh --record",
                    file: file, line: line)
        }
    }
}

/// Human-readable differences between two recordings of a story.
enum FixtureDiff {
    static func describe(_ old: Fixture, _ new: Fixture) -> [String] {
        var out: [String] = []
        let oldNames = old.checkpoints.map(\.name)
        let newNames = new.checkpoints.map(\.name)
        if oldNames != newNames { out.append("checkpoints were \(oldNames), now \(newNames)") }
        for name in newNames where oldNames.contains(name) {
            let a = old.changed(name)
            let b = new.changed(name)
            for path in Set(a.keys).union(b.keys).sorted() {
                switch (a[path], b[path]) {
                case (nil, _): out.append("\(name): now also writes \(path)")
                case (_, nil): out.append("\(name): no longer writes \(path)")
                case let (x?, y?):
                    let fx = flatten(x)
                    let fy = flatten(y)
                    for k in Set(fx.keys).union(fy.keys).sorted() where fx[k] != fy[k] {
                        out.append("\(name): \(path) \(k): \(fx[k] ?? "(missing)") -> \(fy[k] ?? "(missing)")")
                    }
                }
            }
        }
        return Array(out.prefix(60))
    }

    private static func flatten(_ v: Any, _ prefix: String = "") -> [String: String] {
        var out: [String: String] = [:]
        if let m = v as? [String: Any], !(m.count == 1 && m.keys.first!.hasPrefix("$")) {
            if m.isEmpty { out[prefix.isEmpty ? "." : prefix] = "{}" }
            for (k, x) in m { out.merge(flatten(x, prefix.isEmpty ? k : "\(prefix).\(k)")) { a, _ in a } }
        } else {
            out[prefix] = Typed.compact(v)
        }
        return out
    }
}

// MARK: - Reading another app's fixtures

/// Loads a fixture into the emulator, turning placeholders into concrete ids: actors get their test accounts,
/// derived ids (the chat id) are computed from them, everything else becomes "xp-<name>". {{now:<step>}} times
/// become minutes in the past in step order, so whatever the reading app writes next is later than all of them.
@MainActor
final class Seeder {
    let uids: [String: String]
    private let base = Date()
    private var steps: [String] = []

    init(uids: [String: String] = Actors.uids) { self.uids = uids }

    func id(_ name: String) -> String {
        if let u = uids[name] { return u }
        if name.hasSuffix("-email") { return Actors.email(String(name.dropLast("-email".count))) }
        if let spec = (CrossPlatform.contract["derivedIds"] as? [String: Any])?[name] as? [String: Any] {
            let parts = (spec["sortedJoin"] as! [String]).map { id($0) }.sorted()
            return parts.joined(separator: spec["separator"] as! String)
        }
        return "xp-" + name.replacingOccurrences(of: ":", with: "-")
    }

    func text(_ s: String) -> String {
        guard s.contains("{{") else { return s }
        var out = ""
        var rest = s[...]
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            out += rest[..<open.lowerBound]
            out += id(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    func time(_ label: String) -> Date {
        let step = label.replacingOccurrences(of: "{{now", with: "").replacingOccurrences(of: "}}", with: "").replacingOccurrences(of: ":", with: "")
        guard let i = steps.firstIndex(of: step) else { return base.addingTimeInterval(-60) }
        return base.addingTimeInterval(-60 * Double(steps.count + 1 - i))
    }

    func tree(_ v: Any) -> Any {
        if let t = Typed.isTimestamp(v), t.hasPrefix("{{now") { return ["$timestamp": Typed.formatISO(time(t))] }
        switch v {
        case let s as String: return text(s)
        case let m as [String: Any]:
            var out: [String: Any] = [:]
            for (k, x) in m { out[text(k)] = tree(x) }
            return out
        case let a as [Any]: return a.map { tree($0) }
        default: return v
        }
    }

    /// The fixture's documents as they stood at `checkpoint`, written into the (already empty) emulator.
    func seed(_ fixture: Fixture, at checkpoint: String) async throws {
        steps = fixture.checkpoints.map(\.name)
        var docs: [String: [String: Any]] = [:]
        for (path, doc) in fixture.state(checkpoint) { docs[text(path)] = tree(doc) as? [String: Any] }
        try await Emulator.commit(docs)
    }
}

// MARK: - Pushes

/// onPendingNotificationCreate (functions/src/index.ts): what reaches the phone from a pendingNotifications doc.
enum CloudFunction {
    static var forwardedKeys: [String] { (CrossPlatform.contract["cloudFunction"] as! [String: Any])["forwardedKeys"] as! [String] }

    static func data(for notification: [String: Any], recipient: String) -> [String: String] {
        var out: [String: String] = [:]
        for key in forwardedKeys { if let v = notification[key] as? String, !v.isEmpty { out[key] = v } }
        out["recipientUid"] = recipient
        return out
    }
}

/// contract.json "pushRouting", checked against NotificationManager.destination(for:).
enum PushRoutes {
    struct Route {
        let type: String
        let data: [String: String]
        let accept: [(screen: String, id: String?)]
    }

    static var routes: [Route] {
        ((CrossPlatform.contract["pushRouting"] as! [String: Any])["routes"] as! [Any]).map {
            let r = $0 as! [String: Any]
            return Route(type: r["type"] as! String, data: r["data"] as! [String: String],
                         accept: (r["accept"] as! [Any]).map { a in
                             let a = a as! [String: Any]
                             return (a["screen"] as! String, a["id"] as? String)
                         })
        }
    }

    /// The screen (and id) a tap opens on iOS, in the contract's vocabulary.
    @MainActor
    static func iosScreen(_ data: [String: String]) -> (screen: String, id: String?)? {
        guard let routed = NotificationManager.destination(for: data) else { return nil }
        switch routed.destination {
        case .chat(let id): return ("chat", id)
        case .booking(let id): return ("booking", id)
        case .payments: return ("payments", nil)
        case .stringing(let orderId): return ("stringerOrder", orderId)
        case .clubJoinRequest(let placeId), .clubMembers(let placeId): return ("club", placeId)
        case .clubAnnouncement(let placeId, _): return ("clubAnnouncements", placeId)
        case .signupEvent(let placeId, let eventId): return eventId.isEmpty ? ("signupEvents", placeId) : ("signupEvent", eventId)
        case .tournaments: return ("tournaments", nil)
        }
    }

    /// Why a queued push is wrong before it's even tapped: onMessageCreate already pushes every chat message.
    static func duplicate(_ notification: [String: Any]) -> String? {
        guard notification["chatId"] != nil else { return nil }
        return "queues its own push for a chat message (\"\(notification["title"] ?? "")\", type \(notification["type"] ?? "nil")), "
            + "but the onMessageCreate Cloud Function already pushes every message, so the recipient is notified twice"
    }

    /// Why tapping `notification` (a pendingNotifications doc, ids concrete) on iOS goes wrong, or nil if it's fine.
    @MainActor
    static func problem(_ notification: [String: Any], recipient: String) -> String? {
        guard let type = notification["type"] as? String else {
            return "a push with no type (\"\(notification["title"] ?? "")\"): iOS can only route it by the ids it carries"
        }
        guard let route = routes.first(where: { $0.type == type }) else {
            return "push type '\(type)' (\"\(notification["title"] ?? "")\") isn't in the routing contract"
        }
        let received = CloudFunction.data(for: notification, recipient: recipient)
        guard let opened = iosScreen(received) else { return "\(route.type) opens nothing on iOS; the phone receives \(received)" }
        func expectedId(_ template: String) -> String {
            guard let key = route.data.first(where: { $0.value == template })?.key else { return template }
            return notification[key] as? String ?? template
        }
        if route.accept.contains(where: { $0.screen == opened.screen && ($0.id == nil || opened.id == expectedId($0.id!)) }) { return nil }
        let wanted = route.accept.map { option -> String in
            guard let id = option.id else { return option.screen }
            return "\(option.screen)(\(expectedId(id)))"
        }.joined(separator: " or ")
        return "\(route.type) opens \(opened.screen)\(opened.id.map { "(\($0))" } ?? "") on iOS instead of \(wanted); the phone receives \(received)"
    }
}

// MARK: - Test plumbing

/// Collects every problem in a test so one run reports all the incompatibilities in a story.
final class Problems {
    private let what: String
    private var list: [String] = []

    init(_ what: String) { self.what = what }

    func add(_ message: String) { list.append(message) }

    func eq<T: Equatable>(_ label: String, _ expected: T?, _ actual: T?) {
        if expected != actual { list.append("\(label): expected \(expected.map { "\($0)" } ?? "nil"), got \(actual.map { "\($0)" } ?? "nil")") }
    }

    func check(_ ok: Bool, _ message: @autoclosure () -> String) { if !ok { list.append(message()) } }

    func assertNone(file: StaticString = #filePath, line: UInt = #line) {
        var seen = Set<String>()
        let unique = list.filter { seen.insert($0).inserted }
        if !unique.isEmpty { XCTFail("\(what):\n  " + unique.joined(separator: "\n  "), file: file, line: line) }
    }
}

/// Shared setup for the cross-platform tests: fixed test accounts for the contract's actors and a way to reset
/// the emulator between stories.
@MainActor
class CrossPlatformTestCase: EmulatorTestCase {

    func uid(_ actor: String) -> String { Actors.uid(actor) }

    func user(_ actor: String) -> TestUser {
        TestUser(uid: Actors.uid(actor), email: Actors.email(actor), password: Actors.password, first: Actors.first(actor),
                 name: Actors.name(actor), role: Actors.role(actor) == "COACH" ? .coach : .client)
    }

    func signIn(_ actor: String) async throws { try await signIn(user(actor)) }

    /// An empty database with the actors' sign-in accounts in place, and a fresh manager with nothing cached.
    func resetWorld() async throws {
        fm?.stopAllChatListeners()
        fm?.stopSubscriptionListener()
        try? Auth.auth().signOut()
        try await Emulator.wipeFirestore()
        for a in Actors.keys { try await Emulator.ensureUser(uid: Actors.uid(a), email: Actors.email(a), password: Actors.password) }
        fm = FirestoreManager()
    }

    /// Like `eventually`, but reports false instead of failing the test.
    func soon(_ timeout: TimeInterval = 8, _ condition: () async throws -> Bool) async rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try await condition() { return true }
            try? await Task.sleep(nanoseconds: 150_000_000)
        } while Date() < deadline
        return false
    }
}

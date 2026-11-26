import Foundation

struct TeachingToolScorePeriod: Decodable, Identifiable { var id: String { periodId }; let periodId: String; let ordinal: String; let startedAt: String; let isClosed: Bool }
struct TeachingToolScorePeriods: Decodable {
    let sessionId: String; let periods: [TeachingToolScorePeriod]; let nextCursor: String?
    private enum CodingKeys: String, CodingKey { case sessionId, periods, nextCursor }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); sessionId = try c.decode(String.self, forKey: .sessionId); periods = try c.decode([TeachingToolScorePeriod].self, forKey: .periods); nextCursor = try c.decode(String?.self, forKey: .nextCursor) }
}
struct TeachingToolScoreTarget: Decodable { let kind: String; let id: String }
struct TeachingToolScoreEntry: Decodable, Identifiable {
    var id: String { entryId }; let entryId: String; let displayName: String; let delta: Int; let balanceAfter: String
    let reason: String; let createdAt: String; let origin: String; let reversed: Bool
}
struct TeachingToolScoreRank: Decodable, Identifiable { var id: String { target.id }; let target: TeachingToolScoreTarget; let displayName: String; let balance: String; let rank: String }
struct CoreToolScorePage: Decodable {
    let sessionId: String; let periodId: String; let view: String; let target: TeachingToolScoreTarget?; let targetKind: String?
    let balance: String?; let nextCursor: String?; let entries: [TeachingToolScoreEntry]; let rows: [TeachingToolScoreRank]
    private enum CodingKeys: String, CodingKey { case sessionId, periodId, view, target, targetKind, balance, nextCursor, entries, rows }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId); periodId = try c.decode(String.self, forKey: .periodId)
        view = try c.decode(String.self, forKey: .view); nextCursor = try c.decode(String?.self, forKey: .nextCursor)
        switch view {
        case "ledger": target = try c.decode(TeachingToolScoreTarget?.self, forKey: .target); targetKind = target?.kind; balance = try c.decode(String?.self, forKey: .balance); entries = try c.decode([TeachingToolScoreEntry].self, forKey: .entries); rows = []
        case "leaderboard": target = nil; targetKind = try c.decode(String.self, forKey: .targetKind); balance = nil; entries = []; rows = try c.decode([TeachingToolScoreRank].self, forKey: .rows)
        default: throw DecodingError.dataCorruptedError(forKey: .view, in: c, debugDescription: "Unknown score view")
        }
    }
}
struct PreparedToolScoreEntry: Identifiable { var id: String { entry.id }; let entry: TeachingToolScoreEntry; let deltaText: String; let canReverse: Bool }
struct TeachingToolScoreQuery: Decodable {
    let periodId: String; let view: String; let targetKind: String?; let targetId: String?; let cursor: String?; let limit: Int
    private enum CodingKeys: String, CodingKey { case periodId, view, targetKind, targetId, cursor, limit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        periodId = try c.decode(String.self, forKey: .periodId); view = try c.decode(String.self, forKey: .view)
        targetKind = try c.decode(String?.self, forKey: .targetKind); targetId = try c.decode(String?.self, forKey: .targetId)
        cursor = try c.decode(String?.self, forKey: .cursor); limit = try c.decode(Int.self, forKey: .limit)
    }
}
struct TeachingToolScorePage: Identifiable {
    let query: TeachingToolScoreQuery
    let id: String; let periodId: String; let view: String; let targetKind: String?; let targetId: String?; let balance: String?; let nextCursor: String?
    let entries: [PreparedToolScoreEntry]; let rows: [TeachingToolScoreRank]
    init(_ page: CoreToolScorePage, query: TeachingToolScoreQuery, reversible: Set<String>) {
        self.query = query
        id = [query.periodId, query.view, query.targetKind ?? "", query.targetId ?? ""].joined(separator: ":")
        periodId = page.periodId; view = page.view; targetKind = page.targetKind; targetId = page.target?.id; balance = page.balance; nextCursor = page.nextCursor; rows = page.rows
        entries = page.entries.map { PreparedToolScoreEntry(entry: $0, deltaText: $0.delta > 0 ? "+\($0.delta)" : String($0.delta), canReverse: reversible.contains($0.id)) }
    }
}
struct TeachingToolScores {
    let canReadPeriods: Bool; let canReadLedger: Bool; let canReadRank: Bool; let canReadAll: Bool
    let periods: [TeachingToolScorePeriod]; let periodsCursor: String?; let pages: [TeachingToolScorePage]
}

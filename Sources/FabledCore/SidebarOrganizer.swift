import ClaudeKit
import Foundation

/// User-tunable sidebar organization (feature 18, CD funnel pattern).
/// Persisted as JSON in UserDefaults by AppModel.
public struct SidebarOptions: Codable, Equatable, Sendable {
    public enum GroupBy: String, Codable, CaseIterable, Sendable {
        case project, date, none
    }
    public enum SortBy: String, Codable, CaseIterable, Sendable {
        case recency, name
    }
    public enum ActivityWindow: Codable, Equatable, Sendable {
        case all
        case days(Int)

        public var days: Int? {
            if case .days(let value) = self { return value }
            return nil
        }
        /// Menu presets, CD parity: All / 1d / 3d / 7d / 30d.
        public static let presets: [ActivityWindow] =
            [.all, .days(1), .days(3), .days(7), .days(30)]
        public var label: String {
            switch self {
            case .all: "All time"
            case .days(1): "Last day"
            case .days(let n): "Last \(n) days"
            }
        }

        private enum CodingKeys: String, CodingKey { case kind, days }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "days":
                self = .days(try container.decode(Int.self, forKey: .days))
            default:
                self = .all
            }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .all:
                try container.encode("all", forKey: .kind)
            case .days(let n):
                try container.encode("days", forKey: .kind)
                try container.encode(n, forKey: .days)
            }
        }
    }

    public var groupBy: GroupBy = .project
    public var sortBy: SortBy = .recency
    public var activityWindow: ActivityWindow = .all
    public var pinnedSessionIDs: Set<String> = []

    public init() {}
}

/// One rendered sidebar section. `id` is a stable synthetic key
/// ("pinned" / "project-<id>" / "date-<bucket>" / "sessions"), NOT the
/// title: titles collide (two checkouts named "Fabled"; a project literally
/// named "Pinned") and ForEach must still see distinct sections.
public struct SidebarSection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public var sessions: [SessionSummary]

    public init(id: String, title: String, sessions: [SessionSummary]) {
        self.id = id
        self.title = title
        self.sessions = sessions
    }
}

public enum SidebarOrganizer {
    /// Pure: summaries (already newest-first from the index) + options → sections.
    /// Pinned sessions float to a leading section and bypass the window filter
    /// (a pin means "I care", staleness notwithstanding).
    public static func organize(
        _ summaries: [SessionSummary], options: SidebarOptions, now: Date
    ) -> [SidebarSection] {
        var pinned: [SessionSummary] = []
        var rest: [SessionSummary] = []
        for summary in summaries {
            if options.pinnedSessionIDs.contains(summary.id) {
                pinned.append(summary)
            } else if let days = options.activityWindow.days {
                if summary.lastActivity >= now.addingTimeInterval(-Double(days) * 86_400) {
                    rest.append(summary)
                }
            } else {
                rest.append(summary)
            }
        }
        rest = sorted(rest, by: options.sortBy)
        pinned = sorted(pinned, by: options.sortBy)

        var sections: [SidebarSection] = []
        if !pinned.isEmpty {
            sections.append(SidebarSection(id: "pinned", title: "Pinned", sessions: pinned))
        }
        switch options.groupBy {
        case .none:
            if !rest.isEmpty {
                sections.append(SidebarSection(id: "sessions", title: "Sessions",
                                               sessions: rest))
            }
        case .project:
            // Key by project IDENTITY: two checkouts sharing a leaf name
            // ("Fabled") stay separate sections; the leaf is only the title.
            var order: [String] = []
            var titles: [String: String] = [:]
            var groups: [String: [SessionSummary]] = [:]
            for summary in rest {
                let key = summary.project.id
                if groups[key] == nil {
                    order.append(key)
                    titles[key] = summary.project.displayName
                }
                groups[key, default: []].append(summary)
            }
            sections += order.map {
                SidebarSection(id: "project-\($0)", title: titles[$0]!,
                               sessions: groups[$0]!)
            }
        case .date:
            let calendar = Calendar.current
            var buckets: [(String, [SessionSummary])] =
                [("Today", []), ("Yesterday", []), ("This week", []), ("Earlier", [])]
            for summary in rest {
                let bucket: Int
                if calendar.isDate(summary.lastActivity, inSameDayAs: now) {
                    bucket = 0
                } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                          calendar.isDate(summary.lastActivity, inSameDayAs: yesterday) {
                    bucket = 1
                } else if summary.lastActivity >= now.addingTimeInterval(-7 * 86_400) {
                    bucket = 2
                } else {
                    bucket = 3
                }
                buckets[bucket].1.append(summary)
            }
            sections += buckets.compactMap { title, sessions in
                sessions.isEmpty ? nil
                    : SidebarSection(id: "date-\(title)", title: title, sessions: sessions)
            }
        }
        return sections
    }

    private static func sorted(
        _ summaries: [SessionSummary], by sort: SidebarOptions.SortBy
    ) -> [SessionSummary] {
        switch sort {
        case .recency:
            summaries.sorted { $0.lastActivity > $1.lastActivity }
        case .name:
            summaries.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}

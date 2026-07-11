import XCTest
import ClaudeKit
@testable import FabledCore

final class SidebarOrganizerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func summary(_ id: String, project: String, daysAgo: Double,
                         title: String? = nil) -> SessionSummary {
        let projectFolder = ProjectFolder(
            flattenedName: "-tmp-\(project)", originalPath: "/tmp/\(project)",
            directoryURL: URL(fileURLWithPath: "/tmp/\(project)"))
        return SessionSummary(
            id: id, project: projectFolder,
            fileURL: URL(fileURLWithPath: "/tmp/\(project)/\(id).jsonl"),
            title: title ?? id,
            lastActivity: now.addingTimeInterval(-daysAgo * 86_400),
            approximateSizeBytes: 1)
    }

    func testGroupByProjectPreservesNewestFirstProjectOrder() {
        let sections = SidebarOrganizer.organize(
            [summary("a", project: "one", daysAgo: 2),
             summary("b", project: "two", daysAgo: 0.5),
             summary("c", project: "one", daysAgo: 1)],
            options: SidebarOptions(), now: now)
        XCTAssertEqual(sections.map(\.title), ["two", "one"])
        XCTAssertEqual(sections[1].sessions.map(\.id), ["c", "a"],
                       "recency within the group")
    }

    func testGroupByDateBucketsTodayYesterdayOlder() {
        var options = SidebarOptions()
        options.groupBy = .date
        let sections = SidebarOrganizer.organize(
            [summary("today", project: "p", daysAgo: 0.01),
             summary("yesterday", project: "p", daysAgo: 1.0),
             summary("old", project: "p", daysAgo: 9)],
            options: options, now: now)
        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Earlier"])
    }

    func testActivityWindowFiltersStaleSessions() {
        var options = SidebarOptions()
        options.activityWindow = .days(7)
        let sections = SidebarOrganizer.organize(
            [summary("fresh", project: "p", daysAgo: 2),
             summary("stale", project: "junk-probe", daysAgo: 30)],
            options: options, now: now)
        XCTAssertEqual(sections.flatMap(\.sessions).map(\.id), ["fresh"],
                       "probe/worktree junk ages out (finding 14)")
    }

    func testSortByNameIsCaseInsensitive() {
        var options = SidebarOptions()
        options.groupBy = .none
        options.sortBy = .name
        let sections = SidebarOrganizer.organize(
            [summary("1", project: "p", daysAgo: 0, title: "beta"),
             summary("2", project: "p", daysAgo: 1, title: "Alpha")],
            options: options, now: now)
        XCTAssertEqual(sections.flatMap(\.sessions).map(\.title), ["Alpha", "beta"])
    }

    func testPinnedSessionsFloatIntoLeadingSection() {
        var options = SidebarOptions()
        options.pinnedSessionIDs = ["c"]
        let sections = SidebarOrganizer.organize(
            [summary("a", project: "one", daysAgo: 2),
             summary("c", project: "two", daysAgo: 5)],
            options: options, now: now)
        XCTAssertEqual(sections.first?.title, "Pinned")
        XCTAssertEqual(sections.first?.sessions.map(\.id), ["c"])
        XCTAssertEqual(sections.dropFirst().flatMap(\.sessions).map(\.id), ["a"],
                       "pinned sessions leave their home group and dodge the window filter")
    }

    func testOptionsRoundTripThroughJSON() throws {
        var options = SidebarOptions()
        options.groupBy = .date
        options.sortBy = .name
        options.activityWindow = .days(30)
        options.pinnedSessionIDs = ["x", "y"]
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(SidebarOptions.self, from: data)
        XCTAssertEqual(decoded, options)
    }
}

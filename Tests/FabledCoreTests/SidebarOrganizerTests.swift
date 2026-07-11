import XCTest
import ClaudeKit
@testable import FabledCore

final class SidebarOrganizerTests: XCTestCase {
    // Local noon: a fixed epoch is local midnight *somewhere* (1.8e9 is
    // exactly 00:00 in UTC-8), where a sub-day offset like `daysAgo: 0.01`
    // crosses the day boundary and breaks the date buckets. From noon, no
    // sub-day fixture can cross a boundary in any timezone.
    private let now = Calendar.current.date(
        from: DateComponents(year: 2027, month: 1, day: 15, hour: 12))!

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
             summary("thisWeek", project: "p", daysAgo: 4),
             summary("old", project: "p", daysAgo: 9)],
            options: options, now: now)
        XCTAssertEqual(sections.map(\.title),
                       ["Today", "Yesterday", "This week", "Earlier"])
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

    func testSameLeafNameProjectsStayDistinct() {
        // Two checkouts sharing a leaf name must not merge (grouping keys by
        // project identity; the leaf name is only the section title).
        func checkout(_ id: String, root: String) -> SessionSummary {
            let project = ProjectFolder(
                flattenedName: "-tmp-\(root)-Fabled",
                originalPath: "/tmp/\(root)/Fabled",
                directoryURL: URL(fileURLWithPath: "/tmp/\(root)/Fabled"))
            return SessionSummary(
                id: id, project: project,
                fileURL: URL(fileURLWithPath: "/tmp/\(root)/Fabled/\(id).jsonl"),
                title: id, lastActivity: now, approximateSizeBytes: 1)
        }
        let sections = SidebarOrganizer.organize(
            [checkout("a", root: "a"), checkout("b", root: "b")],
            options: SidebarOptions(), now: now)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.title), ["Fabled", "Fabled"])
        XCTAssertEqual(Set(sections.map(\.id)).count, 2, "distinct section ids")
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

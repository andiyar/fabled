import XCTest
@testable import FabledCore

final class NotificationPolicyTests: XCTestCase {
    func testGateNotifiesWhenAppInactive() {
        let note = NotificationPolicy.decide(
            .gateArrived(summary: "Approve: rm -rf build"),
            sessionTitle: "Fix the tests", sessionID: id,
            isAppActive: false, isSessionSelected: true)
        XCTAssertEqual(note?.title, "Fix the tests needs input")
        XCTAssertEqual(note?.body, "Approve: rm -rf build")
    }

    func testGateNotifiesWhenSessionUnselected() {
        XCTAssertNotNil(NotificationPolicy.decide(
            .gateArrived(summary: "Question waiting"),
            sessionTitle: "T", sessionID: id,
            isAppActive: true, isSessionSelected: false))
    }

    func testGateStaysQuietWhenWatching() {
        XCTAssertNil(NotificationPolicy.decide(
            .gateArrived(summary: "x"),
            sessionTitle: "T", sessionID: id,
            isAppActive: true, isSessionSelected: true))
    }

    func testShortTurnStaysQuiet() {
        XCTAssertNil(NotificationPolicy.decide(
            .turnCompleted(detail: "done", durationMS: 5_000),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false))
    }

    func testLongTurnNotifiesWithStatusDetail() {
        let note = NotificationPolicy.decide(
            .turnCompleted(detail: "replied with EFFORT-OK", durationMS: 45_000),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false)
        XCTAssertEqual(note?.body, "replied with EFFORT-OK")
    }

    func testAbnormalTerminationAlwaysNotifiesUnlessWatching() {
        XCTAssertNotNil(NotificationPolicy.decide(
            .terminated(exitCode: 1),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false))
        XCTAssertNil(NotificationPolicy.decide(
            .terminated(exitCode: 0),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false),
            "clean exits are not emergencies")
    }

    private let id = UUID()
}

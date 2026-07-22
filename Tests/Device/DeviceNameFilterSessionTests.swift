import Foundation

@main
struct DeviceNameFilterSessionTests {
    struct Item: Equatable {
        let id: Int
        let names: [String]
    }

    static func main() {
        testTrimAndEmptyReset()
        testCaseInsensitiveSubstring()
        testMiddleSpacesArePreserved()
        testAnyCandidateMatches()
        testAllUsesDisplayedName()
        testCompleteAndVisibleCollectionsStaySeparate()
        testObserversReceiveCommittedChangesOnly()
        testDraftDoesNotMutateCommittedQuery()
        print("DeviceNameFilterSessionTests passed")
    }

    static func testTrimAndEmptyReset() {
        let session = DeviceNameFilterSession()
        session.submit("  Room  ")
        precondition(session.query == "Room")
        precondition(session.isActive)
        session.submit("   \n  ")
        precondition(session.query.isEmpty)
        precondition(!session.isActive)
    }

    static func testCaseInsensitiveSubstring() {
        let session = DeviceNameFilterSession()
        session.submit("LIGHT")
        precondition(session.matches("Meeting Light 01"))
        precondition(!session.matches("Switch 01"))
    }

    static func testMiddleSpacesArePreserved() {
        let session = DeviceNameFilterSession()
        session.submit("room  light")
        precondition(session.matches("Room  Light 01"))
        precondition(!session.matches("Room Light 01"))
    }

    static func testAnyCandidateMatches() {
        let session = DeviceNameFilterSession()
        session.submit("floor")
        precondition(session.matches(anyOf: ["Light 01", "First Floor"]))
        precondition(!session.matches(anyOf: ["Light 01", "Meeting Room"]))
    }

    static func testAllUsesDisplayedName() {
        let session = DeviceNameFilterSession()
        session.submit("all")
        precondition(session.matches("ALL"))
        session.submit("全部")
        precondition(session.matches("全部"))
    }

    static func testCompleteAndVisibleCollectionsStaySeparate() {
        let all = [
            Item(id: 1, names: ["Light 01", "First Floor"]),
            Item(id: 2, names: ["Light 02", "Second Floor"]),
            Item(id: 3, names: ["Switch 01"])
        ]
        let session = DeviceNameFilterSession()
        session.submit("first")
        let visible = session.filtered(all, names: { $0.names })
        precondition(all.map(\.id) == [1, 2, 3])
        precondition(visible.map(\.id) == [1])
    }

    static func testObserversReceiveCommittedChangesOnly() {
        let session = DeviceNameFilterSession()
        var received: [String] = []
        let id = session.observe { received.append($0) }
        session.submit(" room ")
        session.submit("room")
        session.reset()
        session.removeObserver(id)
        session.submit("ignored")
        precondition(received == ["", "room", ""])
    }

    static func testDraftDoesNotMutateCommittedQuery() {
        let session = DeviceNameFilterSession()
        session.submit("old")
        var draft = session.query
        draft = "new"
        precondition(draft == "new")
        precondition(session.query == "old")
    }
}

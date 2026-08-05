@main
struct SpaceNodeCapacityPolicyTests {
    private struct Request: Equatable {
        let id: String
        let nodeCost: Int
    }

    static func main() {
        precondition(SpaceNodeCapacityPolicy.maxNodeCount == 500)
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 499,
                inFlightNodeCount: 0
            ) == 1
        )
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 500,
                inFlightNodeCount: 0
            ) == 0
        )
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 498,
                inFlightNodeCount: 1
            ) == 1
        )
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 501,
                inFlightNodeCount: 0
            ) == 0
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedNodeCount(
                existingNodeCount: 499,
                inFlightNodeCount: 0,
                requestedNodeCount: 2
            ) == 1
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedNodeCount(
                existingNodeCount: 500,
                inFlightNodeCount: 0,
                requestedNodeCount: 1
            ) == 0
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedPrefix(
                ["A", "B", "C"],
                existingNodeCount: 498,
                inFlightNodeCount: 1
            ) == ["A"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedPrefix(
                ["A", "B"],
                existingNodeCount: -1,
                inFlightNodeCount: -1
            ) == ["A", "B"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedElements(
                [Request(id: "replacement", nodeCost: 0)],
                existingNodeCount: 500,
                inFlightNodeCount: 0,
                nodeCost: { $0.nodeCost }
            ).map(\.id) == ["replacement"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedElements(
                [
                    Request(id: "replacement", nodeCost: 0),
                    Request(id: "new", nodeCost: 1)
                ],
                existingNodeCount: 499,
                inFlightNodeCount: 0,
                nodeCost: { $0.nodeCost }
            ).map(\.id) == ["replacement", "new"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedElements(
                [
                    Request(id: "newA", nodeCost: 1),
                    Request(id: "newB", nodeCost: 1),
                    Request(id: "replacement", nodeCost: 0)
                ],
                existingNodeCount: 499,
                inFlightNodeCount: 0,
                nodeCost: { $0.nodeCost }
            ).map(\.id) == ["newA", "replacement"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedElements(
                [
                    Request(id: "newA", nodeCost: 1),
                    Request(id: "newB", nodeCost: 1)
                ],
                existingNodeCount: 498,
                inFlightNodeCount: 1,
                nodeCost: { $0.nodeCost }
            ).map(\.id) == ["newA"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedElements(
                [
                    Request(id: "free", nodeCost: -1),
                    Request(id: "new", nodeCost: 1)
                ],
                existingNodeCount: 499,
                inFlightNodeCount: 0,
                nodeCost: { $0.nodeCost }
            ).map(\.id) == ["free", "new"]
        )
        print("SpaceNodeCapacityPolicyTests passed")
    }
}

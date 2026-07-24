struct FastAddTaskCheckpoint<MessageHandle: AnyObject> {
    let lastMessageHandle: MessageHandle
    let verify: () -> Bool
}

struct FastAddTaskCheckpointSource<MessageHandle: AnyObject> {
    let messageHandles: [MessageHandle]
    let verify: () -> Bool
}

struct FastAddTaskCheckpointBatch<MessageHandle: AnyObject> {
    let messageHandles: [MessageHandle]
    let tracker: FastAddTaskCheckpointTracker<MessageHandle>

    init(sources: [FastAddTaskCheckpointSource<MessageHandle>]) {
        var messageHandles: [MessageHandle] = []
        var checkpoints: [FastAddTaskCheckpoint<MessageHandle>] = []

        sources.forEach { source in
            guard let lastMessageHandle = source.messageHandles.last else {
                return
            }
            messageHandles.append(contentsOf: source.messageHandles)
            checkpoints.append(
                FastAddTaskCheckpoint(
                    lastMessageHandle: lastMessageHandle,
                    verify: source.verify
                )
            )
        }

        self.messageHandles = messageHandles
        tracker = FastAddTaskCheckpointTracker(checkpoints: checkpoints)
    }
}

final class FastAddTaskCheckpointTracker<MessageHandle: AnyObject> {
    private enum State {
        case pending
        case succeeded
        case failed
    }

    private struct Entry {
        let checkpoint: FastAddTaskCheckpoint<MessageHandle>
        var state: State
    }

    private var entries: [Entry]

    init(checkpoints: [FastAddTaskCheckpoint<MessageHandle>]) {
        entries = checkpoints.map {
            Entry(checkpoint: $0, state: .pending)
        }
    }

    func recordSuccess(for messageHandle: MessageHandle) {
        guard let index = entries.firstIndex(where: {
            $0.checkpoint.lastMessageHandle === messageHandle
        }) else {
            return
        }
        guard case .pending = entries[index].state else {
            return
        }

        let succeeded = entries[index].checkpoint.verify()
        entries[index].state = succeeded ? .succeeded : .failed
    }

    var hasFailure: Bool {
        entries.contains {
            switch $0.state {
            case .pending, .failed:
                return true
            case .succeeded:
                return false
            }
        }
    }
}

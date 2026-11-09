// @copyright André Trettin

import Foundation
import GroupActivities

/// Runs the `join()` and `leave()` of one `GroupSession` strictly one after the other, off the
/// main actor. Commands are queued from the main actor in call order and one task executes them,
/// so a `leave()` never overlaps a `join()` that is still running; `join()` blocks while it sets
/// up the call's audio session, which the main thread must not wait for. After `leave()` the
/// queue is finished: a later `join()` or `leave()` does nothing.
///
/// `GroupSession` is not `Sendable`. The box below only hands it to the one task that calls these
/// two methods; everything that reads the session's state stays on the main actor.
final class GroupSessionCommandQueue: Sendable {
    private enum Command {
        case join
        case leave
    }

    /// Why `@unchecked`: Apple does not document `GroupSession` as `Sendable`. This relies on
    /// `join()` and `leave()` being plain calls into the system that the framework serialises
    /// itself, and on this box being the only place that calls them off the main actor, one
    /// call at a time (see the command queue above). That is an assumption, not something
    /// TSan can check inside system code. If a hitch from `join()` ever stops mattering,
    /// the safer form is to call both on the main actor
    /// (CODE_AUDIT_Game_Shareplay §3.3).
    private struct SessionBox: @unchecked Sendable {
        let session: GroupSession<RPGActivity>
    }

    private let continuation: AsyncStream<Command>.Continuation

    init(session: GroupSession<RPGActivity>) {
        let box = SessionBox(session: session)
        let (stream, continuation) = AsyncStream.makeStream(of: Command.self)
        self.continuation = continuation
        Task.detached(priority: .userInitiated) {
            for await command in stream {
                switch command {
                case .join:
                    box.session.join()
                case .leave:
                    box.session.leave()
                    return
                }
            }
        }
    }

    deinit {
        continuation.finish()
    }

    func join() {
        continuation.yield(.join)
    }

    func leave() {
        continuation.yield(.leave)
        continuation.finish()
    }
}

// @copyright André Trettin

import Foundation
import AVFoundation
import Synchronization

@MainActor @Observable
public final class AudioListenerCoordinator {
    @ObservationIgnored
    public let playbackCoordinator: AVPlayerPlaybackCoordinator
    @ObservationIgnored
    private let coordinatorDelegate = CoordinatorDelegate()

    public var sharedAudioId: UUID?

    public init(playbackCoordinator: AVPlayerPlaybackCoordinator) {
        self.playbackCoordinator = playbackCoordinator
        self.playbackCoordinator.delegate = coordinatorDelegate
    }

    func coordinatePlayback(of audioId: UUID) {
        guard audioId != sharedAudioId else { return }
        coordinatorDelegate.setAudioId(audioId)
        sharedAudioId = audioId
    }

    /// AVFoundation calls identifierFor(_:) on an arbitrary queue; all mutable state
    /// lives behind the Mutex. @unchecked remains only because NSObject itself is
    /// not Sendable — the type carries no other unguarded state.
    private final class CoordinatorDelegate: NSObject, AVPlayerPlaybackCoordinatorDelegate, @unchecked Sendable {
        private let audioId = Mutex<UUID?>(nil)

        func setAudioId(_ audioId: UUID?) {
            self.audioId.withLock { $0 = audioId }
        }

        func playbackCoordinator(_ coordinator: AVPlayerPlaybackCoordinator,
                                 identifierFor playerItem: AVPlayerItem) -> String {
            audioId.withLock { $0 }?.uuidString ?? UUID().uuidString
        }
    }
}


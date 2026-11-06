// @copyright André Trettin

import Foundation
import AVFoundation
import OSLog
import Synchronization

@MainActor @Observable
public final class AudioListenerCoordinator {
    @ObservationIgnored
    public let playbackCoordinator: AVPlayerPlaybackCoordinator
    @ObservationIgnored
    private let coordinatorDelegate = CoordinatorDelegate()

    public var sharedAudioId: UUID?

    /// The two diagnostics loops below; cancelled with the coordinator, since a new one is made
    /// for every audio engine, also after a media-services reset.
    @ObservationIgnored
    private var diagnosticsTasks: [Task<Void, Never>] = []

    public init(playbackCoordinator: AVPlayerPlaybackCoordinator) {
        self.playbackCoordinator = playbackCoordinator
        self.playbackCoordinator.delegate = coordinatorDelegate
        logCoordinationChanges()
    }

    isolated deinit {
        diagnosticsTasks.forEach { $0.cancel() }
    }

    /// Logs who takes part in the coordinated playback and what holds it up. A SharePlay
    /// player only loads the track and relies on the coordinator to start it with the game
    /// master's playback, so when nothing plays, this is where the reason shows.
    private func logCoordinationChanges() {
        let coordinator = playbackCoordinator
        let center = NotificationCenter.default
        let participantsTask = Task { @MainActor [weak self] in
            for await _ in center.notifications(named: AVPlaybackCoordinator.otherParticipantsDidChangeNotification, object: coordinator) {
                guard let self else { return }
                Logger.audioController.debug("🎧 Coordinated playback participants: \(self.participantsDescription, privacy: .public)")
            }
        }
        let suspensionTask = Task { @MainActor [weak self] in
            for await _ in center.notifications(named: AVPlaybackCoordinator.suspensionReasonsDidChangeNotification, object: coordinator) {
                guard let self else { return }
                let reasons = coordinator.suspensionReasons.map(\.rawValue).joined(separator: ", ")
                Logger.audioController.debug("🎧 Coordinated playback suspended locally: [\(reasons, privacy: .public)], participants: \(self.participantsDescription, privacy: .public)")
            }
        }
        diagnosticsTasks = [participantsTask, suspensionTask]
    }

    private var participantsDescription: String {
        let participants = playbackCoordinator.otherParticipants.map { participant in
            let reasons = participant.suspensionReasons.map(\.rawValue).joined(separator: ", ")
            return "\(participant.identifier.uuidString.prefix(8)) ready: \(participant.isReadyToPlay) suspended: [\(reasons)]"
        }
        return participants.isEmpty ? "none" : participants.joined(separator: "; ")
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


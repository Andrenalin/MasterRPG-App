// @copyright André Trettin

import Foundation
import AVFoundation

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

    func coordinatePlayback(of audioId: UUID) async {
        guard audioId != sharedAudioId else { return }
        await updateSharedAudio(audioId: audioId)
    }

    private func updateSharedAudio(audioId: UUID) async {
        coordinatorDelegate.setAudioId(audioId)
        sharedAudioId = audioId
    }

    private final class CoordinatorDelegate: NSObject, AVPlayerPlaybackCoordinatorDelegate {
        nonisolated(unsafe) private var audioId: UUID?

        @MainActor
        func setAudioId(_ audioId: UUID?) {
            self.audioId = audioId
        }
        
        func playbackCoordinator(_ coordinator: AVPlayerPlaybackCoordinator,
                                 identifierFor playerItem: AVPlayerItem) -> String {
            guard let audioId else { return "-1" }
            return "\(audioId)"
        }
    }
}


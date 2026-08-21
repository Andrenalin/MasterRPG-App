// @copyright André Trettin

import AVFoundation
import CoreRPG
import Foundation
import os.log

protocol AudioPlayerSessionDelegate: Sendable {
    @MainActor func routeChanged()
    @MainActor func beginInterruption() -> Bool
    @MainActor func endInterruption(wasPlaying: Bool)
    @MainActor func resetMediaService()
}

@MainActor
final class AudioPlayerSessionModel: Sendable {
    weak var delegate: (AnyObject & AudioPlayerSessionDelegate)?
    private(set) var audioSessionObservers: [NSObjectProtocol] = []
    private(set) var wasPlaying = false
    
    init(delegate: (AnyObject & AudioPlayerSessionDelegate)) {
        self.delegate = delegate
    }
    
    func reset(audioSessionObservers: [NSObjectProtocol]) {
        self.audioSessionObservers = audioSessionObservers
    }
    
    func reset(wasPlaying: Bool) {
        self.wasPlaying = wasPlaying
    }
}

final class AudioPlayerSession: Sendable {
#if !os(macOS)
    private let audioSession = AVAudioSession.sharedInstance()
#endif
    private let model: AudioPlayerSessionModel
    
    @MainActor
    init(delegate: (AnyObject & AudioPlayerSessionDelegate)) {
        self.model = AudioPlayerSessionModel(delegate: delegate)
    }

    @MainActor
    func initSession() {
#if !os(macOS)
        setCategory()
        registerSessionNotifications()
        Task { await setActive() }
#endif
    }
}

private extension AudioPlayerSession {
#if !os(macOS)
    func setCategory() {
        do {
            // `.longFormAudio` route sharing (instead of `.default` policy +
            // `.mixWithOthers`) is what tells the system this is background game
            // music, not incidental app noise. With `.mixWithOthers`, the system
            // aggressively ducks our audio the moment a FaceTime/SharePlay call
            // becomes the "primary" audio — that's the reported "quieter music
            // during SharePlay". `.longFormAudio` is Apple's documented policy for
            // exactly this kind of long-form/background audio (Music, Podcasts use
            // it too), and it's what lets `AVPlayerPlaybackCoordinator.coordinate(
            // with:)` (see `AudioListenerCoordinator`) be recognized as the
            // SharePlay activity's own shared audio instead of a ducked bystander.
            //
            // `CategoryOptions` can only be combined with the `.default` policy, so
            // `.allowAirPlay`/`.allowBluetoothHFP`/`.allowBluetoothA2DP` are dropped
            // here — AirPlay (including AirPlay 2) and Bluetooth output routing are
            // already implicit for `.playback` + `.longFormAudio`.
            try audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Logger.audioController.error("An error occurred setting the audio session category: \(error.localizedDescription, privacy: .public)")
        }
    }

    @concurrent
    func setActive() async {
        do {
            // setActive is a blocking AVAudioSession call — keep it off the main actor.
            try audioSession.setActive(true)
        } catch {
            Logger.audioController.error("An error occurred activating the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func registerSessionNotifications() {
        let center = NotificationCenter.default
        var audioSessionObservers: [NSObjectProtocol] = []
        audioSessionObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: audioSession, queue: .main) { [weak self] note in
            self?.handleRouteChange(notification: note)
        })

        audioSessionObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: audioSession, queue: .main) { [weak self] note in
            // Extract the Sendable raw values — the Notification itself must not
            // cross into the MainActor closure.
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            // queue: .main ⇒ delivered on the main thread; assumeIsolated is safe and
            // keeps the wasPlaying write/read strictly ordered (no Task-per-event races).
            assumeMainActorIsolated {
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        })

        audioSessionObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: audioSession, queue: .main) { [weak self] note in
            self?.handleMediaServicesReset(notification: note)
        })
        
        model.reset(audioSessionObservers: audioSessionObservers)
    }

    func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let rawValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }

        let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue)
        guard reason == .oldDeviceUnavailable,
              let previousRoute = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
              let previousOutput = previousRoute.outputs.first,
              previousOutput.portType == .headphones else { return }

        Task {
            await model.delegate?.routeChanged()
        }
    }

    @MainActor
    func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw else { return }

        let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        if type == .began {
            model.reset(wasPlaying: model.delegate?.beginInterruption() ?? false)
        } else if let optionsRaw,
                  AVAudioSession.InterruptionOptions(rawValue: optionsRaw) == .shouldResume {
            let wasPlaying = model.wasPlaying
            Task { [weak self] in
                await self?.setActive()
                self?.model.delegate?.endInterruption(wasPlaying: wasPlaying)
            }
        }
    }

    func handleMediaServicesReset(notification _: Notification) {
        Task {
            await removeAllSessionObservers()
            await model.delegate?.resetMediaService()
        }
    }
#endif

    @MainActor
    func removeAllSessionObservers() {
        model.audioSessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

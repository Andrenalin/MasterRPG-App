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
    private(set) var audioSessionObservers: [Task<Void, Never>] = []
    private(set) var wasPlaying = false
    private(set) var configureTask: Task<Void, Never>?
    
    init(delegate: (AnyObject & AudioPlayerSessionDelegate)) {
        self.delegate = delegate
    }
    
    func reset(audioSessionObservers: [Task<Void, Never>]) {
        self.audioSessionObservers = audioSessionObservers
    }
    
    func reset(wasPlaying: Bool) {
        self.wasPlaying = wasPlaying
    }

    func reset(configureTask: Task<Void, Never>?) {
        self.configureTask = configureTask
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
        registerSessionNotifications()
        model.reset(configureTask: Task { await configureAndActivate() })
#endif
    }

    /// Whether the initial category/activation is still pending. See CODE_AUDIT_20 §3.2.
    @MainActor
    var isConfiguring: Bool {
        model.configureTask != nil
    }

    /// Waits for the initial category/activation so the first track never starts under the
    /// default category (silenced by the ring switch). Returns at once after the first wait.
    /// See CODE_AUDIT_19 §3.5.
    @MainActor
    func waitUntilConfigured() async {
        guard let task = model.configureTask else { return }
        await task.value
        model.reset(configureTask: nil)
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

    /// Both `setCategory` and `setActive` are blocking AVAudioSession (SessionCore) calls
    /// that can stall the main thread while a FaceTime/SharePlay call is active, so both
    /// run off the main actor, category first. See CODE_AUDIT_18 §7.2.
    @concurrent
    func configureAndActivate() async {
        setCategory()
        await setActive()
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

    /// Observes the session's notifications as async sequences on the main actor, so the
    /// handlers run isolated and need no `assumeMainActorIsolated`. The tasks end with
    /// `removeAllSessionObservers()`. See CODE_AUDIT_20 §4.3.
    @MainActor
    func registerSessionNotifications() {
        let center = NotificationCenter.default
        let session = audioSession
        var observers: [Task<Void, Never>] = []
        observers.append(Task { @MainActor [weak self] in
            for await note in center.notifications(named: AVAudioSession.routeChangeNotification, object: session) {
                self?.handleRouteChange(notification: note)
            }
        })

        observers.append(Task { @MainActor [weak self] in
            for await note in center.notifications(named: AVAudioSession.interruptionNotification, object: session) {
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        })

        observers.append(Task { @MainActor [weak self] in
            for await note in center.notifications(named: AVAudioSession.mediaServicesWereResetNotification, object: session) {
                self?.handleMediaServicesReset(notification: note)
            }
        })

        model.reset(audioSessionObservers: observers)
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
        model.audioSessionObservers.forEach { $0.cancel() }
    }
}

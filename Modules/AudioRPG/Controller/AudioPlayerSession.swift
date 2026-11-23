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
    /// The last queued `setActive`/`setInactive`: each new change waits for it, so the session
    /// ends in the state of the last request. See CODE_AUDIT_26 §3.12.
    private(set) var sessionChangeTask: Task<Void, Never>?
    /// Whether this session activated the audio session and has not given it back.
    private(set) var isActive = false
    /// Bumped by every interruption that begins: a resume that waited for the session to
    /// activate checks it, so it does not play inside a newer interruption.
    private(set) var interruptionGeneration = 0
    
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

    func reset(sessionChangeTask: Task<Void, Never>?) {
        self.sessionChangeTask = sessionChangeTask
    }

    func reset(isActive: Bool) {
        self.isActive = isActive
    }

    func beginInterruptionGeneration() -> Int {
        interruptionGeneration += 1
        return interruptionGeneration
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

    /// Registers the notifications and sets the category. The session is not activated here:
    /// activating it interrupts the user's Music or podcast, which must wait for audio that
    /// really plays (see `activate()`). See CODE_AUDIT_Audio2 §5.10.
    @MainActor
    func initSession() {
#if !os(macOS)
        registerSessionNotifications()
        model.reset(configureTask: Task { await configure() })
#endif
    }

    /// Whether the category is still being set or the session is not active yet, so a play has
    /// to go through `activate()` first. See CODE_AUDIT_20 §3.2.
    @MainActor
    var needsActivation: Bool {
#if os(macOS)
        false
#else
        model.configureTask != nil || !model.isActive
#endif
    }

    /// Waits for the initial category so the first track never starts under the default category
    /// (silenced by the ring switch). Returns at once after the first wait.
    /// See CODE_AUDIT_19 §3.5.
    @MainActor
    func waitUntilConfigured() async {
        guard let task = model.configureTask else { return }
        await task.value
        model.reset(configureTask: nil)
    }

    /// Waits for the category and activates the session, once, for the audio about to play.
    @MainActor
    func activate() async {
#if !os(macOS)
        await waitUntilConfigured()
        guard !model.isActive else { return }
        await enqueueSessionChange(active: true).value
        model.reset(isActive: true)
#endif
    }

    /// Gives the audio session back, telling other apps they may resume.
    @MainActor
    func deactivate() {
#if !os(macOS)
        guard model.isActive, model.configureTask == nil else { return }
        model.reset(isActive: false)
        enqueueSessionChange(active: false)
#endif
    }
}

private extension AudioPlayerSession {
#if !os(macOS)
    /// Queues a session (de)activation behind the one before it. `setActive`/`setInactive` are
    /// `@concurrent`, so two bare tasks could run in either order and leave the session in the
    /// state of the one that finished last.
    @MainActor
    @discardableResult
    func enqueueSessionChange(active: Bool) -> Task<Void, Never> {
        let previous = model.sessionChangeTask
        let task = Task {
            await previous?.value
            if active {
                await setActive()
            } else {
                await setInactive()
            }
        }
        model.reset(sessionChangeTask: task)
        return task
    }

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
            Logger.audioController.error("An error occurred setting the audio session category: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    /// `setCategory` and `setActive` are blocking AVAudioSession (SessionCore) calls that can
    /// stall the main thread while a FaceTime/SharePlay call is active, so both run off the
    /// main actor. See CODE_AUDIT_18 §7.2.
    @concurrent
    func configure() async {
        setCategory()
    }

    @concurrent
    func setInactive() async {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Logger.audioController.error("An error occurred deactivating the audio session: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    @concurrent
    func setActive() async {
        do {
            // setActive is a blocking AVAudioSession call — keep it off the main actor.
            try audioSession.setActive(true)
        } catch {
            Logger.audioController.error("An error occurred activating the audio session: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Observes the session's notifications as async sequences on the main actor, so the
    /// handlers run isolated and need no `assumeMainActorIsolated`. The tasks end with
    /// `removeAllSessionObservers()`. See CODE_AUDIT_20 §4.3.
    @MainActor
    func registerSessionNotifications() {
        // A second registration would leave the first observers running next to the new ones,
        // so every notification was handled twice. See CODE_AUDIT_28 §8.4.
        removeAllSessionObservers()
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

    @MainActor
    func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let rawValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }

        let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue)
        // Any external output that went away pauses, not only wired headphones: AirPods, a
        // Bluetooth speaker or USB audio would otherwise continue from the device speaker.
        // See CODE_AUDIT_23 §5.18.
        guard reason == .oldDeviceUnavailable,
              let previousRoute = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
              previousRoute.outputs.contains(where: { $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver }) else { return }

        model.delegate?.routeChanged()
    }

    @MainActor
    func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw else { return }

        let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        if type == .began {
            _ = model.beginInterruptionGeneration()
            // The system deactivated the session; the next play must activate it again.
            // See CODE_AUDIT_26 §5.101.
            model.reset(isActive: false)
            model.reset(wasPlaying: model.delegate?.beginInterruption() ?? false)
        } else if let optionsRaw,
                  AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
            let wasPlaying = model.wasPlaying
            let generation = model.interruptionGeneration
            Task { [weak self] in
                await self?.setActive()
                guard let self, self.model.interruptionGeneration == generation else { return }
                self.model.reset(isActive: true)
                self.model.delegate?.endInterruption(wasPlaying: wasPlaying)
            }
        } else {
            // The interruption ended without a request to resume: what was playing stays paused.
            model.delegate?.endInterruption(wasPlaying: false)
        }
    }

    @MainActor
    func handleMediaServicesReset(notification _: Notification) {
        removeAllSessionObservers()
        // The reset deactivated the session and replaces the player: both start over.
        model.reset(isActive: false)
        model.delegate?.resetMediaService()
    }
#endif

    @MainActor
    func removeAllSessionObservers() {
        model.audioSessionObservers.forEach { $0.cancel() }
        model.reset(audioSessionObservers: [])
    }
}

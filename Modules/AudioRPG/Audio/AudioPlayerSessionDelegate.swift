// @copyright André Trettin

import AVFoundation
import Foundation

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
        setActive()
#endif
    }
}

private extension AudioPlayerSession {
#if !os(macOS)
    func setCategory() {
        do {
            #if os(tvOS)
            try audioSession.setCategory(.playback, mode: .default, policy: .default, options: [.allowAirPlay, .mixWithOthers])
            #else
            try audioSession.setCategory(.playback, mode: .default, policy: .default, options: [.allowAirPlay, .mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP])
            #endif
        } catch {
            print("an error occurred when audio session category.\n \(error)")
        }
    }

    func setActive() {
        do {
            try audioSession.setActive(true)
        } catch {
            print("an error occurred when audio session activation.\n \(error)")
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
            self?.handleInterruption(notification: note)
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

    func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let rawValue = info[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        
        let type = AVAudioSession.InterruptionType(rawValue: rawValue)
        if type == .began {
            Task { @MainActor in
                model.reset(wasPlaying: model.delegate?.beginInterruption() ?? false)
            }
        } else {
            if let rawValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: rawValue)
                if options == .shouldResume {
                    setActive()
                    Task{ @MainActor in
                        model.delegate?.endInterruption(wasPlaying: model.wasPlaying)
                    }
                }
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

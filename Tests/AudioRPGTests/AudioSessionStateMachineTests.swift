// @copyright André Trettin

#if os(iOS) && canImport(Testing)
import AVFoundation
import Foundation
import MediaPlayer
import Testing

@testable import AudioRPG

/// CODE_AUDIT_26 §10.5: interruption, media-services reset and the Now Playing throttle.
/// The session's own notifications drive it, so the tests post them the way the system does.
@Suite("Audio session state machine", .serialized)
@MainActor
struct AudioSessionStateMachineTests {
    @MainActor
    private final class DelegateSpy: AudioPlayerSessionDelegate {
        var beginCalls = 0
        var ended: [Bool] = []
        var resets = 0
        var routeChanges = 0
        var wasPlayingOnBegin = true

        func routeChanged() { routeChanges += 1 }
        func beginInterruption() -> Bool {
            beginCalls += 1
            return wasPlayingOnBegin
        }
        func endInterruption(wasPlaying: Bool) { ended.append(wasPlaying) }
        func resetMediaService() { resets += 1 }
    }

    private func post(interruption type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions? = nil) {
        var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let options { userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func makeSession(_ spy: DelegateSpy) -> AudioPlayerSession {
        let session = AudioPlayerSession(delegate: spy)
        session.initSession()
        return session
    }

    @Test("An interruption that begins asks the delegate once and the session has to be activated again")
    func interruptionBegins() async {
        let spy = DelegateSpy()
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        post(interruption: .began)

        #expect(await waitUntil { spy.beginCalls == 1 })
        #expect(session.needsActivation, "the system deactivated the session")
    }

    @Test("An interruption that ends with shouldResume resumes what was playing")
    func endedWithResume() async {
        let spy = DelegateSpy()
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        post(interruption: .began)
        #expect(await waitUntil { spy.beginCalls == 1 })
        post(interruption: .ended, options: .shouldResume)

        #expect(await waitUntil { !spy.ended.isEmpty })
        #expect(spy.ended == [true])
        _ = session
    }

    @Test("An interruption that ends with shouldResume keeps a paused player paused")
    func endedWithResumeWhileNotPlaying() async {
        let spy = DelegateSpy()
        spy.wasPlayingOnBegin = false
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        post(interruption: .began)
        #expect(await waitUntil { spy.beginCalls == 1 })
        post(interruption: .ended, options: .shouldResume)

        #expect(await waitUntil { !spy.ended.isEmpty })
        #expect(spy.ended == [false])
        _ = session
    }

    @Test("An interruption that ends without shouldResume leaves everything paused")
    func endedWithoutResume() async {
        let spy = DelegateSpy()
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        post(interruption: .began)
        #expect(await waitUntil { spy.beginCalls == 1 })
        post(interruption: .ended)

        #expect(await waitUntil { !spy.ended.isEmpty })
        #expect(spy.ended == [false])
        _ = session
    }

    @Test("A second interruption begins again and asks the delegate again")
    func secondBegan() async {
        let spy = DelegateSpy()
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        post(interruption: .began)
        post(interruption: .began)

        #expect(await waitUntil { spy.beginCalls == 2 })
        _ = session
    }

    @Test("A notification without an interruption type is ignored")
    func missingTypeIgnored() async {
        let spy = DelegateSpy()
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [:]
        )
        post(interruption: .began)

        #expect(await waitUntil { spy.beginCalls == 1 })
        #expect(spy.ended.isEmpty)
        _ = session
    }

    @Test("A media-services reset tells the delegate once and stops observing the old session")
    func mediaServicesReset() async {
        let spy = DelegateSpy()
        let session = makeSession(spy)
        await session.waitUntilConfigured()

        NotificationCenter.default.post(
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        #expect(await waitUntil { spy.resets == 1 })
        #expect(session.needsActivation)

        post(interruption: .began)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(spy.beginCalls == 0, "the observers of the old session are gone")
        #expect(spy.resets == 1)
    }

    // MARK: - Now Playing throttle

    private func nowPlayingElapsed() -> Float? {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Float
    }

    @Test("The Now Playing position is written on a change of state or a jump, not on every tick")
    func nowPlayingThrottle() {
        MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        MediaPlayerCoordinator.handlePlaybackChange(playing: true, rate: 1, position: 10, duration: 100)
        #expect(nowPlayingElapsed() == 10, "the first tick is written")

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        MediaPlayerCoordinator.handlePlaybackChange(playing: true, rate: 1, position: 10, duration: 100)
        #expect(nowPlayingElapsed() == nil, "the same state and an extrapolated position are not written again")

        MediaPlayerCoordinator.handlePlaybackChange(playing: true, rate: 1, position: 60, duration: 100)
        #expect(nowPlayingElapsed() == 60, "a seek is written")

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        MediaPlayerCoordinator.handlePlaybackChange(playing: false, rate: 0, position: 60, duration: 100)
        #expect(nowPlayingElapsed() == 60, "a pause is written")

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        MediaPlayerCoordinator.handlePlaybackChange(playing: false, rate: 0, position: 60.5, duration: 100)
        #expect(nowPlayingElapsed() == nil, "a paused position within the tolerance is not written")

        MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
    }

    @Test("A new item forgets what was written, so its first tick is written again")
    func newItemResetsTheThrottle() {
        MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
        MediaPlayerCoordinator.handlePlaybackChange(playing: true, rate: 1, position: 5, duration: 50)

        MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        MediaPlayerCoordinator.handlePlaybackChange(playing: true, rate: 1, position: 5, duration: 50)

        #expect(nowPlayingElapsed() == 5)
        MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
    }
}
#endif

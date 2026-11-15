// @copyright André Trettin

import AppIntentsTesting
import XCTest

/// The Audio module's playback intents. Create / query / delete are shared in `ItemIntentTests`.
/// See CODE_AUDIT_AppIntents §4.6.
@available(iOS 27, macOS 27, *)
final class AudioIntentTests: AppIntentsUITestCase {
    func testPauseAudioRunsWithoutAnythingPlaying() async throws {
        try await definitions.intents["PauseAudioIntent"].makeIntent().run()
    }

    /// A created audio has no file, so its playlist cannot load; the intent reports that
    /// instead of claiming success (CODE_AUDIT_26 §5.100).
    func testPlayAudioFailsForAnAudioWithoutAFile() async throws {
        let (audio, _) = try await createItem(.audio)

        do {
            try await definitions.intents["PlayAudioIntent"].makeIntent(target: audio).run()
            XCTFail("An audio without a file must not report success.")
        } catch {
            // Expected: the audio could not be played.
        }
        try await definitions.intents["PauseAudioIntent"].makeIntent().run()
    }

    func testPlayAudioFailsForADeletedAudio() async throws {
        let (audio, _) = try await createItem(.audio)
        try await delete(.audio, [audio])

        do {
            try await definitions.intents["PlayAudioIntent"].makeIntent(target: audio).run()
            XCTFail("A deleted audio must not be played.")
        } catch {
            // Expected.
        }
    }
}

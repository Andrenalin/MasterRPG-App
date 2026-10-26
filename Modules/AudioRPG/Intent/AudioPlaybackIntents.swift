// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

/// Plays an audio track, or the playlist of an audio folder, through the app's own player, so a
/// game master can start the music hands-free (Siri, AirPods, Action button). It takes the same
/// path as the play button: `GameController.play(id:shouldPlay:)`. See CODE_AUDIT_AppIntents §4.6.
struct PlayAudioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Audio"
    static let description = IntentDescription("Play a track or playlist from your audio collection")

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$target)")
    }

    @Parameter(title: "Audio", requestValueDialog: "Which audio do you want to play?")
    var target: AudioEntity

    @Dependency var root: AudioRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // `target` may have been deleted since it was cached.
        let model = try requiredIntentTarget(
            root.itemController.itemSync(for: target.id),
            parameter: $target,
            prompt: "Which audio do you want to play?"
        )
        try await root.gameController.play(id: model.id, shouldPlay: true)
        return .result(dialog: "Playing \"\(target.name)\".")
    }
}

/// Pauses the audio that is playing.
struct PauseAudioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause Audio"
    static let description = IntentDescription("Pause the audio that is playing")

    @Dependency var root: AudioRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        root.audioController.pause()
        return .result(dialog: "Paused the audio.")
    }
}

#if os(iOS)
extension PlayAudioIntent: TargetContentProvidingIntent {}
extension PauseAudioIntent: TargetContentProvidingIntent {}
#endif

#endif

// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

/// Plays an audio track, or the playlist of an audio folder, through the app's own player, so a
/// game master can start the music hands-free (Siri, AirPods, Action button). It takes the same
/// path as the play button: while a game runs the play is sent through the game, so the players
/// hear it too (`AudioRootModel.playFromIntent`). See CODE_AUDIT_AppIntents §4.6.
public struct PlayAudioIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Play Audio"
    public static let description = IntentDescription(
        "Plays a track, or the playlist of an audio folder, in the app's player.",
        categoryName: "Audio",
        searchKeywords: ["music", "sound", "playlist", "ambience"]
    )

    public static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$target)")
    }

    @Parameter(title: "Audio", requestValueDialog: .localized("Which audio do you want to play?", bundle: .module))
    var target: AudioEntity

    @Dependency var root: AudioRootModel

    public init() {}

    init(target: AudioEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // `target` may have been deleted since it was cached.
        let model = try requiredIntentTarget(
            root.itemController.itemSync(for: target.id),
            parameter: $target,
            prompt: .localized("Which audio do you want to play?", bundle: .module)
        )
        try await root.playFromIntent(id: model.id)
        return .result(dialog: .localized("Playing \"\(target.name)\".", bundle: .module))
    }
}

/// Pauses the audio that is playing.
public struct PauseAudioIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Pause Audio"
    public static let description = IntentDescription(
        "Pauses the audio that is playing in the app.",
        categoryName: "Audio",
        searchKeywords: ["music", "stop", "silence"]
    )

    @Dependency var root: AudioRootModel

    public init() {}

    /// Playback needs no database, so the three playback-only intents answer at once, also on a
    /// cold launch. See CODE_AUDIT_Since_3.0.1 §5.20, §5.22.
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard root.audioController.model.isPlaying else {
            return .result(dialog: .localized("There is no audio playing.", bundle: .module))
        }
        root.pauseFromIntent()
        return .result(dialog: .localized("Paused the audio.", bundle: .module))
    }
}

/// Plays the paused audio on, where Play needs a track. See CODE_AUDIT_AppIntents3 §4.13.
public struct ResumeAudioIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Resume Audio"
    public static let description = IntentDescription(
        "Plays the paused audio on from where it stopped.",
        categoryName: "Audio",
        searchKeywords: ["music", "continue", "play"]
    )

    @Dependency var root: AudioRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = root.audioController.model
        guard let index = player.currentIndex, player.playList.indices.contains(index) else {
            return .result(dialog: .localized("There is no audio to resume.", bundle: .module))
        }
        let title = player.playList[index].title
        if !player.isPlaying {
            // Restarts a finished track, as the player's play button does.
            root.resumeFromIntent()
        }
        return .result(dialog: .localized("Playing \"\(title)\".", bundle: .module))
    }
}

/// Skips to the next track of the playlist, like the remote command. See CODE_AUDIT_AppIntents3 §4.13.
public struct NextTrackIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Next Track"
    public static let description = IntentDescription(
        "Skips to the next track of the playlist that is playing in the app.",
        categoryName: "Audio",
        searchKeywords: ["music", "skip", "playlist"]
    )

    @Dependency var root: AudioRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = root.audioController.model
        guard let index = player.currentIndex else {
            return .result(dialog: .localized("There is no audio playing.", bundle: .module))
        }
        guard player.playList.indices.contains(index + 1) else {
            return .result(dialog: .localized("This is the last track.", bundle: .module))
        }
        let title = player.playList[index + 1].title
        root.nextTrackFromIntent()
        return .result(dialog: .localized("Playing \"\(title)\".", bundle: .module))
    }
}

/// What the playback intents do. While a game runs (`runningGameActions` is not `nil`) they go
/// through the game like the player's buttons, so Siri and Shortcuts play, pause and skip for
/// every player; without a game they act on this device.
extension AudioRootModel {
    @MainActor
    func playFromIntent(id: UUID) async throws {
        let actions = runningGameActions()
        try await startPlayback(id: id, isGameRunning: actions != nil, networkActions: actions)
    }

    @MainActor
    func pauseFromIntent() {
        let actions = runningGameActions()
        pause(isGameRunning: actions != nil, networkActions: actions)
    }

    @MainActor
    func resumeFromIntent() {
        let actions = runningGameActions()
        togglePlayback(isGameRunning: actions != nil, networkActions: actions)
    }

    @MainActor
    func nextTrackFromIntent() {
        let actions = runningGameActions()
        skip(offsetBy: 1, isGameRunning: actions != nil, networkActions: actions)
    }
}

extension AudioRootModel {
    /// Donates a start from the play button, so Siri learns which music belongs to a session.
    /// Throttled per item, like dice rolls. See CODE_AUDIT_AppIntents3 §4.13.
    @MainActor
    func donatePlay(of itemId: UUID) {
        IntentDonations.startThrottledDonation(for: itemId) { [self] in
            guard let model = itemController.itemSync(for: itemId) else { return nil }
            return PlayAudioIntent(target: AudioEntity(root: self, model: model))
        }
    }
}

#if os(iOS)
extension PlayAudioIntent: TargetContentProvidingIntent {}
extension PauseAudioIntent: TargetContentProvidingIntent {}
extension ResumeAudioIntent: TargetContentProvidingIntent {}
extension NextTrackIntent: TargetContentProvidingIntent {}
#endif

#endif

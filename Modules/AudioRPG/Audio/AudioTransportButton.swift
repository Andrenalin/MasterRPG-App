// @copyright André Trettin

import CoreRPG
import SwiftUI

/// One of the transport buttons of the audio players: previous, play/pause and next. Every
/// audio surface shows the same buttons with the same rules (what disables them, how they are
/// labelled, that they go through the game when one runs); a surface only sets how big and how
/// styled they are. See CODE_AUDIT_Audio2 §8.2.
struct AudioTransportButton: View {
    enum Kind {
        case previous
        case playPause
        case next
    }

    /// The symbols of the play/pause button.
    enum PlayPauseSymbols {
        case glyph
        case circle
    }

    let kind: Kind
    var font: Font = .title3
    /// The side of the tap target (its minimum for a side button), or `nil` for the size of the
    /// symbol.
    var side: CGFloat?
    var playPauseSymbols: PlayPauseSymbols = .glyph
    /// A material circle behind the symbol.
    var hasCircleBackground = false

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let model = root.audioPlayerModel
        Button {
            withAnimation(.default.reduced(if: reduceMotion)) {
                perform()
            }
        } label: {
            Label {
                title(isPlaying: model.isPlaying)
            } icon: {
                Image(systemName: symbolName(isPlaying: model.isPlaying))
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
            }
            .labelStyle(.iconOnly)
            .font(font)
            .padding(hasCircleBackground ? 8 : 0)
            .background {
                if hasCircleBackground {
                    Circle().fill(.regularMaterial)
                }
            }
            .frame(minWidth: side, minHeight: side)
            .contentShape(.rect)
        }
        .accessibilityHint(hint(isPlaying: model.isPlaying))
        .disabled(isDisabled(model))
    }

    private func perform() {
        let isGameRunning = appGameStateModel.isGameRunning
        switch kind {
        case .previous:
            root.skip(offsetBy: -1, isGameRunning: isGameRunning, networkActions: networkActions)
        case .playPause:
            root.togglePlayback(isGameRunning: isGameRunning, networkActions: networkActions)
        case .next:
            root.skip(offsetBy: 1, isGameRunning: isGameRunning, networkActions: networkActions)
        }
    }

    /// Previous and next need a neighbour in the playlist, play needs a playlist.
    private func isDisabled(_ model: AudioPlayerModel) -> Bool {
        switch kind {
        case .previous: !model.hasPrev
        case .playPause: model.playList.isEmpty
        case .next: !model.hasNext
        }
    }

    private func title(isPlaying: Bool) -> Text {
        switch kind {
        case .previous: Text("Previous Track", bundle: .module)
        case .playPause: isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module)
        case .next: Text("Next Track", bundle: .module)
        }
    }

    private func hint(isPlaying: Bool) -> Text {
        switch kind {
        case .previous: Text("Play the previous track in the playlist", bundle: .module)
        case .playPause: isPlaying ? Text("Pause playback", bundle: .module) : Text("Resume playback", bundle: .module)
        case .next: Text("Play the next track in the playlist", bundle: .module)
        }
    }

    private func symbolName(isPlaying: Bool) -> String {
        switch kind {
        case .previous:
            "backward.fill"
        case .next:
            "forward.fill"
        case .playPause:
            switch playPauseSymbols {
            case .glyph: isPlaying ? "pause.fill" : "play.fill"
            case .circle: isPlaying ? "pause.circle.fill" : "play.circle.fill"
            }
        }
    }
}

#Preview(traits: .mockData) {
    HStack {
        AudioTransportButton(kind: .previous)
        AudioTransportButton(kind: .playPause, font: .title2)
        AudioTransportButton(kind: .next)
    }
    .buttonStyle(.plain)
    .padding()
}

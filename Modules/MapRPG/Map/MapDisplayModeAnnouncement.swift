// @copyright André Trettin

import SwiftUI

/// The display mode the room editor just switched to, announced for a moment in the middle of
/// the map. A new value (new `id`) restarts the announcement, also for a repeated mode.
struct MapDisplayModeAnnouncement: Equatable, Identifiable {
    let id = UUID()
    let mode: MapDisplayMode
}

extension MapDisplayMode {
    /// The name of the mode: the game master sees every room, the player preview what the
    /// players see, the viewer the clear map.
    var announcementTitle: LocalizedStringKey {
        switch self {
        case .master: "Game Master"
        case .player: "Player"
        case .reader: "Viewer"
        }
    }

    /// Same wording as the first-switch tip (`MapDisplayModesTip`).
    var announcementDescription: LocalizedStringKey {
        switch self {
        case .master: "All rooms are visible, hidden ones are highlighted."
        case .player: "Hidden rooms are covered, exactly as your players see the map."
        case .reader: "The map is clear, only the room outlines are drawn."
        }
    }
}

/// Chrome in the style of the battle round announcement: a glass card in the middle of the map
/// that fades out by itself. It never takes touches, so the map stays usable underneath.
struct MapDisplayModeAnnouncementOverlay: View {
    let session: MapEditorSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let announcement = session.displayModeAnnouncement {
                MapDisplayModeAnnouncementCard(mode: announcement.mode)
                    .accessibilityElement(children: .combine)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.18),
            value: session.displayModeAnnouncement
        )
        .task(id: session.displayModeAnnouncement?.id) {
            guard session.displayModeAnnouncement != nil else { return }
            do {
                try await Task.sleep(for: reduceMotion ? .seconds(1.2) : .seconds(2))
            } catch {
                return
            }
            session.displayModeAnnouncement = nil
        }
        .onDisappear {
            session.displayModeAnnouncement = nil
        }
    }
}

private struct MapDisplayModeAnnouncementCard: View {
    let mode: MapDisplayMode

    @ScaledMetric(relativeTo: .largeTitle) private var width: CGFloat = 280

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: mode.toolBarIcon)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)

            Text(mode.announcementTitle, bundle: .module)
                .font(.largeTitle.bold())

            Text(mode.announcementDescription, bundle: .module)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: width)
#if !os(visionOS)
        .glassEffect(in: .rect(cornerRadius: 24))
#endif
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Display mode announcement") {
    MapDisplayModeAnnouncementCard(mode: .player)
        .padding()
}

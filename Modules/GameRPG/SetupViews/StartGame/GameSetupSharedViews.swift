// @copyright André Trettin

import CoreRPG
import SwiftUI

enum GameSetupRole: Int, CaseIterable, Hashable, Identifiable {
#if !os(tvOS)
    case player = 0
    case master = 1
#endif
    case join = 2

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
#if !os(tvOS)
        case .player:
            LocalizedStringResource("Player", bundle: .module)
        case .master:
            LocalizedStringResource("Game Master", bundle: .module)
#endif
        case .join:
            LocalizedStringResource("Join", bundle: .module)
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
#if !os(tvOS)
        case .player:
            LocalizedStringResource("Choose a character and join a shared game.", bundle: .module)
        case .master:
            LocalizedStringResource("Choose an adventure and host the session.", bundle: .module)
#endif
        case .join:
            LocalizedStringResource("Find a nearby game as observer or proxy.", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
#if !os(tvOS)
        case .player: "theatermasks.fill"
        case .master: "wand.and.stars"
#endif
        case .join: "person.2.wave.2.fill"
        }
    }

    static var previewPlayer: GameSetupRole {
#if os(tvOS)
        .join
#else
        .player
#endif
    }

    static var previewMaster: GameSetupRole {
#if os(tvOS)
        .join
#else
        .master
#endif
    }
}

struct GameSetupBackdrop: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            theme.backgroundGradient

            if !reduceTransparency {
                Circle()
                    .fill(theme.tint(for: .adventure).opacity(0.18))
                    .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: 0)
                    .blur(radius: 48)
                    .offset(x: -120, y: -220)

                Circle()
                    .fill(theme.tint(for: .dice).opacity(0.14))
                    .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: 0)
                    .blur(radius: 56)
                    .offset(x: 160, y: 300)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct GameSetupRolePicker: View {
    @Binding var selection: GameSetupRole

    var body: some View {
        Picker(selection: $selection) {
            ForEach(GameSetupRole.allCases) { role in
                Label {
                    Text(role.title)
                } icon: {
                    Image(systemName: role.systemImage)
                }
                .tag(role)
            }
        } label: {
            Text("Your role", bundle: .module)
        }
        .pickerStyle(.segmented)
        .accessibilityHint(Text("Changes the game setup options below.", bundle: .module))
    }
}

struct GameSetupRoleCards: View {
    @Binding var selection: GameSetupRole

    var body: some View {
        Grid {
            GridRow {
                ForEach(GameSetupRole.allCases) { role in
                    Button {
                        selection = role
                    } label: {
                        VStack {
                            Image(systemName: role.systemImage)
                                .font(.title)
                            Text(role.title)
                                .bold()
                            Text(role.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selection == role ? nil : .secondary.opacity(0.35))
                    .accessibilityAddTraits(selection == role ? .isSelected : [])
                }
            }
        }
    }
}

struct GameSetupRoleContent: View {
    let root: GameRoot
    let selection: GameSetupRole

    var body: some View {
        VStack {
            switch selection {
#if !os(tvOS)
            case .player:
                SelectedPlayerView(root: root)
                PlayerStartView(root: root)
            case .master:
                SelectedAdventureView(root: root)
                MasterStartView(root: root)
#endif
            case .join:
                SearchProxyView(root: root)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SupporterWelcomeCard: View {
    let openSupporter: @MainActor () -> Void

    @Environment(\.supporterTier) private var supporterTier
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: openSupporter) {
            HStack {
                SupporterCrownView(tier: supporterTier)
                    .font(.title)

                VStack(alignment: .leading) {
                    if supporterTier == .none {
                        Text("Every adventurer is welcome", bundle: .module)
                            .font(.headline)
                        Text(
                            "Every MasterRPG feature is available to everyone. If the app supports your adventures, you can support its development and receive a crown beside your game name.",
                            bundle: .module
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Welcome back, \(Text(supporterTier.localizedName)).", bundle: .module)
                            .font(.headline)
                        Text(
                            "Thank you for helping keep the adventure going.",
                            bundle: .module
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding()
            .background(
                theme.panelColor.opacity(0.88),
                in: .rect(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens supporter options.", bundle: .module))
    }
}

struct GameSetupStatisticsCard: View {
    let sessionCount: Int
    let openStatistics: @MainActor () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: openStatistics) {
            GameStatisticsEntryLabel(sessionCount: sessionCount)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    theme.panelColor.opacity(0.82),
                    in: .rect(cornerRadius: 20)
                )
        }
        .buttonStyle(.plain)
    }
}

struct GameSetupTipCard: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text("Ready table, happy party", bundle: .module)
                    .bold()
                Text(
                    "Choose your role first. MasterRPG will keep your last adventure or character ready for the next session.",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(theme.tint(for: .adventure))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            theme.panelColor.opacity(0.82),
            in: .rect(cornerRadius: 20)
        )
    }
}

struct GameSetupSectionCard<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            theme.panelColor.opacity(0.86),
            in: .rect(cornerRadius: 24)
        )
    }
}

#Preview("Shared · Backdrop") {
    GameSetupBackdrop()
}

#Preview("Shared · Role picker") {
    @Previewable @State var role = GameSetupRole.previewPlayer

    GameSetupRolePicker(selection: $role)
        .padding()
}

#Preview("Shared · Role cards") {
    @Previewable @State var role = GameSetupRole.previewPlayer

    GameSetupRoleCards(selection: $role)
        .padding()
}

#Preview("Shared · Role content", traits: .mockData) {
    GameSetupRoleContent(
        root: .preview,
        selection: .previewPlayer
    )
    .padding()
}

#Preview("Shared · Supporter welcome") {
    SupporterWelcomeCard(openSupporter: {})
        .padding()
        .environment(\.supporterTier, .gold)
}

#Preview("Shared · Statistics") {
    GameSetupStatisticsCard(
        sessionCount: 42,
        openStatistics: {}
    )
    .padding()
}

#Preview("Shared · Tip") {
    GameSetupTipCard()
        .padding()
}

#Preview("Shared · Section card") {
    GameSetupSectionCard(
        LocalizedStringResource("Preview section", bundle: .module),
        systemImage: "sparkles"
    ) {
        Text("Preview content", bundle: .module)
    }
    .padding()
}

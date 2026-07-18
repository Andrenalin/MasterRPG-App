// @copyright André Trettin

import CoreRPG
import SwiftUI

// MARK: - Domain Models

struct BattleRoundEntry: Identifiable {
    var id: UUID { pin.id }
    var pin: MapPinModel
    var opponent: MapPinModel? = nil
    var root: ItemRootController? = nil
    var sheetRootModel: SheetRootModel? = nil
}

@MainActor @Observable
final class BattleRoundModel {
    var roundCounter: Int = 1
    var entries: [BattleRoundEntry] = []

    func nextRound() {
        withAnimation(.spring(duration: 0.3)) { roundCounter += 1 }
    }

    func move(from source: IndexSet, to destination: Int) {
        withAnimation { entries.move(fromOffsets: source, toOffset: destination) }
    }

    func setOpponent(_ opponent: MapPinModel?, for pinId: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == pinId }) else { return }
        withAnimation { entries[i].opponent = opponent }
    }
}

// MARK: - Platform-Conditional Modifiers

private extension View {
    @ViewBuilder
    func battleInsetGroupedListStyle() -> some View {
        #if os(iOS) || os(visionOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func battleEditMode() -> some View {
        #if os(iOS) || os(visionOS)
        self.environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }

    @ViewBuilder
    func inlineNavBarTitle() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Shared Subviews

private struct PinAvatar: View {
    let pin: MapPinModel
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(pin.color.opacity(0.18))
            Circle().strokeBorder(pin.color, lineWidth: 1.5)
            Text(pin.name.prefix(1).uppercased())
                .font(.system(size: diameter * 0.44, weight: .bold))
                .foregroundStyle(pin.color)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct OpponentSlot: View {
    let opponent: MapPinModel?
    let diameter: CGFloat

    var body: some View {
        if let opp = opponent {
            PinAvatar(pin: opp, diameter: diameter)
        } else {
            ZStack {
                Circle().strokeBorder(.quaternary, lineWidth: 1.5)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: diameter * 0.32))
                    .foregroundStyle(.quaternary)
            }
            .frame(width: diameter, height: diameter)
        }
    }
}

private struct StatsExpansionView: View {
    let entry: BattleRoundEntry

    var body: some View {
        if let root = entry.root, let sheet = entry.sheetRootModel {
            SheetRootView(root: root, rootModel: sheet, linkTypes: EmptyLinkTransferable.self)
                .frame(maxHeight: 280)
        } else {
            Label("No stats linked", systemImage: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - A · Initiative Table
// Dense columnar list — all data visible, drag handles exposed permanently.
// Name tap expands inline stats sheet.
// ─────────────────────────────────────────────────────────────────────────────

struct BattleRoundViewA: View {
    let model: BattleRoundModel
    @State private var expandedId: UUID?

    var body: some View {
        List {
            Section {
                ForEach(model.entries) { entry in
                    BattleRoundRowA(
                        entry: entry,
                        rank: rank(of: entry),
                        isExpanded: expandedId == entry.id,
                        onToggle: { toggle(entry.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
                .onMove(perform: model.move)
            } header: {
                HStack {
                    Label("Round \(model.roundCounter)", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Spacer()
                    Button("Next Round", systemImage: "forward.fill", action: model.nextRound)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .textCase(nil)
                }
                .padding(.bottom, 4)
            }
        }
        .battleInsetGroupedListStyle()
        .battleEditMode()
    }

    private func rank(of entry: BattleRoundEntry) -> Int {
        (model.entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedId = expandedId == id ? nil : id
        }
    }
}

private struct BattleRoundRowA: View {
    let entry: BattleRoundEntry
    let rank: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(entry.pin.color)
                    .frame(width: 22, alignment: .center)

                PinAvatar(pin: entry.pin, diameter: 34)

                Button(action: onToggle) {
                    HStack(spacing: 3) {
                        Text(entry.pin.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if entry.pin.isDead {
                            Image(systemName: "skull")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    OpponentSlot(opponent: entry.opponent, diameter: 28)
                }
            }

            if isExpanded {
                StatsExpansionView(entry: entry)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - B · Initiative Cards
// Floating cards with a color accent stripe — visual-first layout.
// The initiative badge overlays the avatar for quick scanning.
// ─────────────────────────────────────────────────────────────────────────────

struct BattleRoundViewB: View {
    let model: BattleRoundModel
    @State private var expandedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Round \(model.roundCounter)", systemImage: "shield.lefthalf.filled")
                    .font(.title3.bold())
                Spacer()
                Button("Next Round", systemImage: "chevron.right.2", action: model.nextRound)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            List {
                ForEach(model.entries) { entry in
                    BattleRoundCardB(
                        entry: entry,
                        rank: rank(of: entry),
                        isExpanded: expandedId == entry.id,
                        onToggle: { toggle(entry.id) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .onMove(perform: model.move)
            }
            .listStyle(.plain)
            .battleEditMode()
        }
    }

    private func rank(of entry: BattleRoundEntry) -> Int {
        (model.entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }

    private func toggle(_ id: UUID) {
        withAnimation(.spring(duration: 0.25)) {
            expandedId = expandedId == id ? nil : id
        }
    }
}

private struct BattleRoundCardB: View {
    let entry: BattleRoundEntry
    let rank: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(entry.pin.color)
                    .frame(width: 4)

                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        PinAvatar(pin: entry.pin, diameter: 42)
                        Text("\(rank)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(entry.pin.color, in: Circle())
                            .offset(x: 2, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Button(action: onToggle) {
                            HStack(spacing: 4) {
                                Text(entry.pin.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                                    .font(.caption)
                                    .foregroundStyle(entry.pin.color.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                        if entry.pin.isDead {
                            Label("Dead", systemImage: "skull.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("vs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        OpponentSlot(opponent: entry.opponent, diameter: 36)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            .clipShape(.rect(cornerRadius: 10))

            if isExpanded {
                StatsExpansionView(entry: entry)
                    .padding(12)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: isExpanded)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - C · Timeline View
// Numbered circles on the left rail show turn order at a glance.
// Rank 1 (current turn) is highlighted; others are de-emphasized.
// ─────────────────────────────────────────────────────────────────────────────

struct BattleRoundViewC: View {
    let model: BattleRoundModel
    @State private var expandedId: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.entries) { entry in
                    BattleRoundTimelineRowC(
                        entry: entry,
                        rank: rank(of: entry),
                        isExpanded: expandedId == entry.id,
                        onToggle: { toggle(entry.id) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .onMove(perform: model.move)
            }
            .listStyle(.plain)
            .battleEditMode()
            .navigationTitle("Round \(model.roundCounter)")
            .inlineNavBarTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Next Round", systemImage: "chevron.right.2", action: model.nextRound)
                }
            }
        }
    }

    private func rank(of entry: BattleRoundEntry) -> Int {
        (model.entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.22)) {
            expandedId = expandedId == id ? nil : id
        }
    }
}

private struct BattleRoundTimelineRowC: View {
    let entry: BattleRoundEntry
    let rank: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    private var isCurrent: Bool { rank == 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline badge
            ZStack {
                Circle()
                    .fill(isCurrent ? entry.pin.color : Color.secondary.opacity(0.15))
                Circle()
                    .strokeBorder(
                        isCurrent ? entry.pin.color : Color.secondary.opacity(0.3),
                        lineWidth: 1.5
                    )
                Text("\(rank)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(isCurrent ? .white : .secondary)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 9)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    PinAvatar(pin: entry.pin, diameter: isCurrent ? 44 : 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Button(action: onToggle) {
                            HStack(spacing: 4) {
                                Text(entry.pin.name)
                                    .font(isCurrent ? .headline : .subheadline)
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if let opp = entry.opponent {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(opp.name)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        } else if entry.pin.isDead {
                            Label("Dead", systemImage: "skull")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    OpponentSlot(opponent: entry.opponent, diameter: isCurrent ? 38 : 26)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(
                    isCurrent ? entry.pin.color.opacity(0.08) : Color.clear,
                    in: .rect(cornerRadius: 10)
                )

                if isExpanded {
                    StatsExpansionView(entry: entry)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isExpanded)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Previews
// ─────────────────────────────────────────────────────────────────────────────

private extension BattleRoundModel {
    @MainActor
    static func make(round: Int = 3, withOpponents: Bool = true) -> BattleRoundModel {
        let model = BattleRoundModel()
        model.roundCounter = round
        let pins = MapPinModel.previewPins
        model.entries = pins.enumerated().map { index, pin in
            var entry = BattleRoundEntry(pin: pin)
            if withOpponents {
                if index == 0 { entry.opponent = pins[safe: 1] }
                if index == 2 { entry.opponent = pins[safe: 0] }
            }
            return entry
        }
        return model
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("A · Table — Round 3 with opponents") {
    BattleRoundViewA(model: .make())
}

#Preview("A · Table — Round 1 empty opponents") {
    BattleRoundViewA(model: .make(round: 1, withOpponents: false))
}

#Preview("B · Cards — Round 3 with opponents") {
    BattleRoundViewB(model: .make())
}

#Preview("B · Cards — Round 1 empty opponents") {
    BattleRoundViewB(model: .make(round: 1, withOpponents: false))
}

#Preview("C · Timeline — Round 3 with opponents") {
    BattleRoundViewC(model: .make())
}

#Preview("C · Timeline — Round 1 empty opponents") {
    BattleRoundViewC(model: .make(round: 1, withOpponents: false))
}

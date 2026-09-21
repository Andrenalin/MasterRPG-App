// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DiceRollerView: View {
    @State private var selectedDie: DieModel = .die20(color: .G)
    @State private var currentRoll: DiceResultModel?
    @State private var isRolling: Bool = false

    /// Simulated roll-animation duration before the result is computed and shown.
    /// See CODE_AUDIT §9.14.
    private static let rollAnimationDuration: Duration = .seconds(0.6)
    /// Caps how many past rolls are kept in memory and persisted. Without this,
    /// `rollHistory` would grow without bound over a long session, and the full
    /// array is JSON re-encoded/decoded through the shared App Group
    /// `UserDefaults` on every roll and every appearance — costly in this
    /// memory-constrained widget-extension process. See CODE_AUDIT §7.1.
    private static let maxRollHistoryCount = 50
    @State private var rollHistory: [DiceResultModel] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let loadsStoredHistory: Bool

    @Namespace private var glassNamespace

    init(
        selectedDie: DieModel = .die20(color: .G),
        currentRoll: DiceResultModel? = nil,
        rollHistory: [DiceResultModel] = [],
        loadsStoredHistory: Bool = true
    ) {
        _selectedDie = State(initialValue: selectedDie)
        _currentRoll = State(initialValue: currentRoll)
        _rollHistory = State(initialValue: rollHistory)
        self.loadsStoredHistory = loadsStoredHistory
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
#if os(visionOS)
                DiceRollerContentView(
                    currentRoll: currentRoll,
                    selectedDie: selectedDie,
                    isRolling: isRolling,
                    glassNamespace: glassNamespace,
                    rollAction: rollDice
                )
#else
                // Main dice display with Liquid Glass
                GlassEffectContainer(spacing: 40) {
                    DiceRollerContentView(
                        currentRoll: currentRoll,
                        selectedDie: selectedDie,
                        isRolling: isRolling,
                        glassNamespace: glassNamespace,
                        rollAction: rollDice
                    )
                }
#endif

                // Dice type selector with Liquid Glass
                DiceTypeSelectorView(selectedDie: $selectedDie, currentRoll: $currentRoll)

                // Roll history
                if !rollHistory.isEmpty {
                    RollHistoryView(
                        rollHistory: rollHistory,
                        clearAction: {
                            rollHistory.removeAll()
                            saveHistory()
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle(Text("Dice Roller", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                NavigationLink {
                    DiceRollerWidgetConfiguration()
                } label: {
                    Label {
                        Text("Widget Settings", bundle: .main)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .onAppear {
            guard loadsStoredHistory else { return }
            loadHistory()
        }
    }

    // MARK: - Actions

    private func rollDice() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7)) {
            isRolling = true

            // Simulate rolling animation with modern structured concurrency
            Task { @MainActor in
                try? await Task.sleep(for: Self.rollAnimationDuration)

                let rolledDie = selectedDie.roll(resetResults: true, rerollOptions: [])
                let value = rolledDie.result.first ?? selectedDie.die.max

                // Create dice model with the rolled die
                let diceModel = DiceSnapshot(id: UUID(), name: "D\(selectedDie.die.max)", dice: [rolledDie])

                let result = DiceResultModel(
                    diceModel: diceModel,
                    result: .rolled,
                    values: "\(value)",
                    sum: value,
                    checked: false,
                    timeStamp: Date()
                )

                withAnimation(reduceMotion ? nil : .default) {
                    currentRoll = result
                    rollHistory.append(result)
                    if rollHistory.count > Self.maxRollHistoryCount {
                        rollHistory.removeFirst(rollHistory.count - Self.maxRollHistoryCount)
                    }
                    isRolling = false
                }

                // Update widget
                var config = DiceConfiguration.loadFromUserDefaults()
                config.lastRoll = result
                config.selectedDice = diceModel
                config.save()
                DiceWidgetReloader.reloadDiceWidgets()

                // Save history
                saveHistory()
            }
        }
    }

    private func loadHistory() {
        let defaults = UserDefaults.appGroupDefaults
        if let data = defaults?.data(forKey: UserDefaults.DiceKeys.rollHistory),
           let history = try? JSONDecoder().decode([DiceResultModel].self, from: data) {
            // Also trims a larger history persisted before `maxRollHistoryCount`
            // existed, rather than only capping future growth.
            rollHistory = Array(history.suffix(Self.maxRollHistoryCount))
        }
    }

    private func saveHistory() {
        let defaults = UserDefaults.appGroupDefaults
        if let data = try? JSONEncoder().encode(rollHistory) {
            defaults?.set(data, forKey: UserDefaults.DiceKeys.rollHistory)
        }
    }
}

// MARK: - Views

struct DiceRollerContentView: View {
    let currentRoll: DiceResultModel?
    let selectedDie: DieModel
    let isRolling: Bool
    let glassNamespace: Namespace.ID
    let rollAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            if let roll = currentRoll {
                resultDisplay(roll)
#if !os(visionOS)
                    .glassEffectID("result", in: glassNamespace)
#endif
            } else {
                DiceSelectionView(selectedDie: selectedDie)
#if !os(visionOS)
                    .glassEffectID("selection", in: glassNamespace)
#endif
            }

            // Roll button with Liquid Glass
            Button(action: rollAction) {
                HStack {
                    Image(systemName: "dice")
                    Text("Roll D\(selectedDie.die.max)", bundle: .main)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
            }
#if !os(visionOS)
            .buttonStyle(.glassProminent)
#endif
            .disabled(isRolling)
        }
        .padding()
    }

    private func resultDisplay(_ result: DiceResultModel) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(resultColor(for: result.result).opacity(0.2))
                    .frame(width: 120, height: 120)

                Text(verbatim: "\(result.sum)")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(resultColor(for: result.result))
            }
#if !os(visionOS)
            .glassEffect(.regular.tint(resultColor(for: result.result)).interactive())
#endif
            Text(verbatim: result.diceModel.name)
                .font(.title2)
                .bold()

            if result.result == .coup {
                Text("Critical Success!", bundle: .main)
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if result.result == .fumble {
                Text("Critical Failure!", bundle: .main)
                    .font(.headline)
                    .foregroundStyle(.red)
            }
        }
        .rotation3DEffect(
            .degrees(isRolling && !reduceMotion ? 720 : 0),
            axis: (x: 1, y: 1, z: 0)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: result.diceModel.name))
        .accessibilityValue(Text(verbatim: "\(result.sum)"))
    }
}

private struct DiceSelectionView: View {
    let selectedDie: DieModel

    var body: some View {
        VStack(spacing: 12) {
            selectedDie.diceImage(for: selectedDie.die.max)
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            Text(verbatim: "D\(selectedDie.die.max)")
                .font(.title)
                .bold()

            Text("Tap to roll", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
#if !os(visionOS)
        .glassEffect(.regular.interactive())
#endif
    }
}

private struct DiceTypeSelectorView: View {
    @Binding var selectedDie: DieModel
    @Binding var currentRoll: DiceResultModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Dice", bundle: .main)
                .font(.headline)
                .padding(.horizontal)

#if os(visionOS)
            DiceRollerGridView(selectedDie: $selectedDie, currentRoll: $currentRoll)
#else
            GlassEffectContainer(spacing: 16) {
                DiceRollerGridView(selectedDie: $selectedDie, currentRoll: $currentRoll)
            }
#endif
        }
    }
}

struct DiceRollerGridView: View {
    @Binding var selectedDie: DieModel
    @Binding var currentRoll: DiceResultModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach([DieModel.die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)]) { die in
                Button {
                    withAnimation(reduceMotion ? nil : .spring()) {
                        selectedDie = die
                        currentRoll = nil
                    }
                } label: {
                    VStack(spacing: 8) {
                        die.diceImage(for: die.die.max)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        Text(verbatim: "D\(die.die.max)")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
                .overlay {
                    if selectedDie.die == die.die {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.blue, lineWidth: 3)
                    }
                }
                .accessibilityValue(
                    selectedDie.die == die.die
                        ? Text("Selected", bundle: .main)
                        : Text("Not selected", bundle: .main)
                )
            }
        }
        .padding()
    }
}

private struct RollHistoryView: View {
    let rollHistory: [DiceResultModel]
    let clearAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History", bundle: .main)
                    .font(.headline)

                Spacer()

                Button(role: .destructive) {
                    withAnimation(reduceMotion ? nil : .default) {
                        clearAction()
                    }
                } label: {
                    Text("Clear", bundle: .main)
                }
                .font(.caption)
            }
            .padding(.horizontal)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(rollHistory.reversed()) { roll in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(resultColor(for: roll.result).opacity(0.2))
                                    .frame(width: 50, height: 50)

                                Text(verbatim: "\(roll.sum)")
                                    .font(.title3)
                                    .bold()
                                    .foregroundStyle(resultColor(for: roll.result))
                            }

                            Text(verbatim: roll.diceModel.name)
                                .font(.caption2)
                        }
#if !os(visionOS)
                        .glassEffect(.regular)
#endif
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private func resultColor(for result: DiceResultModel.DiceResult) -> Color {
    switch result {
    case .coup:
        return .green
    case .fumble:
        return .red
    case .rolled:
        return .blue
    case .notRolled:
        return .secondary
    }
}

#Preview("In-app dice roller") {
    let roll = DiceResultModel(
        diceModel: DiceModel.previewSnapshot,
        result: .coup,
        values: "1",
        sum: 1,
        checked: false,
        timeStamp: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )

    NavigationStack {
        DiceRollerView(
            currentRoll: roll,
            rollHistory: [roll],
            loadsStoredHistory: false
        )
    }
}

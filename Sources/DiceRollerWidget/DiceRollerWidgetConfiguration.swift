// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

/// Integration view for managing dice roller widget from the main app
struct DiceRollerWidgetConfiguration: View {
    @State private var configuration: DiceConfiguration = .default
    @State private var isGameActive: Bool = false
    @State private var currentGameName: String = ""

    private let loadsStoredConfiguration: Bool

    init(
        configuration: DiceConfiguration = .default,
        isGameActive: Bool = false,
        currentGameName: String = "",
        loadsStoredConfiguration: Bool = true
    ) {
        _configuration = State(initialValue: configuration)
        _isGameActive = State(initialValue: isGameActive)
        _currentGameName = State(initialValue: currentGameName)
        self.loadsStoredConfiguration = loadsStoredConfiguration
    }
    
    var body: some View {
        Form {
            Section {
                Text("Current: \(configuration.selectedDice.name)", bundle: .main)
                    .font(.headline)
            } header: {
                Text("Widget Settings", bundle: .main)
            } footer: {
                Text("The widget displays your last rolled dice configuration", bundle: .main)
            }
            
            Section {
                Toggle(isOn: $isGameActive) {
                    Text("Enable Live Activity", bundle: .main)
                }
                    .onChange(of: isGameActive) { _, newValue in
                        updateGameStatus(isActive: newValue)
                    }
                
                if isGameActive {
                    TextField(text: $currentGameName) {
                        Text("Game Name", bundle: .main)
                    }
                        .onChange(of: currentGameName) { _, newValue in
                            saveGameName(newValue)
                        }
                    
                    NavigationLink {
                        FavoriteDiceManagementView(configuration: $configuration)
                    } label: {
                        HStack {
                            Text("Favorite Dice", bundle: .main)
                            Spacer()
                            Text(verbatim: "\(configuration.favoriteDice.count)/6")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Live Activity", bundle: .main)
            } footer: {
                Text("Show dice rolls in Dynamic Island and Lock Screen during gameplay", bundle: .main)
            }
            
            Section {
                if let lastRoll = configuration.lastRoll {
                    HStack {
                        if let firstDie = lastRoll.diceModel.dice.first {
                            firstDie.diceImage(for: firstDie.result.last ?? firstDie.die.max)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(resultColor(for: lastRoll.result))
                                .accessibilityHidden(true)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(verbatim: "\(lastRoll.sum)")
                                .font(.title)
                                .bold()
                                .foregroundStyle(resultColor(for: lastRoll.result))
                            
                            Text(verbatim: lastRoll.diceModel.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if let timestamp = lastRoll.timestamp {
                            VStack(alignment: .trailing) {
                                Text(timestamp, style: .date)
                                    .font(.caption2)
                                Text(timestamp, style: .time)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button(role: .destructive) {
                        clearHistory()
                    } label: {
                        Text("Clear History", bundle: .main)
                    }
                } else {
                    Text("No rolls yet", bundle: .main)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Last Roll", bundle: .main)
            }
            
            Section {
                Button {
                    // This opens Settings where user can add widget
                    if let _ = URL(string: "App-prefs:root=") {
                        //UIApplication.openSettingsURLString
                        //UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Add Widget to Home Screen", bundle: .main)
                }
                
                Button {
                    DiceWidgetReloader.reloadDiceWidgets()
                } label: {
                    Text("Reload Dice Widgets", bundle: .main)
                }
            } header: {
                Text("Widget Management", bundle: .main)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liquid Glass Design", bundle: .main)
                        .font(.headline)
                    
                    Text(
                        "The dice roller widget uses Apple's new Liquid Glass design, which creates a beautiful glass-like effect that blurs content behind it and reflects surrounding colors.",
                        bundle: .main
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Preview of Liquid Glass effect
                    HStack(spacing: 16) {
                        ForEach([DieModel.die20(color: .G), .die12(color: .G), .die10(color: .G)], id: \.id) { die in
                            VStack(spacing: 4) {
                                die.diceImage(for: die.die.max)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .accessibilityHidden(true)
                                Text(verbatim: "D\(die.die.max)")
                                    .font(.caption2)
                            }
                            .frame(width: 60, height: 60)
#if !os(visionOS)
                            .glassEffect(.regular.interactive())
#endif
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.blue.opacity(0.3))
                    .clipShape(.rect(cornerRadius: 12))
                }
            } header: {
                Text("About", bundle: .main)
            }
        }
        .navigationTitle(Text("Dice Widget", bundle: .main))
        .onAppear {
            guard loadsStoredConfiguration else { return }
            loadConfiguration()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadConfiguration() {
        configuration = DiceConfiguration.loadFromUserDefaults()
        
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        isGameActive = defaults?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false
        currentGameName = defaults?.string(forKey: UserDefaults.DiceKeys.currentGameName) ?? ""
    }
    
    private func updateGameStatus(isActive: Bool) {
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        defaults?.set(isActive, forKey: UserDefaults.DiceKeys.isGameActive)
        
        if !isActive {
            // Clear all favorites when game ends
            // Game dice IDs are only valid during the session
            configuration.favoriteDice.removeAll()
            configuration.save()
            
            // End Live Activity
            Task {
                await DiceRollerLiveActivityManager.shared.endActivity()
            }
        }
        
        // Reload widget to reflect changes
        DiceWidgetReloader.reloadDiceWidgets()
    }
    
    private func saveGameName(_ name: String) {
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        defaults?.set(name, forKey: UserDefaults.DiceKeys.currentGameName)
    }
    
    private func clearHistory() {
        configuration.lastRoll = nil
        configuration.save()
        DiceWidgetReloader.reloadDiceWidgets()
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
}

#Preview("Widget configuration") {
    let roll = DiceResultModel(
        diceModel: DiceModel.previewSnapshot,
        result: .coup,
        values: "1",
        sum: 1,
        checked: false,
        timeStamp: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
    let configuration = DiceConfiguration(
        selectedDice: DiceModel.previewSnapshot,
        lastRoll: roll,
        availableDice: [.die6(color: .G), .die8(color: .G), .die20(color: .G)],
        showHistory: true
    )

    NavigationStack {
        DiceRollerWidgetConfiguration(
            configuration: configuration,
            isGameActive: true,
            currentGameName: "The Verdant Vault",
            loadsStoredConfiguration: false
        )
    }
}

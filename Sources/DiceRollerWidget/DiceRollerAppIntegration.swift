// @copyright André Trettin

import SwiftUI
import CoreRPG
import WidgetKit

/// Integration view for managing dice roller widget from the main app
struct DiceRollerWidgetConfiguration: View {
    @State private var selectedDice: DiceType = .d20
    @State private var configuration: DiceConfiguration = .default
    @State private var isGameActive: Bool = false
    @State private var currentGameName: String = ""
    
    var body: some View {
        Form {
            Section {
                Picker("Default Dice", selection: $selectedDice) {
                    ForEach(DiceType.allCases) { diceType in
                        HStack {
                            diceType.dieImage

                            Text(diceType.rawValue)
                        }
                        .tag(diceType)
                    }
                }
                .onChange(of: selectedDice) { _, newValue in
                    updateConfiguration(selectedDice: newValue)
                }
            } header: {
                Text("Widget Settings")
            } footer: {
                Text("Choose which dice type appears in the widget by default")
            }
            
            Section {
                Toggle("Enable Live Activity", isOn: $isGameActive)
                    .onChange(of: isGameActive) { _, newValue in
                        updateGameStatus(isActive: newValue)
                    }
                
                if isGameActive {
                    TextField("Game Name", text: $currentGameName)
                        .onChange(of: currentGameName) { _, newValue in
                            saveGameName(newValue)
                        }
                }
            } header: {
                Text("Live Activity")
            } footer: {
                Text("Show dice rolls in Dynamic Island and Lock Screen during gameplay")
            }
            
            Section {
                if let lastRoll = configuration.lastRoll {
                    HStack {
                        lastRoll.diceType.dieImage
                            .font(.title2)
                            .foregroundStyle(resultColor(for: lastRoll))
                        
                        VStack(alignment: .leading) {
                            Text("\(lastRoll.value)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(resultColor(for: lastRoll))
                            
                            Text(lastRoll.diceType.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(lastRoll.timestamp, style: .date)
                                .font(.caption2)
                            Text(lastRoll.timestamp, style: .time)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Button("Clear History", role: .destructive) {
                        clearHistory()
                    }
                } else {
                    Text("No rolls yet")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Last Roll")
            }
            
            Section {
                Button("Add Widget to Home Screen") {
                    // This opens Settings where user can add widget
                    if let url = URL(string: "App-prefs:root=") {
                        //UIApplication.openSettingsURLString
                        //UIApplication.shared.open(url)
                    }
                }
                
                Button("Reload All Widgets") {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } header: {
                Text("Widget Management")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liquid Glass Design")
                        .font(.headline)
                    
                    Text("The dice roller widget uses Apple's new Liquid Glass design, which creates a beautiful glass-like effect that blurs content behind it and reflects surrounding colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Preview of Liquid Glass effect
                    HStack(spacing: 16) {
                        ForEach([DiceType.d20, .d12, .d10], id: \.self) { diceType in
                            VStack(spacing: 4) {
                                diceType.dieImage
                                    .frame(width: 32, height: 32)
                                Text(diceType.rawValue)
                                    .font(.caption2)
                            }
                            .frame(width: 60, height: 60)
                            .glassEffect(.regular.interactive())
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.blue.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Dice Widget")
        .onAppear {
            loadConfiguration()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadConfiguration() {
        configuration = DiceConfiguration.loadFromUserDefaults()
        selectedDice = configuration.selectedDice
        
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        isGameActive = defaults?.bool(forKey: "isGameActive") ?? false
        currentGameName = defaults?.string(forKey: "currentGameName") ?? ""
    }
    
    private func updateConfiguration(selectedDice: DiceType) {
        configuration.selectedDice = selectedDice
        configuration.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func updateGameStatus(isActive: Bool) {
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        defaults?.set(isActive, forKey: "isGameActive")
        
        if !isActive {
            // End Live Activity
            Task {
                await DiceRollerLiveActivityManager.shared.endActivity()
            }
        }
    }
    
    private func saveGameName(_ name: String) {
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        defaults?.set(name, forKey: "currentGameName")
    }
    
    private func clearHistory() {
        configuration.lastRoll = nil
        configuration.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func resultColor(for result: DiceRollResult) -> Color {
        if result.isCritical {
            return .green
        } else if result.isCriticalFailure {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - In-App Dice Roller with Widget Integration

struct DiceRollerView: View {
    @State private var selectedDice: DiceType = .d20
    @State private var currentRoll: DiceRollResult?
    @State private var isRolling: Bool = false
    @State private var rollHistory: [DiceRollResult] = []
    
    @Namespace private var glassNamespace
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Main dice display with Liquid Glass
                GlassEffectContainer(spacing: 40) {
                    VStack(spacing: 16) {
                        if let roll = currentRoll {
                            resultDisplay(roll)
                                .glassEffectID("result", in: glassNamespace)
                        } else {
                            diceSelection
                                .glassEffectID("selection", in: glassNamespace)
                        }
                        
                        // Roll button with Liquid Glass
                        Button(action: rollDice) {
                            HStack {
                                Image(systemName: "dice")
                                Text("Roll \(selectedDice.rawValue)")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isRolling)
                    }
                    .padding()
                }
                
                // Dice type selector with Liquid Glass
                diceTypeSelector
                
                // Roll history
                if !rollHistory.isEmpty {
                    rollHistoryView
                }
            }
            .padding()
        }
        .navigationTitle("Dice Roller")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    DiceRollerWidgetConfiguration()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .onAppear {
            loadHistory()
        }
    }
    
    // MARK: - Views
    
    private var diceSelection: some View {
        VStack(spacing: 12) {
            selectedDice.dieImage
                .frame(width: 80, height: 80)
                .foregroundStyle(.primary)
            
            Text(selectedDice.rawValue)
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Tap to roll")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassEffect(.regular.interactive())
    }
    
    private func resultDisplay(_ result: DiceRollResult) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(resultColor(for: result).opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Text("\(result.value)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(resultColor(for: result))
            }
            .glassEffect(.regular.tint(resultColor(for: result)).interactive())
            
            Text(result.diceType.rawValue)
                .font(.title2)
                .fontWeight(.semibold)
            
            if result.isCritical {
                Text("Critical Success!")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if result.isCriticalFailure {
                Text("Critical Failure!")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
        }
        .rotation3DEffect(
            .degrees(isRolling ? 720 : 0),
            axis: (x: 1, y: 1, z: 0)
        )
    }
    
    private var diceTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Dice")
                .font(.headline)
                .padding(.horizontal)
            
            GlassEffectContainer(spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                    ForEach(DiceType.allCases) { diceType in
                        Button {
                            withAnimation(.spring()) {
                                selectedDice = diceType
                                currentRoll = nil
                            }
                        } label: {
                            VStack(spacing: 8) {
                                diceType.dieImage
                                    .frame(width: 40, height: 40)
                                    .font(.title)
                                Text(diceType.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.glass)
                        .overlay {
                            if selectedDice == diceType {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.blue, lineWidth: 3)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private var rollHistoryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear", role: .destructive) {
                    withAnimation {
                        rollHistory.removeAll()
                        saveHistory()
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rollHistory.reversed()) { roll in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(resultColor(for: roll).opacity(0.2))
                                    .frame(width: 50, height: 50)
                                
                                Text("\(roll.value)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(resultColor(for: roll))
                            }
                            
                            Text(roll.diceType.rawValue)
                                .font(.caption2)
                        }
                        .glassEffect(.regular)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Actions
    
    private func rollDice() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            isRolling = true
            
            // Simulate rolling animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let value = selectedDice.roll()
                let result = DiceRollResult(
                    value: value,
                    diceType: selectedDice,
                    timestamp: Date()
                )
                
                withAnimation {
                    currentRoll = result
                    rollHistory.append(result)
                    isRolling = false
                }
                
                // Update widget
                var config = DiceConfiguration.loadFromUserDefaults()
                config.lastRoll = result
                config.selectedDice = selectedDice
                config.save()
                WidgetCenter.shared.reloadAllTimelines()
                
                // Update Live Activity if game is active
                Task {
                    let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
                    let isGameActive = defaults?.bool(forKey: "isGameActive") ?? false
                    
                    if isGameActive {
                        await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
                    }
                }
                
                // Save history
                saveHistory()
            }
        }
    }
    
    private func loadHistory() {
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        if let data = defaults?.data(forKey: "rollHistory"),
           let history = try? JSONDecoder().decode([DiceRollResult].self, from: data) {
            rollHistory = history
        }
    }
    
    private func saveHistory() {
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        if let data = try? JSONEncoder().encode(rollHistory) {
            defaults?.set(data, forKey: "rollHistory")
        }
    }
    
    private func resultColor(for result: DiceRollResult) -> Color {
        if result.isCritical {
            return .green
        } else if result.isCriticalFailure {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - Previews

#Preview("Configuration") {
    NavigationStack {
        DiceRollerWidgetConfiguration()
    }
}

#Preview("Dice Roller") {
    NavigationStack {
        DiceRollerView()
    }
}

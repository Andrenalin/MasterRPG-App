// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// Integration view for managing dice roller widget from the main app
struct DiceRollerWidgetConfiguration: View {
    @State private var configuration: DiceConfiguration = .default
    @State private var isGameActive: Bool = false
    @State private var currentGameName: String = ""
    
    var body: some View {
        Form {
            Section {
                Text("Current: \(configuration.selectedDice.name)")
                    .font(.headline)
            } header: {
                Text("Widget Settings")
            } footer: {
                Text("The widget displays your last rolled dice configuration")
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
                    
                    NavigationLink {
                        FavoriteDiceManagementView(configuration: $configuration)
                    } label: {
                        HStack {
                            Text("Favorite Dice")
                            Spacer()
                            Text("\(configuration.favoriteDice.count)/6")
                                .foregroundStyle(.secondary)
                        }
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
                        if let firstDie = lastRoll.diceModel.dice.first {
                            firstDie.diceImage(for: lastRoll.sum)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(resultColor(for: lastRoll.result))
                        }
                        
                        VStack(alignment: .leading) {
                            Text("\(lastRoll.sum)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(resultColor(for: lastRoll.result))
                            
                            Text(lastRoll.diceModel.name)
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
                    if let _ = URL(string: "App-prefs:root=") {
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
                        ForEach([DieModel.die20(color: .G), .die12(color: .G), .die10(color: .G)], id: \.id) { die in
                            VStack(spacing: 4) {
                                die.diceImage(for: die.die.max)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                Text("D\(die.die.max)")
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
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func saveGameName(_ name: String) {
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        defaults?.set(name, forKey: UserDefaults.DiceKeys.currentGameName)
    }
    
    private func clearHistory() {
        configuration.lastRoll = nil
        configuration.save()
        WidgetCenter.shared.reloadAllTimelines()
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

// MARK: - In-App Dice Roller with Widget Integration

struct DiceRollerView: View {
    @State private var selectedDie: DieModel = .die20(color: .G)
    @State private var currentRoll: DiceResultModel?
    @State private var isRolling: Bool = false
    @State private var rollHistory: [DiceResultModel] = []
    
    @Namespace private var glassNamespace
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
#if os(visionOS)
                contentView
#else
                // Main dice display with Liquid Glass
                GlassEffectContainer(spacing: 40) {
                    contentView
                }
#endif
                
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
            ToolbarItem(placement: .automatic) {
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
    
    var contentView: some View {
        VStack(spacing: 16) {
            if let roll = currentRoll {
                resultDisplay(roll)
#if !os(visionOS)
                    .glassEffectID("result", in: glassNamespace)
#endif
            } else {
                diceSelection
#if !os(visionOS)
                    .glassEffectID("selection", in: glassNamespace)
#endif
            }
            
            // Roll button with Liquid Glass
            Button(action: rollDice) {
                HStack {
                    Image(systemName: "dice")
                    Text("Roll D\(selectedDie.die.max)")
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
    
    // MARK: - Views
    
    private var diceSelection: some View {
        VStack(spacing: 12) {
            selectedDie.diceImage(for: selectedDie.die.max)
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.primary)
            
            Text("D\(selectedDie.die.max)")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Tap to roll")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
#if !os(visionOS)
        .glassEffect(.regular.interactive())
#endif
    }
    
    private func resultDisplay(_ result: DiceResultModel) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(resultColor(for: result.result).opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Text("\(result.sum)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(resultColor(for: result.result))
            }
#if !os(visionOS)
            .glassEffect(.regular.tint(resultColor(for: result.result)).interactive())
#endif
            Text(result.diceModel.name)
                .font(.title2)
                .fontWeight(.semibold)
            
            if result.result == .coup {
                Text("Critical Success!")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if result.result == .fumble {
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
            
#if os(visionOS)
            gridView
#else
            GlassEffectContainer(spacing: 16) {
                gridView
            }
#endif
        }
    }
    
    var gridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach([DieModel.die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)]) { die in
                Button {
                    withAnimation(.spring()) {
                        selectedDie = die
                        currentRoll = nil
                    }
                } label: {
                    VStack(spacing: 8) {
                        die.diceImage(for: die.die.max)
                            .resizable()
                            .frame(width: 40, height: 40)
                        Text("D\(die.die.max)")
                            .font(.caption)
                            .fontWeight(.medium)
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
            }
        }
        .padding()
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
                                    .fill(resultColor(for: roll.result).opacity(0.2))
                                    .frame(width: 50, height: 50)
                                
                                Text("\(roll.sum)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(resultColor(for: roll.result))
                            }
                            
                            Text(roll.diceModel.name)
                                .font(.caption2)
                        }
#if !os(visionOS)
                        .glassEffect(.regular)
#endif
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
                let rolledDie = selectedDie.role(resetResults: true, reroleOptions: [])
                let value = rolledDie.result.first ?? selectedDie.die.max
                
                // Create dice model with the rolled die
                let diceModel = DiceModel(id: UUID(), name: "D\(selectedDie.die.max)", dice: [rolledDie])
                
                let result = DiceResultModel(
                    diceModel: diceModel,
                    result: .rolled,
                    values: "\(value)",
                    sum: value,
                    checked: false,
                    timeStamp: Date()
                )
                
                withAnimation {
                    currentRoll = result
                    rollHistory.append(result)
                    isRolling = false
                }
                
                // Update widget
                var config = DiceConfiguration.loadFromUserDefaults()
                config.lastRoll = result
                config.selectedDice = diceModel
                config.save()
                WidgetCenter.shared.reloadAllTimelines()
                
                // Update Live Activity if game is active
                Task {
                    let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
                    let isGameActive = defaults?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false
                    
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
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        if let data = defaults?.data(forKey: UserDefaults.DiceKeys.rollHistory),
           let history = try? JSONDecoder().decode([DiceResultModel].self, from: data) {
            rollHistory = history
        }
    }
    
    private func saveHistory() {
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        if let data = try? JSONEncoder().encode(rollHistory) {
            defaults?.set(data, forKey: UserDefaults.DiceKeys.rollHistory)
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
}
// MARK: - Favorite Dice Management

struct FavoriteDiceManagementView: View {
    @Binding var configuration: DiceConfiguration
    @State private var showingAddFavorite = false
    @State private var newFavoriteName = ""
    @State private var selectedDiceModel: DiceModel?
    @Environment(\.dismiss) private var dismiss
    
    // Sample dice models for selection - in real app, get from character/game
    private let availableDiceModels: [DiceModel] = [
        DiceModel(id: UUID(), name: "Attack Roll", dice: [.die20(color: .G)]),
        DiceModel(id: UUID(), name: "Damage", dice: [.die8(color: .G), .die6(color: .G)]),
        DiceModel(id: UUID(), name: "Skill Check", dice: [.die20(color: .G)]),
        DiceModel(id: UUID(), name: "Sneak Attack", dice: [.die6(color: .G), .die6(color: .G), .die6(color: .G)])
    ]
    
    var body: some View {
        List {
            Section {
                ForEach(configuration.favoriteDice) { favorite in
                    HStack {
                        if let firstDie = favorite.diceModel.dice.first {
                            firstDie.diceImage(for: firstDie.die.max)
                                .resizable()
                                .frame(width: 32, height: 32)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(favorite.name)
                                .font(.headline)
                            
                            Text(favorite.diceModel.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(diceDescription(favorite.diceModel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteFavorites)
                .onMove(perform: moveFavorites)
            } header: {
                HStack {
                    Text("Favorite Dice")
                    Spacer()
                    Text("\(configuration.favoriteDice.count)/6")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("These dice will appear in the widget during active gameplay. Tap Edit to reorder.")
            }
            
            if configuration.favoriteDice.count < 6 {
                Section {
                    Button {
                        showingAddFavorite = true
                    } label: {
                        Label("Add Favorite Dice", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("Select dice from your character sheet or create custom dice configurations.")
                }
            }
            
            Section {
                ForEach(availableDiceModels) { diceModel in
                    Button {
                        addFavorite(diceModel: diceModel)
                    } label: {
                        HStack {
                            if let firstDie = diceModel.dice.first {
                                firstDie.diceImage(for: firstDie.die.max)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(diceModel.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text(diceDescription(diceModel))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if configuration.favoriteDice.contains(where: { $0.diceModel.id == diceModel.id }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if configuration.favoriteDice.count >= 6 {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(configuration.favoriteDice.count >= 6 || 
                             configuration.favoriteDice.contains(where: { $0.diceModel.id == diceModel.id }))
                }
            } header: {
                Text("Available Dice")
            } footer: {
                Text("Dice configurations from your character and game settings.")
            }
        }
        .navigationTitle("Favorite Dice")
    #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
#endif
        .sheet(isPresented: $showingAddFavorite) {
            addFavoriteSheet
        }
    }
    
    private var addFavoriteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Favorite Name", text: $newFavoriteName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Give this dice configuration a memorable name")
                }
                
                // In a real implementation, this would show character's available dice
                Section {
                    Text("Select from character dice configurations")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Dice Configuration")
                }
            }
            .navigationTitle("Add Favorite")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddFavorite = false
                        newFavoriteName = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // Add the favorite
                        showingAddFavorite = false
                        newFavoriteName = ""
                    }
                    .disabled(newFavoriteName.isEmpty)
                }
            }
        }
    }
    
    private func addFavorite(diceModel: DiceModel) {
        guard configuration.favoriteDice.count < 6 else { return }
        guard !configuration.favoriteDice.contains(where: { $0.diceModel.id == diceModel.id }) else { return }
        
        let favorite = FavoriteDiceItem(
            name: diceModel.name,
            diceModel: diceModel
        )
        
        configuration.favoriteDice.append(favorite)
        configuration.save()
        
        // Reload widget
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func deleteFavorites(at offsets: IndexSet) {
        configuration.favoriteDice.remove(atOffsets: offsets)
        configuration.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        configuration.favoriteDice.move(fromOffsets: source, toOffset: destination)
        configuration.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func diceDescription(_ diceModel: DiceModel) -> String {
        let diceNames = diceModel.dice.map { "D\($0.die.max)" }.joined(separator: " + ")
        return diceNames
    }
}



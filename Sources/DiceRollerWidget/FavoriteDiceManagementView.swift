// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct FavoriteDiceManagementView: View {
    @Binding var configuration: DiceConfiguration
    @State private var showingAddFavorite = false
    @State private var newFavoriteName = ""
    @State private var selectedDiceModel: DiceSnapshot?
    @Environment(\.dismiss) private var dismiss
    
    // Sample dice models for selection - in real app, get from character/game
    private let availableDiceModels: [DiceSnapshot] = [
        DiceSnapshot(id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)), name: String(localized: "Attack Roll", bundle: .main), dice: [.die20(color: .G)]),
        DiceSnapshot(id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)), name: String(localized: "Damage", bundle: .main), dice: [.die8(color: .G), .die6(color: .G)]),
        DiceSnapshot(id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)), name: String(localized: "Skill Check", bundle: .main), dice: [.die20(color: .G)]),
        DiceSnapshot(id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)), name: String(localized: "Sneak Attack", bundle: .main), dice: [.die6(color: .G), .die6(color: .G), .die6(color: .G)])
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
                                .accessibilityHidden(true)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: favorite.name)
                                .font(.headline)
                            
                            Text(verbatim: favorite.diceModel.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(verbatim: diceDescription(favorite.diceModel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteFavorites)
                .onMove(perform: moveFavorites)
            } header: {
                HStack {
                    Text("Favorite Dice", bundle: .main)
                    Spacer()
                    Text(verbatim: "\(configuration.favoriteDice.count)/6")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("These dice will appear in the widget during active gameplay. Tap Edit to reorder.", bundle: .main)
            }
            
            if configuration.favoriteDice.count < 6 {
                Section {
                    Button {
                        showingAddFavorite = true
                    } label: {
                        Label {
                            Text("Add Favorite Dice", bundle: .main)
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                } footer: {
                    Text("Select dice from your character sheet or create custom dice configurations.", bundle: .main)
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
                                    .accessibilityHidden(true)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: diceModel.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text(verbatim: diceDescription(diceModel))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if configuration.favoriteDice.contains(where: { $0.diceModel.id == diceModel.id }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            } else if configuration.favoriteDice.count >= 6 {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(configuration.favoriteDice.count >= 6 || 
                             configuration.favoriteDice.contains(where: { $0.diceModel.id == diceModel.id }))
                }
            } header: {
                Text("Available Dice", bundle: .main)
            } footer: {
                Text("Dice configurations from your character and game settings.", bundle: .main)
            }
        }
        .navigationTitle(Text("Favorite Dice", bundle: .main))
#if os(iOS)
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
                    TextField(text: $newFavoriteName) {
                        Text("Favorite Name", bundle: .main)
                    }
                } header: {
                    Text("Name", bundle: .main)
                } footer: {
                    Text("Give this dice configuration a memorable name", bundle: .main)
                }
                
                // In a real implementation, this would show character's available dice
                Section {
                    Text("Select from character dice configurations", bundle: .main)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Dice Configuration", bundle: .main)
                }
            }
            .navigationTitle(Text("Add Favorite", bundle: .main))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingAddFavorite = false
                        newFavoriteName = ""
                    } label: {
                        Text("Cancel", bundle: .main)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // Add the favorite
                        showingAddFavorite = false
                        newFavoriteName = ""
                    } label: {
                        Text("Add", bundle: .main)
                    }
                    .disabled(newFavoriteName.isEmpty)
                }
            }
        }
    }
    
    private func addFavorite(diceModel: DiceSnapshot) {
        guard configuration.favoriteDice.count < 6 else { return }
        guard !configuration.favoriteDice.contains(where: { $0.diceModel.id == diceModel.id }) else { return }
        
        let favorite = FavoriteDiceItem(
            name: diceModel.name,
            diceModel: diceModel
        )
        
        configuration.favoriteDice.append(favorite)
        configuration.save()
        
        // Reload widget
        DiceWidgetReloader.reloadDiceWidgets()
    }
    
    private func deleteFavorites(at offsets: IndexSet) {
        configuration.favoriteDice.remove(atOffsets: offsets)
        configuration.save()
        DiceWidgetReloader.reloadDiceWidgets()
    }
    
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        configuration.favoriteDice.move(fromOffsets: source, toOffset: destination)
        configuration.save()
        DiceWidgetReloader.reloadDiceWidgets()
    }
    
    private func diceDescription(_ diceModel: DiceSnapshot) -> String {
        let diceNames = diceModel.dice.map { "D\($0.die.max)" }.joined(separator: " + ")
        return diceNames
    }
}

#Preview("Favorite dice") {
    @Previewable @State var configuration = DiceConfiguration(
        selectedDice: DiceModel.previewSnapshot,
        availableDice: [.die6(color: .G), .die8(color: .G), .die20(color: .G)],
        showHistory: true,
        favoriteDice: [
            FavoriteDiceItem(
                id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                name: "Dungeon Master",
                diceModel: DiceModel.previewSnapshot
            )
        ]
    )

    NavigationStack {
        FavoriteDiceManagementView(configuration: $configuration)
    }
}

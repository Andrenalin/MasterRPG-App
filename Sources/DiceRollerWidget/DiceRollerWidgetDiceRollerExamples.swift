//// @copyright André Trettin
//
//import SwiftUI
//
///// Example configuration and usage patterns for the Dice Roller Widget
//
//// MARK: - Example 1: Basic Integration in Main App
//
//struct GameView: View {
//    @State private var gameController: GameController
//    
//    var body: some View {
//        VStack {
//            // Your existing game UI
//            
//            Button("Roll D20") {
//                Task {
//                    await rollDiceAndUpdateWidget(.d20)
//                }
//            }
//        }
//    }
//    
//    private func rollDiceAndUpdateWidget(_ diceType: DiceType) async {
//        // Perform the roll
//        let value = diceType.roll()
//        
//        // Create result
//        let result = DiceRollResult(
//            value: value,
//            diceType: diceType,
//            timestamp: Date()
//        )
//        
//        // Update widget
//        var config = DiceConfiguration.loadFromUserDefaults()
//        config.lastRoll = result
//        config.selectedDice = diceType
//        config.save()
//        
//        // Reload widgets
//        WidgetCenter.shared.reloadAllTimelines()
//        
//        // Update Live Activity if game is active
//        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
//        if defaults?.bool(forKey: "isGameActive") == true {
//            await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
//        }
//    }
//}
//
//// MARK: - Example 2: Starting a Game Session with Live Activity
//
//struct GameSessionManager {
//    
//    static func startGameSession(name: String) async {
//        // Mark game as active
//        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
//        defaults?.set(true, forKey: "isGameActive")
//        defaults?.set(name, forKey: "currentGameName")
//        
//        // Note: Live Activity will start automatically on first dice roll
//        print("Game session '\(name)' started. Live Activity will activate on first roll.")
//    }
//    
//    static func endGameSession() async {
//        // Mark game as inactive
//        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
//        defaults?.set(false, forKey: "isGameActive")
//        
//        // End Live Activity
//        await DiceRollerLiveActivityManager.shared.endActivityWithDelay(seconds: 10)
//        
//        print("Game session ended. Live Activity will dismiss in 10 seconds.")
//    }
//}
//
//// MARK: - Example 3: Custom Dice Configuration View
//
//struct CustomDiceConfigurationView: View {
//    @State private var availableDice: [DiceType] = DiceType.allCases
//    @State private var selectedDice: Set<DiceType> = Set(DiceType.allCases)
//    
//    var body: some View {
//        Form {
//            Section("Available Dice") {
//                ForEach(DiceType.allCases) { diceType in
//                    Toggle(isOn: binding(for: diceType)) {
//                        HStack {
//                            Image(systemName: diceType.systemImage)
//                            Text(diceType.rawValue)
//                        }
//                    }
//                }
//            }
//            
//            Section {
//                Button("Save Configuration") {
//                    saveConfiguration()
//                }
//            }
//        }
//        .navigationTitle("Configure Dice")
//    }
//    
//    private func binding(for diceType: DiceType) -> Binding<Bool> {
//        Binding(
//            get: { selectedDice.contains(diceType) },
//            set: { isSelected in
//                if isSelected {
//                    selectedDice.insert(diceType)
//                } else {
//                    selectedDice.remove(diceType)
//                }
//            }
//        )
//    }
//    
//    private func saveConfiguration() {
//        var config = DiceConfiguration.loadFromUserDefaults()
//        config.availableDice = Array(selectedDice)
//        config.save()
//        
//        WidgetCenter.shared.reloadAllTimelines()
//    }
//}
//
//// MARK: - Example 4: Integrating with Existing DiceModel
//
//extension DiceModel {
//    
//    /// Converts a DiceModel to the widget's DiceType
//    var widgetDiceType: DiceType? {
//        switch die.sides {
//        case .four: return .d4
//        case .six: return .d6
//        case .eight: return .d8
//        case .ten: return .d10
//        case .twelve: return .d12
//        case .twenty: return .d20
//        case .number(let n):
//            if n == 100 { return .d100 }
//            return nil
//        }
//    }
//    
//    /// Updates widget with the roll result from this DiceModel
//    func updateWidget() {
//        guard let widgetType = widgetDiceType,
//              let lastResult = result.last else { return }
//        
//        let widgetResult = DiceRollResult(
//            value: lastResult,
//            diceType: widgetType,
//            timestamp: Date()
//        )
//        
//        var config = DiceConfiguration.loadFromUserDefaults()
//        config.lastRoll = widgetResult
//        config.save()
//        
//        WidgetCenter.shared.reloadAllTimelines()
//    }
//}
//
//// MARK: - Example 5: Game Controller Integration
//
//extension GameController {
//    
//    /// Rolls a die and updates the widget
//    func rollDieWithWidgetUpdate(die: DieModel, for itemId: UUID) async {
//        // Existing roll logic
//        role(die: die, for: itemId)
//        let result = await createDiceResult(
//            for: itemId,
//            resultCategory: ResultCategory(id: itemId, module: .dice)
//        )
//        
//        // Update widget
//        die.updateWidget()
//        
//        // Update Live Activity if game is active
//        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
//        if defaults?.bool(forKey: "isGameActive") == true {
//            if let widgetType = die.widgetDiceType,
//               let lastResult = die.result.last {
//                let widgetResult = DiceRollResult(
//                    value: lastResult,
//                    diceType: widgetType,
//                    timestamp: Date()
//                )
//                await DiceRollerLiveActivityManager.shared.startOrUpdate(with: widgetResult)
//            }
//        }
//    }
//}
//
//// MARK: - Example 6: Settings View with Liquid Glass Preview
//
//struct DiceWidgetSettingsView: View {
//    @State private var enableLiveActivity = false
//    @State private var showCriticals = true
//    @State private var vibrationFeedback = true
//    
//    @Namespace private var glassNamespace
//    
//    var body: some View {
//        Form {
//            Section {
//                Toggle("Live Activity", isOn: $enableLiveActivity)
//                Toggle("Show Critical Results", isOn: $showCriticals)
//                Toggle("Vibration Feedback", isOn: $vibrationFeedback)
//            } header: {
//                Text("Widget Settings")
//            }
//            
//            Section {
//                // Live preview of Liquid Glass effect
//                VStack(spacing: 16) {
//                    Text("Widget Preview")
//                        .font(.headline)
//                    
//                    GlassEffectContainer(spacing: 20) {
//                        HStack(spacing: 20) {
//                            // Preview dice
//                            ForEach([DiceType.d20, .d12, .d10], id: \.self) { diceType in
//                                VStack(spacing: 8) {
//                                    Image(systemName: diceType.systemImage)
//                                        .font(.title)
//                                    Text(diceType.rawValue)
//                                        .font(.caption)
//                                }
//                                .frame(width: 80, height: 80)
//                                .glassEffect(.regular.interactive())
//                                .glassEffectID(diceType.rawValue, in: glassNamespace)
//                            }
//                        }
//                    }
//                    .padding()
//                    .background {
//                        // Colorful background to show glass effect
//                        LinearGradient(
//                            colors: [.blue, .purple, .pink],
//                            startPoint: .topLeading,
//                            endPoint: .bottomTrailing
//                        )
//                        .opacity(0.3)
//                    }
//                    .clipShape(RoundedRectangle(cornerRadius: 16))
//                }
//                .listRowInsets(EdgeInsets())
//                .listRowBackground(Color.clear)
//            } header: {
//                Text("Liquid Glass Preview")
//            } footer: {
//                Text("This preview shows how your widget will look with the new Liquid Glass design. The glass effect adapts to your Home Screen appearance.")
//            }
//        }
//        .navigationTitle("Widget Settings")
//    }
//}
//
//// MARK: - Example 7: Deep Link Handling
//
//struct AppCoordinator {
//    
//    /// Handles deep links from widgets
//    static func handleWidgetDeepLink(_ url: URL) -> Bool {
//        guard url.scheme == "masterrpg" else { return false }
//        
//        switch url.host {
//        case "dice":
//            // Navigate to dice roller
//            navigateToDiceRoller()
//            return true
//            
//        case "roll":
//            // Perform a quick roll
//            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
//               let diceTypeString = components.queryItems?.first(where: { $0.name == "type" })?.value,
//               let diceType = DiceType(rawValue: diceTypeString.uppercased()) {
//                Task {
//                    await performQuickRoll(diceType)
//                }
//            }
//            return true
//            
//        case "config":
//            // Navigate to widget configuration
//            navigateToWidgetConfig()
//            return true
//            
//        default:
//            return false
//        }
//    }
//    
//    private static func navigateToDiceRoller() {
//        // Implement navigation to dice roller view
//        print("Navigating to dice roller")
//    }
//    
//    private static func performQuickRoll(_ diceType: DiceType) async {
//        let value = diceType.roll()
//        let result = DiceRollResult(value: value, diceType: diceType, timestamp: Date())
//        
//        var config = DiceConfiguration.loadFromUserDefaults()
//        config.lastRoll = result
//        config.save()
//        
//        WidgetCenter.shared.reloadAllTimelines()
//    }
//    
//    private static func navigateToWidgetConfig() {
//        // Implement navigation to widget configuration
//        print("Navigating to widget configuration")
//    }
//}
//
//// MARK: - Example 8: Widget Timeline Optimization
//
//struct OptimizedDiceRollerProvider: TimelineProvider {
//    
//    func placeholder(in context: Context) -> DiceRollerEntry {
//        DiceRollerEntry(
//            date: Date(),
//            selectedDice: .d20,
//            lastRoll: nil,
//            configuration: .default
//        )
//    }
//    
//    func getSnapshot(in context: Context, completion: @escaping (DiceRollerEntry) -> Void) {
//        let entry = createEntry()
//        completion(entry)
//    }
//    
//    func getTimeline(in context: Context, completion: @escaping (Timeline<DiceRollerEntry>) -> Void) {
//        let entry = createEntry()
//        
//        // Determine when to refresh based on context
//        let refreshDate: Date
//        if let lastRoll = entry.lastRoll {
//            // If there's a recent roll, refresh sooner (5 minutes)
//            let timeSinceRoll = Date().timeIntervalSince(lastRoll.timestamp)
//            if timeSinceRoll < 300 { // 5 minutes
//                refreshDate = Date().addingTimeInterval(300)
//            } else {
//                // Otherwise refresh every 15 minutes
//                refreshDate = Date().addingTimeInterval(900)
//            }
//        } else {
//            // No roll, refresh every hour
//            refreshDate = Date().addingTimeInterval(3600)
//        }
//        
//        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
//        completion(timeline)
//    }
//    
//    private func createEntry() -> DiceRollerEntry {
//        let configuration = DiceConfiguration.loadFromUserDefaults()
//        return DiceRollerEntry(
//            date: Date(),
//            selectedDice: configuration.selectedDice,
//            lastRoll: configuration.lastRoll,
//            configuration: configuration
//        )
//    }
//}
//
//// MARK: - Example 9: Analytics Integration
//
//struct DiceRollerAnalytics {
//    
//    static func trackWidgetRoll(_ result: DiceRollResult) {
//        // Log widget interaction
//        print("Widget Roll: \(result.diceType.rawValue) = \(result.value)")
//        
//        // Track critical success/failure
//        if result.isCritical {
//            print("Critical Success!")
//        } else if result.isCriticalFailure {
//            print("Critical Failure!")
//        }
//        
//        // You can integrate with your analytics provider here
//        // Analytics.track("widget_dice_roll", properties: [
//        //     "dice_type": result.diceType.rawValue,
//        //     "value": result.value,
//        //     "is_critical": result.isCritical,
//        //     "is_failure": result.isCriticalFailure
//        // ])
//    }
//    
//    static func trackLiveActivityStart(gameName: String) {
//        print("Live Activity Started: \(gameName)")
//        // Analytics.track("live_activity_started", properties: ["game_name": gameName])
//    }
//    
//    static func trackLiveActivityEnd() {
//        print("Live Activity Ended")
//        // Analytics.track("live_activity_ended")
//    }
//}
//
//// MARK: - Example 10: Testing Utilities
//
//#if DEBUG
//struct DiceWidgetTestingUtilities {
//    
//    /// Simulates multiple dice rolls for testing
//    static func simulateRolls(count: Int = 10) {
//        for i in 0..<count {
//            let diceType = DiceType.allCases.randomElement()!
//            let value = diceType.roll()
//            let result = DiceRollResult(value: value, diceType: diceType, timestamp: Date())
//            
//            var config = DiceConfiguration.loadFromUserDefaults()
//            config.lastRoll = result
//            config.save()
//            
//            print("Roll \(i + 1): \(diceType.rawValue) = \(value)")
//            
//            // Add delay to simulate real usage
//            Thread.sleep(forTimeInterval: 0.5)
//        }
//        
//        WidgetCenter.shared.reloadAllTimelines()
//    }
//    
//    /// Clears all widget data
//    static func clearAllData() {
//        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
//        defaults?.removeObject(forKey: "diceConfiguration")
//        defaults?.removeObject(forKey: "rollHistory")
//        defaults?.removeObject(forKey: "isGameActive")
//        defaults?.removeObject(forKey: "currentGameName")
//        
//        WidgetCenter.shared.reloadAllTimelines()
//        print("All widget data cleared")
//    }
//    
//    /// Tests Live Activity lifecycle
//    static func testLiveActivity() async {
//        print("Testing Live Activity...")
//        
//        // Start game
//        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
//        defaults?.set(true, forKey: "isGameActive")
//        defaults?.set("Test Game", forKey: "currentGameName")
//        
//        // Simulate rolls
//        for i in 1...5 {
//            let result = DiceRollResult(
//                value: Int.random(in: 1...20),
//                diceType: .d20,
//                timestamp: Date()
//            )
//            
//            await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
//            print("Roll \(i): \(result.value)")
//            
//            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
//        }
//        
//        // End activity
//        await DiceRollerLiveActivityManager.shared.endActivityWithDelay(seconds: 5)
//        
//        defaults?.set(false, forKey: "isGameActive")
//        print("Live Activity test complete")
//    }
//}
//
//// Usage in a preview or test:
//struct TestingView: View {
//    var body: some View {
//        VStack(spacing: 20) {
//            Button("Simulate Rolls") {
//                DiceWidgetTestingUtilities.simulateRolls()
//            }
//            
//            Button("Clear Data") {
//                DiceWidgetTestingUtilities.clearAllData()
//            }
//            
//            Button("Test Live Activity") {
//                Task {
//                    await DiceWidgetTestingUtilities.testLiveActivity()
//                }
//            }
//        }
//        .buttonStyle(.borderedProminent)
//    }
//}
//#endif

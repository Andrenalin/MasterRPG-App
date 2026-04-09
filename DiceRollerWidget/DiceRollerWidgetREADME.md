# Dice Roller Widget with Liquid Glass Design

A comprehensive dice rolling widget for iOS with beautiful Liquid Glass design and Live Activity support during gameplay.

## Features

### 🎲 Widget Functionality
- **Multiple Widget Sizes**: Small, Medium, and Large widget support
- **Quick Dice Selection**: Choose from D4, D6, D8, D10, D12, D20, and D100
- **Roll History**: View your last roll directly in the widget
- **Interactive Buttons**: Tap dice in the widget to roll immediately using App Intents

### ✨ Liquid Glass Design
- **Modern Aesthetic**: Implements Apple's latest Liquid Glass design language
- **Adaptive Rendering**: Supports both full-color and accented rendering modes
- **Interactive Effects**: Glass elements respond to touch and hover interactions
- **Beautiful Transitions**: Smooth morphing between different dice states

### 🎮 Live Activity Support
- **Dynamic Island**: Shows dice rolls in the Dynamic Island on iPhone 14 Pro and later
- **Lock Screen**: Displays active dice rolls on the Lock Screen
- **Quick Actions**: Roll different dice types directly from the Live Activity
- **Game Integration**: Automatically activates during gameplay sessions

## Setup

### 1. Add Widget Extension Target

1. In Xcode, go to **File > New > Target**
2. Select **Widget Extension**
3. Name it `DiceRollerWidgetExtension`
4. Enable "Include Live Activity" when prompted

### 2. Configure App Groups

Both your main app and widget extension need access to a shared App Group:

1. Select your main app target
2. Go to **Signing & Capabilities**
3. Add **App Groups** capability
4. Create/select group: `group.de.andretrettin.MasterRPG`
5. Repeat for the widget extension target

### 3. Update Info.plist

Add to your main app's `Info.plist`:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>UIApplicationSupportsIndirectInputEvents</key>
<true/>
```

Add to your widget extension's `Info.plist`:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

### 4. Add Required Files

Copy all files from the `DiceRollerWidget` folder to your widget extension target:

- `DiceRollerWidget.swift` (main entry point)
- `DiceRollerProvider.swift` (timeline provider and data models)
- `DiceRollerWidgetView.swift` (widget UI)
- `DiceRollerIntents.swift` (App Intents for interactivity)
- `DiceRollerLiveActivity.swift` (Live Activity implementation)
- `DiceRollerAppIntegration.swift` (main app integration - add to main app target)

### 5. Configure URL Scheme (Optional)

To enable deep linking from widgets to your app:

1. Select your main app target
2. Go to **Info** tab
3. Add **URL Types**
4. Set **Identifier**: `de.andretrettin.MasterRPG`
5. Set **URL Schemes**: `masterrpg`

## Usage

### In the Main App

Add the dice roller view to your app:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            DiceRollerView()
        }
    }
}
```

### Enable Live Activity During Gameplay

```swift
// When starting a game session
let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
defaults?.set(true, forKey: "isGameActive")
defaults?.set("Dragon's Lair Campaign", forKey: "currentGameName")

// When ending a game session
defaults?.set(false, forKey: "isGameActive")

// End Live Activity
Task {
    await DiceRollerLiveActivityManager.shared.endActivity()
}
```

### Manual Live Activity Control

```swift
// Start or update Live Activity with a dice roll
let result = DiceRollResult(
    value: 18,
    diceType: .d20,
    timestamp: Date()
)

await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)

// End immediately
await DiceRollerLiveActivityManager.shared.endActivity()

// End after delay (10 seconds)
await DiceRollerLiveActivityManager.shared.endActivityWithDelay(seconds: 10)
```

## Architecture

### Data Flow

```
Main App
   ├─ Saves dice configuration to App Group UserDefaults
   ├─ Triggers widget reload via WidgetCenter
   └─ Manages Live Activity lifecycle

Widget Extension
   ├─ Reads configuration from App Group UserDefaults
   ├─ Provides timeline updates
   └─ Handles App Intent interactions

Live Activity
   ├─ Shows real-time dice rolls in Dynamic Island
   ├─ Displays on Lock Screen during games
   └─ Allows quick actions via buttons
```

### Liquid Glass Implementation

The widget uses several Liquid Glass techniques:

1. **Widget Rendering Modes**: Adapts to full-color and accented modes
2. **Glass Effect Modifiers**: Uses `.glassEffect()` on key elements
3. **Glass Button Style**: Interactive buttons with `.buttonStyle(.glass)`
4. **Glass Effect Container**: Groups related elements with `GlassEffectContainer`
5. **Widget Accentable**: Marks important content with `.widgetAccentable()`

### App Intents

Three main intents power widget interactivity:

- **RollDiceIntent**: Rolls a specific dice and updates the widget
- **SelectDiceIntent**: Changes the default dice type
- **ClearDiceHistoryIntent**: Clears roll history

## Customization

### Dice Types

Add or modify dice types in `DiceType` enum:

```swift
enum DiceType: String, Codable, CaseIterable {
    case d4 = "D4"
    case d6 = "D6"
    // ... add more
    
    var sides: Int {
        // Define number of sides
    }
}
```

### Colors and Theming

Customize result colors in the `resultColor(for:)` methods:

```swift
private func resultColor(for result: DiceRollResult) -> Color {
    if result.isCritical {
        return .green  // Critical success
    } else if result.isCriticalFailure {
        return .red    // Critical failure
    } else {
        return .blue   // Normal roll
    }
}
```

### Widget Sizes

Add or remove supported widget families:

```swift
.supportedFamilies([
    .systemSmall,
    .systemMedium,
    .systemLarge,
    .accessoryCircular,  // Watch complication
    .accessoryRectangular // Watch complication
])
```

## Testing

### Test Widget in Simulator

1. Run the widget extension scheme
2. Choose "Widget" as the run option
3. Select widget size to preview

### Test Live Activity

1. Enable Live Activities in Settings > [Your App]
2. Start a game session in your app
3. Roll dice to trigger Live Activity
4. View in Dynamic Island or Lock Screen

### Test on Device

Live Activities and Dynamic Island features require a physical device:
- iPhone 14 Pro or later for Dynamic Island
- iPhone 11 or later for Lock Screen Live Activities

## Integration with Existing Dice System

To integrate with your existing `DiceModel` and `GameController`:

```swift
// In your GameController
func rollAndUpdateWidget(die: DieModel, for itemId: UUID) async {
    // Your existing roll logic
    gameController.role(die: die, for: itemId)
    let result = await gameController.createDiceResult(for: itemId, resultCategory: ResultCategory(id: itemId, module: .dice))
    
    // Update widget
    let widgetResult = DiceRollResult(
        value: die.result.last ?? 0,
        diceType: convertToWidgetDiceType(die.die),
        timestamp: Date()
    )
    
    var config = DiceConfiguration.loadFromUserDefaults()
    config.lastRoll = widgetResult
    config.save()
    WidgetCenter.shared.reloadAllTimelines()
    
    // Update Live Activity
    if isGameActive {
        await DiceRollerLiveActivityManager.shared.startOrUpdate(with: widgetResult)
    }
}

private func convertToWidgetDiceType(_ rawDie: RawDie) -> DiceType {
    switch rawDie.sides {
    case .four: return .d4
    case .six: return .d6
    case .eight: return .d8
    case .ten: return .d10
    case .twelve: return .d12
    case .twenty: return .d20
    case .number(let n) where n == 100: return .d100
    default: return .d20
    }
}
```

## Performance Considerations

- Widget timelines update every 15 minutes by default
- Live Activities can run for up to 8 hours
- App Intents execute in the background efficiently
- Liquid Glass effects are GPU-accelerated

## Accessibility

All components include proper accessibility support:
- VoiceOver labels for all interactive elements
- Dynamic Type support for text
- High contrast mode compatibility
- Reduced motion support

## Requirements

- iOS 18.0+ (for Liquid Glass and latest Live Activity features)
- Xcode 16.0+
- Swift 6.0+

## License

Copyright © André Trettin

---

## Additional Resources

- [Apple Documentation: WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [Apple Documentation: ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Apple Documentation: App Intents](https://developer.apple.com/documentation/appintents)
- [Liquid Glass Design Guide](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)

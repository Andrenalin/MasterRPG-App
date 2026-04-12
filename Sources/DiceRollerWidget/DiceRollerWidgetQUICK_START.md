# 🎲 Dice Roller Widget - Quick Start Guide

## ⚡ 5-Minute Setup

### Step 1: Create Widget Extension (2 minutes)

1. In Xcode, go to **File → New → Target**
2. Search for and select **Widget Extension**
3. Click **Next**
4. Name it: `DiceRollerWidgetExtension`
5. ✅ **Check** "Include Live Activity"
6. Click **Finish**
7. Click **Activate** when prompted

### Step 2: Configure App Groups (1 minute)

**For Main App Target:**
1. Select your main app target in Xcode
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Click **+** and add: `group.de.andretrettin.MasterRPG`

**For Widget Extension Target:**
1. Select **DiceRollerWidgetExtension** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Select the same: `group.de.andretrettin.MasterRPG`

### Step 3: Update Info.plist (1 minute)

**Main App Info.plist:**
Add these keys:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>UIApplicationSupportsIndirectInputEvents</key>
<true/>
```

**Widget Extension Info.plist:**
Add these keys:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

### Step 4: Add Files (1 minute)

**To Widget Extension Target** (check the target membership):
- ✅ `DiceRollerWidget.swift`
- ✅ `DiceRollerProvider.swift`
- ✅ `DiceRollerWidgetView.swift`
- ✅ `DiceRollerIntents.swift`
- ✅ `DiceRollerLiveActivity.swift`

**To Main App Target:**
- ✅ `DiceRollerAppIntegration.swift`
- ✅ `DiceRollerExamples.swift` (optional)

### Step 5: Build and Run!

1. Select the **DiceRollerWidgetExtension** scheme
2. Choose **Widget (Small)** as the run destination
3. Click **Run** ▶️
4. The widget preview should appear!

---

## 🎯 Test Your Widget in 3 Steps

### Test 1: Widget Preview
```swift
// In Xcode, open DiceRollerWidget.swift
// Look for #Preview blocks
// Click the preview to see widget
```

### Test 2: Roll from App
```swift
// Add to your app:
import WidgetKit

Button("Roll D20") {
    let result = DiceRollResult(value: 18, diceType: .d20, timestamp: .now)
    var config = DiceConfiguration.loadFromUserDefaults()
    config.lastRoll = result
    config.save()
    WidgetCenter.shared.reloadAllTimelines()
}
```

### Test 3: Live Activity (Requires Device)
```swift
// Start game session:
let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
defaults?.set(true, forKey: "isGameActive")
defaults?.set("Test Game", forKey: "currentGameName")

// Roll dice:
let result = DiceRollResult(value: 20, diceType: .d20, timestamp: .now)
await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)

// Check Dynamic Island! 🎉
```

---

## 🎨 See Liquid Glass in Action

Run this in a SwiftUI preview:

```swift
#Preview {
    ZStack {
        // Colorful background to show glass effect
        LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        
        // Liquid Glass dice
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 20) {
                ForEach([DiceType.d20, .d12, .d10], id: \.self) { dice in
                    VStack {
                        Image(systemName: dice.systemImage)
                            .font(.largeTitle)
                        Text(dice.rawValue)
                            .font(.caption)
                    }
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular.interactive())
                }
            }
        }
    }
}
```

---

## 🐛 Troubleshooting

### Widget not showing?
- ✅ Check target membership of files
- ✅ Verify App Group is identical in both targets
- ✅ Clean build folder (Cmd+Shift+K)
- ✅ Rebuild project

### Live Activity not working?
- ⚠️ **Must test on real device** (not simulator)
- ✅ Enable Live Activities in Settings → [Your App]
- ✅ Verify `NSSupportsLiveActivities` in Info.plist
- ✅ Check game is marked as active: `isGameActive = true`

### App Group not found?
- ✅ Ensure identical group name in both targets
- ✅ Check provisioning profile supports App Groups
- ✅ Re-select team in Signing & Capabilities

### Liquid Glass not visible?
- ✅ Test on iOS 18.0 or later
- ✅ Try with a colorful background
- ✅ Check widget is in accented rendering mode
- ✅ Verify `.containerBackgroundRemovable(true)`

---

## 📱 Add Widget to Home Screen

1. Long press on Home Screen
2. Tap **+** in top corner
3. Search for your app name
4. Select **Dice Roller** widget
5. Choose size (Small, Medium, or Large)
6. Tap **Add Widget**
7. Tap **Done**

---

## 🎮 Integration with Your Game

### Minimal Integration (Copy & Paste Ready!)

Add this extension to your `GameController`:

```swift
import WidgetKit

extension GameController {
    
    func updateDiceWidget(die: DieModel, for itemId: UUID) {
        guard let value = die.result.last else { return }
        
        // Convert to widget dice type
        let widgetType: DiceType
        switch die.die.sides {
        case .four: widgetType = .d4
        case .six: widgetType = .d6
        case .eight: widgetType = .d8
        case .ten: widgetType = .d10
        case .twelve: widgetType = .d12
        case .twenty: widgetType = .d20
        default: return
        }
        
        // Create result
        let result = DiceRollResult(
            value: value,
            diceType: widgetType,
            timestamp: Date()
        )
        
        // Update widget
        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = result
        config.save()
        WidgetCenter.shared.reloadAllTimelines()
        
        // Update Live Activity
        Task {
            let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
            if defaults?.bool(forKey: "isGameActive") == true {
                await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
            }
        }
    }
}
```

Then in your roll function:
```swift
private func roleDice(_ die: DieModel) async {
    root.gameController.role(die: die, for: itemId)
    let result = await root.gameController.createDiceResult(for: itemId, resultCategory: ResultCategory(id: itemId, module: .dice))
    networkActions?.game(result, .generic, nil)
    
    // ⭐ Add this line:
    root.gameController.updateDiceWidget(die: die, for: itemId)
}
```

**That's it! Your dice rolls now update the widget! 🎉**

---

## 🎊 Success Checklist

- [ ] Widget appears in preview
- [ ] Can add widget to Home Screen
- [ ] Tapping dice in widget triggers roll
- [ ] Widget shows last roll result
- [ ] Liquid Glass effects visible
- [ ] Widget adapts to Home Screen theme
- [ ] Live Activity appears on device
- [ ] Dynamic Island shows dice results
- [ ] Lock Screen displays Live Activity
- [ ] Game session controls work

---

## 🚀 What's Next?

### Customize Your Widget
1. Change colors in `resultColor(for:)` methods
2. Add more dice types to `DiceType` enum
3. Customize widget layouts in `DiceRollerWidgetView.swift`
4. Adjust glass effects with different tints

### Advanced Features
1. Add roll statistics tracking
2. Implement dice roll history view
3. Add haptic feedback
4. Support Watch complications
5. Add Siri shortcuts

---

## 📚 Full Documentation

For detailed documentation, see:
- **README.md** - Complete feature list and setup
- **IMPLEMENTATION_SUMMARY.md** - Architecture overview
- **DiceRollerExamples.swift** - 10 code examples

---

## 🎯 Key Files Reference

| File | Purpose | Target |
|------|---------|--------|
| `DiceRollerWidget.swift` | Main widget entry | Widget Extension |
| `DiceRollerProvider.swift` | Data & timeline | Widget Extension |
| `DiceRollerWidgetView.swift` | Widget UI | Widget Extension |
| `DiceRollerIntents.swift` | Interactivity | Widget Extension |
| `DiceRollerLiveActivity.swift` | Live Activity | Widget Extension |
| `DiceRollerAppIntegration.swift` | App integration | Main App |

---

## 💪 You're Ready!

Your dice roller widget with Liquid Glass design and Live Activity support is ready to roll! 🎲✨

**Questions?** Check the detailed documentation in README.md

**Need help?** Review the examples in DiceRollerExamples.swift

**Happy Rolling!** 🎲🎲🎲

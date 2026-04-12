# Dice Module App Intents - Complete Reference

## Current Intents

### ✅ Implemented

1. **OpenDiceIntent**
   - Opens a specific dice in the app
   - Used for: Deep linking, Spotlight, Siri shortcuts
   - Conforms to: `OpenIntent`, `TargetContentProvidingIntent`

2. **DiceEntityQuery**
   - Finds dice by ID, name, or provides all dice
   - Used for: Entity discovery in Shortcuts and Siri
   - Methods: `suggestedEntities()`, `entities(for:)`, `entities(matching:)`, `allEntities()`

3. **RollDiceIntent** (in `DiceRollerIntents.swift`)
   - Rolls a generic dice type (D4, D6, D8, etc.)
   - Used for: Widgets, quick rolling without selecting specific dice
   - Parameters: `diceType: IntentDiceType`

4. **RollSpecificDiceIntent** ⭐ NEW
   - Rolls a specific dice from the user's collection
   - Used for: Shortcuts, Siri, Spotlight actions
   - Parameters: `dice: DiceEntity`
   - Returns: Dialog and visual snippet with roll result

5. **ClearDiceHistoryIntent** (in `DiceRollerIntents.swift`)
   - Clears the dice roll history
   - Used for: Shortcuts, maintenance actions

## Recommended Future Intents

### High Priority

6. **GetLastRollIntent**
   ```swift
   struct GetLastRollIntent: AppIntent {
       static let title: LocalizedStringResource = "Get Last Roll"
       func perform() async throws -> some IntentResult & ReturnsValue<Int>
   }
   ```
   - Returns the last rolled value
   - Useful for: Shortcuts automation, checking results

7. **ListFavoriteDiceIntent**
   ```swift
   struct ListFavoriteDiceIntent: AppIntent {
       static let title: LocalizedStringResource = "List Favorite Dice"
       func perform() async throws -> some IntentResult & ReturnsValue<[DiceEntity]>
   }
   ```
   - Lists only favorited dice
   - Useful for: Quick access to frequently used dice

### Medium Priority

8. **RollMultipleDiceIntent**
   ```swift
   struct RollMultipleDiceIntent: AppIntent {
       static let title: LocalizedStringResource = "Roll Multiple Dice"
       @Parameter(title: "Dice") var dice: [DiceEntity]
       func perform() async throws -> some IntentResult & ReturnsValue<[Int]>
   }
   ```
   - Rolls multiple dice at once
   - Returns array of results

9. **CompareDiceRollIntent**
   ```swift
   struct CompareDiceRollIntent: AppIntent {
       static let title: LocalizedStringResource = "Roll and Compare"
       @Parameter(title: "Dice") var dice: DiceEntity
       @Parameter(title: "Target Number") var targetNumber: Int
       func perform() async throws -> some IntentResult & ReturnsValue<Bool>
   }
   ```
   - Rolls and compares against a target number
   - Returns success/failure boolean

10. **FindDiceByTagIntent**
    ```swift
    struct FindDiceByTagIntent: AppIntent {
        static let title: LocalizedStringResource = "Find Dice by Tag"
        @Parameter(title: "Tag") var tag: String
        func perform() async throws -> some IntentResult & ReturnsValue<[DiceEntity]>
    }
    ```
    - Finds dice filtered by tag
    - Useful for: Organization, campaign-specific dice

### Low Priority (Nice to Have)

11. **CreateQuickDiceIntent**
    - Creates a temporary dice configuration
    - Useful for: One-off rolls without saving

12. **ExportDiceIntent**
    - Exports dice configuration
    - Useful for: Sharing with other players

13. **GetDiceStatsIntent**
    - Returns statistics about a dice (average, min, max)
    - Useful for: Analysis, education

## Intent Usage Matrix

| Intent | Siri | Shortcuts | Widgets | Spotlight | Live Activity |
|--------|------|-----------|---------|-----------|---------------|
| OpenDiceIntent | ✅ | ✅ | - | ✅ | - |
| RollDiceIntent | ✅ | ✅ | ✅ | - | ✅ |
| RollSpecificDiceIntent | ✅ | ✅ | - | ✅ | ✅ |
| ClearDiceHistoryIntent | ✅ | ✅ | ✅ | - | - |
| GetLastRollIntent | ✅ | ✅ | - | - | - |

## Implementation Pattern

All dice intents follow this pattern:

```swift
#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import SwiftUI

struct MyDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Intent Title"
    static let description = IntentDescription("Description")
    
    @Parameter(title: "Parameter Name")
    var parameter: DiceEntity
    
    @Dependency var root: DiceRootModel
    
    init() {}
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // Implementation
        return .result()
    }
}

#if os(iOS)
extension MyDiceIntent: TargetContentProvidingIntent {}
#endif

#endif
```

## App Intent Registration

Ensure intents are registered in your `AppIntentsProvider` or equivalent:

```swift
struct DiceAppIntentsProvider: AppIntentsPackage {
    static var includedAppIntents: [any AppIntent.Type] {
        [
            OpenDiceIntent.self,
            RollDiceIntent.self,
            RollSpecificDiceIntent.self,
            ClearDiceHistoryIntent.self,
            // Add new intents here
        ]
    }
}
```

## Testing Checklist

For each new intent:
- [ ] Test in Shortcuts app
- [ ] Test with Siri voice command
- [ ] Test in Spotlight (if applicable)
- [ ] Test parameter selection
- [ ] Test error handling
- [ ] Test with empty data sets
- [ ] Test localization
- [ ] Test on all supported platforms (iOS, iPadOS, macOS)

## Best Practices

1. **Always use `@MainActor`** when accessing UI models
2. **Provide clear dialogs** for voice feedback
3. **Return useful values** for Shortcuts automation
4. **Handle errors gracefully** with user-friendly messages
5. **Use entity queries** for parameter discovery
6. **Include snippet views** for visual feedback when appropriate
7. **Update widgets** after state-changing operations
8. **Support Live Activities** for game-related intents
9. **Platform-guard** with `#if !os(tvOS)` where AppIntents isn't available
10. **Conform to `TargetContentProvidingIntent`** on iOS for Spotlight integration

## Related Documentation

- OpenDiceIntent: See other module intents (OpenTableIntent, OpenPhotoIntent, etc.)
- DiceEntityQuery: Standard entity query pattern
- RollDiceIntent: Widget integration example
- RollSpecificDiceIntent: Complete implementation with snippet view

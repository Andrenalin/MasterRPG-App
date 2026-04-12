# RollSpecificDiceIntent Implementation

## Overview
This document describes the implementation of `RollSpecificDiceIntent`, which allows users to roll specific dice from their collection via Siri, Shortcuts, and Spotlight.

## What Was Implemented

### 1. RollSpecificDiceIntent (New File: `RollSpecificDiceIntent.swift`)

A new App Intent that enables users to:
- Select a specific dice from their collection
- Roll it with all configured options (modifiers, reroll options, coup/fumble detection)
- See visual feedback with a snippet view
- Store the result for widgets and Live Activities
- Receive appropriate dialog responses based on roll outcome

#### Key Features:

**Parameters:**
- `dice: DiceEntity` - The specific dice to roll (user can select from their collection)

**Dependencies:**
- `root: DiceRootModel` - Access to the dice data model

**Roll Logic:**
The intent properly handles:
- Multiple dice in a dice model (rolls all of them)
- Reroll options configured on the dice
- Sum vs. single die results
- Modifiers
- Critical success (coup) detection
- Critical failure (fumble) detection
- Formatted value display (e.g., "1, 4, 6 +2 = 13")

**Result Handling:**
- Creates a `DiceResultModel` with complete roll information
- Saves to `DiceConfiguration` for widget display
- Reloads all widgets via `WidgetCenter`
- Starts or updates Live Activity if a game is active
- Returns contextual dialog ("🎉 Critical Success!", "💥 Critical Failure!", or "🎲 Rolled...")

**Visual Feedback:**
- Provides a `RollResultSnippetView` that shows:
  - Result type icon (star for coup, warning for fumble, checkmark for normal)
  - Dice name
  - Final sum in large, bold text
  - Breakdown of individual die results and modifier

### 2. Enhanced DiceEntity Transferable (Updated: `DiceEntity.swift`)

Updated the `Transferable` conformance to match other modules:
- **PDF Export**: Now exports dice as PDF files with:
  - Dice name and description
  - Configuration details (individual dice, modifiers)
  - Professional formatting at 600pt width
- **Plain Text Export**: Kept existing text export for backward compatibility

## How to Use

### Via Siri
Users can say:
- "Roll my dice"
- "Roll [dice name]"

### Via Shortcuts
1. Add "Roll Specific Dice" action
2. Select which dice to roll
3. Optional: Use the result value in subsequent actions

### Via Spotlight (iOS)
1. Search for a dice in Spotlight
2. Tap the dice result
3. Use the "Roll" action

## Integration Points

### Required Dependencies:
- `DiceRootModel` - Provides access to dice data
- `DiceConfiguration` - Stores roll results
- `WidgetKit` - Reloads widgets after rolling
- `DiceRollerLiveActivityManager` - Updates Live Activities during games

### App Intent Registration:
Make sure to register this intent in your app's intent configuration. The intent will automatically appear in:
- Shortcuts app
- Siri suggestions
- Spotlight actions (when `TargetContentProvidingIntent` is adopted)

## Optional: Enable Spotlight Actions

To enable this intent to appear in Spotlight search results for dice, add this conformance to `RollSpecificDiceIntent`:

```swift
#if os(iOS)
extension RollSpecificDiceIntent: TargetContentProvidingIntent {}
#endif
```

This will make the roll action appear directly in Spotlight when users search for their dice.

## Testing

### Manual Testing:
1. Create a dice in your app
2. Open Shortcuts app
3. Create a new shortcut with "Roll Specific Dice" action
4. Select the dice you created
5. Run the shortcut
6. Verify:
   - Correct result is calculated
   - Widgets update
   - Dialog message is appropriate
   - Snippet view displays correctly

### Voice Testing:
1. Invoke Siri
2. Say "Roll [your dice name]"
3. Verify Siri responds with the roll result

## Future Enhancements

Consider adding:
1. **Batch Rolling**: Roll multiple dice at once
2. **Roll History Intent**: View recent rolls
3. **Favorite Dice Intent**: Quick access to favorite dice
4. **Custom Roll Intent**: Roll with temporary modifiers
5. **Compare Rolls Intent**: Roll against a target number

## Architecture Notes

This implementation follows the same pattern as other module intents:
- Entity-based (uses `DiceEntity`)
- Query-based discovery (uses `DiceEntityQuery`)
- Dependency injection (uses `@Dependency`)
- Result-oriented (returns dialog and snippet view)
- Platform-aware (`#if !os(tvOS)`)

The intent integrates seamlessly with:
- Existing dice rolling logic
- Widget system
- Live Activities
- Configuration storage
- Game session management

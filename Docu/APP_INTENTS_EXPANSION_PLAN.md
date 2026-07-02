# App Intents Expansion Plan for MasterRPG

## Overview
This plan outlines the implementation of comprehensive App Intents to expose MasterRPG's features to Siri, Shortcuts, Spotlight, and Apple Intelligence. The app uses a **modular architecture** where each feature module contains its own App Intents.

## Current State

### ✅ Existing Modules with App Intents

**DiceRPG Module:**
- ✅ `DiceEntity` (IndexedEntity with Spotlight support)
- ✅ `DiceEntityQuery` (EntityQuery, EntityStringQuery, EnumerableEntityQuery with caching)
- ✅ `OpenDiceIntent` (OpenIntent)
- ✅ `RollDiceIntent` - Roll simple dice (D4-D20)
- ✅ `RollSpecificDiceIntent` - Roll specific dice with snippet view
- ✅ `ShowDiceHistoryIntent` - Show recent rolls
- ✅ `DiceShortcuts` (AppShortcutsProvider)
- ✅ `DiceFrameworkPackage` (AppIntentsPackage)
- ✅ `IntentDiceType` (AppEnum for dice types)
- ✅ `ConfigureDiceWidgetIntent` - Widget configuration

**MapRPG Module:**
- ✅ `MapEntity` (IndexedEntity)
- ✅ `MapEntityQuery` (EntityQuery, EntityStringQuery, EnumerableEntityQuery)
- ✅ `OpenMapIntent` (OpenIntent)
- ✅ `MapShortcuts` (AppShortcutsProvider)
- ✅ `MapFrameworkPackage` (AppIntentsPackage)

**SpaceRPG Module:**
- ✅ `SpaceEntity` (IndexedEntity)
- ✅ `SpaceEntityQuery` (EntityQuery, EntityStringQuery, EnumerableEntityQuery)
- ✅ `OpenSpaceIntent` (OpenIntent)
- ✅ `SpaceShortcuts` (AppShortcutsProvider)
- ✅ `SpaceFrameworkPackage` (AppIntentsPackage)

**GeneratorRPG Module:**
- ✅ `GeneratorEntity` (IndexedEntity)
- ✅ `GeneratorEntityQuery` (EntityQuery, EntityStringQuery, EnumerableEntityQuery)

**WeatherRPG Module:**
- ✅ `WeatherEntity` (IndexedEntity)
- ✅ `WeatherEntityQuery` (EntityQuery, EntityStringQuery, EnumerableEntityQuery)

### 📋 Modules Identified (Need App Intents)

Based on `MasterRPGApp.swift`, these modules exist but need App Intents:
- ❌ **AdventureRPG** - `adventureRoot: AdventureRootModel`
- ❌ **AudioRPG** - `audioRoot: AudioRootModel`
- ❌ **CharacterRPG** - `characterRoot: CharacterRootModel`
- ❌ **PDFRPG** - `pdfRoot: PDFRootModel`
- ❌ **PhotoRPG** - `photoRoot: PhotoRootModel`
- ❌ **TableRPG** - `tableRoot: TableRootModel`

## Goals
1. Enable users to perform common RPG tasks via Siri voice commands
2. Create reusable shortcuts for frequent actions
3. Make app content discoverable in Spotlight
4. Support Apple Intelligence and Visual Intelligence integration
5. Provide interactive snippets for rich Siri responses
6. Enable Control Center widgets for quick actions
7. **Follow modular architecture** - All intents live in their respective modules

---

## Phase 1: Core Game Actions (Priority: HIGH)

### 1.1 Dice Rolling Intents
**Files to create:** `DiceIntents.swift`, `DiceEntities.swift`, `DiceEntityQuery.swift`

#### Intents to implement:
- **RollDiceIntent** - Roll any combination of dice
  - Parameters: dice type (d4, d6, d8, d10, d12, d20, d100), count, modifier
  - Phrases: "Roll a d20 in \(.applicationName)", "Roll 3d6 with \(.applicationName)"
  - Returns: Result with breakdown and total
  - Interactive snippet showing roll results

- **RollSavingThrowIntent** - Roll a saving throw
  - Parameters: ability (STR, DEX, CON, etc.), modifier, DC
  - Phrases: "Roll a dexterity save in \(.applicationName)"
  - Returns: Success/failure with margin

- **RollSkillCheckIntent** - Roll a skill check
  - Parameters: skill name, modifier, advantage/disadvantage
  - Phrases: "Roll a stealth check in \(.applicationName)"
  - Returns: Result with natural roll and modified total

- **QuickRollFavoriteDiceIntent** - Roll a saved favorite dice combination
  - Parameters: favorite dice entity
  - Phrases: "Roll my favorite dice in \(.applicationName)"
  - Returns: Result

#### Entities:
- **DiceEntity** - Represents a die type and configuration
  - Properties: type, count, modifier, label
  - Query: EnumerableEntityQuery for standard dice types

- **DiceRollResultEntity** - Represents a roll result
  - Properties: individual values, total, timestamp
  - IndexedEntity for Spotlight search of recent rolls

### 1.2 Character Management Intents
**Files to create:** `CharacterIntents.swift`, `CharacterEntities.swift`, `CharacterEntityQuery.swift`

#### Intents to implement:
- **GetCharacterIntent** - Retrieve character information
  - Parameters: character entity
  - Phrases: "Show my character in \(.applicationName)"
  - Returns: Character stats in snippet view

- **UpdateCharacterHPIntent** - Modify character hit points
  - Parameters: character entity, HP change (damage/healing), new value
  - Phrases: "Heal my character 10 HP in \(.applicationName)", "Take 5 damage in \(.applicationName)"
  - Returns: New HP total with confirmation
  - Requires: Confirmation for damage

- **LevelUpCharacterIntent** - Increase character level
  - Parameters: character entity
  - Phrases: "Level up my character in \(.applicationName)"
  - Returns: New level confirmation
  - Requires: Confirmation, authentication

- **ListCharactersIntent** - Get all characters
  - Phrases: "Show my characters in \(.applicationName)"
  - Returns: List in snippet view

- **CreateCharacterIntent** - Start character creation flow
  - Parameters: character name, class, race
  - Phrases: "Create a new character in \(.applicationName)"
  - Opens app with prefilled character creation

#### Entities:
- **CharacterEntity** - Represents a player character
  - Properties: name, class, race, level, HP, maxHP, AC, stats
  - Query: EntityStringQuery for search by name
  - IndexedEntity for Spotlight
  - UniqueAppEntity variant for "current character"

- **CharacterClassEntity** - Character classes
  - AppEnum: Fighter, Wizard, Rogue, Cleric, etc.

- **CharacterRaceEntity** - Character races
  - AppEnum: Human, Elf, Dwarf, Halfling, etc.

### 1.3 Game Session Intents
**Files to create:** `GameSessionIntents.swift`, `GameSessionEntities.swift`

#### Intents to implement:
- **StartGameSessionIntent** - Start a new game session
  - Parameters: adventure/campaign entity
  - Phrases: "Start a game session in \(.applicationName)"
  - Opens app and activates game mode
  - Donates for prediction

- **EndGameSessionIntent** - End current session
  - Phrases: "End my game session in \(.applicationName)"
  - Saves state and creates session log

- **GetSessionStatusIntent** - Check if game is active
  - Phrases: "Is my game active in \(.applicationName)"
  - Returns: Session status snippet

#### Entities:
- **GameSessionEntity** - Represents a game session
  - Properties: start time, duration, adventure, participants
  - Query: Recent sessions for history

---

## Phase 2: Content Management (Priority: MEDIUM)

### 2.1 Adventure/Campaign Intents
**Files to create:** `AdventureIntents.swift`, `AdventureEntities.swift`

#### Intents to implement:
- **OpenAdventureIntent** - Open a specific adventure
  - Parameters: adventure entity
  - Phrases: "Open my adventure in \(.applicationName)"
  - Opens app to adventure view
  - Implements OpenIntent protocol

- **ListAdventuresIntent** - Show all adventures
  - Phrases: "Show my adventures in \(.applicationName)"
  - Returns: List snippet

- **CreateAdventureIntent** - Create new adventure
  - Parameters: adventure name
  - Phrases: "Create a new adventure in \(.applicationName)"
  - Opens app to creation flow

#### Entities:
- **AdventureEntity** - Represents an adventure/campaign
  - Properties: name, description, created date, last played
  - Query: EntityStringQuery for search
  - IndexedEntity for Spotlight

### 2.2 Map Intents
**Files to create:** `MapIntents.swift`, `MapEntities.swift`

#### Intents to implement:
- **OpenMapIntent** - Open a specific map
  - Parameters: map entity
  - Phrases: "Show the dungeon map in \(.applicationName)"
  - Opens app to map view

- **AddMapMarkerIntent** - Add marker to current map
  - Parameters: marker type, location description
  - Phrases: "Add a treasure marker in \(.applicationName)"
  - Requires: Foreground mode

#### Entities:
- **MapEntity** - Represents a game map
  - Properties: name, thumbnail, location count
  - Query: EntityStringQuery
  - IndexedEntity for Spotlight

### 2.3 Audio/Music Intents
**Files to create:** `AudioIntents.swift`, `AudioEntities.swift`

#### Intents to implement:
- **PlayAudioIntent** - Play ambient audio/music
  - Parameters: audio entity, volume
  - Phrases: "Play tavern music in \(.applicationName)"
  - Starts audio playback

- **StopAudioIntent** - Stop current audio
  - Phrases: "Stop music in \(.applicationName)"

- **ListAudioIntent** - Show available audio
  - Phrases: "Show audio in \(.applicationName)"
  - Returns: Audio library snippet

#### Entities:
- **AudioEntity** - Represents an audio track
  - Properties: name, category (ambient, combat, tavern, etc.), duration
  - Query: EnumerableEntityQuery or EntityStringQuery
  - AppEnum for categories

### 2.4 Weather Intents
**Files to create:** `WeatherIntents.swift`, `WeatherEntities.swift`

#### Intents to implement:
- **GetWeatherIntent** - Get current weather in game world
  - Parameters: location entity (optional)
  - Phrases: "What's the weather in \(.applicationName)"
  - Returns: Weather snippet with conditions

- **SetWeatherIntent** - Change weather conditions
  - Parameters: weather type, intensity
  - Phrases: "Make it rain in \(.applicationName)"
  - Updates weather state

#### Entities:
- **WeatherConditionEntity** - Weather types
  - AppEnum: Clear, Cloudy, Rain, Snow, Storm, Fog, etc.

---

## Phase 3: Generator & Utilities (Priority: MEDIUM)

### 3.1 Generator Intents
**Files to create:** `GeneratorIntents.swift`, `GeneratorEntities.swift`

#### Intents to implement:
- **GenerateNPCIntent** - Generate random NPC
  - Parameters: race (optional), class (optional), level range
  - Phrases: "Generate an NPC in \(.applicationName)"
  - Returns: NPC details snippet

- **GenerateTreasureIntent** - Generate random treasure
  - Parameters: challenge rating, treasure type
  - Phrases: "Generate treasure in \(.applicationName)"
  - Returns: Treasure list snippet

- **GenerateEncounterIntent** - Generate random encounter
  - Parameters: party level, difficulty, environment
  - Phrases: "Generate an encounter in \(.applicationName)"
  - Returns: Encounter details snippet

- **GenerateNameIntent** - Generate random name
  - Parameters: name type (person, place, tavern, etc.), culture
  - Phrases: "Generate an elf name in \(.applicationName)"
  - Returns: Name with pronunciation

### 3.2 Table/Reference Intents
**Files to create:** `TableIntents.swift`, `TableEntities.swift`

#### Intents to implement:
- **RollOnTableIntent** - Roll on a random table
  - Parameters: table entity
  - Phrases: "Roll on the wild magic table in \(.applicationName)"
  - Returns: Table result

- **LookupRuleIntent** - Look up a game rule
  - Parameters: rule topic
  - Phrases: "Look up grappling rules in \(.applicationName)"
  - Opens app to rule reference

#### Entities:
- **TableEntity** - Represents a random table
  - Properties: name, category, entry count
  - Query: EntityStringQuery
  - IndexedEntity for Spotlight

---

## Phase 4: Advanced Features (Priority: LOW)

### 4.1 Photo/Asset Intents
**Files to create:** `PhotoIntents.swift`

#### Intents to implement:
- **AddPhotoIntent** - Add photo to current adventure
  - Parameters: photo, description
  - Phrases: "Add this photo to my adventure in \(.applicationName)"
  - Requires: Foreground mode

- **ShowPhotosIntent** - Show adventure photos
  - Phrases: "Show adventure photos in \(.applicationName)"
  - Opens photo gallery

### 4.2 Visual Intelligence Integration (iOS 26+)
**Files to create:** `VisualSearchIntents.swift`, `VisualSearchQuery.swift`

#### Implementation:
- **RPGVisualSearchQuery** - IntentValueQuery for visual search
  - Matches: Miniatures, dice, maps, character sheets
  - Returns: Relevant entities (characters, adventures, maps)
  - Opens appropriate content in app

#### Use cases:
- Point camera at dice → recognize type, suggest rolls
- Point camera at character sheet → open character
- Point camera at map → open map view
- Point camera at miniature → open creature stats

### 4.3 Control Center Widgets (iOS 18+)
**Files to create:** `ControlWidgets.swift`

#### Widgets to implement:
- **QuickDiceControl** - Roll favorite dice from Control Center
  - Toggle or button to roll
  - Shows last result

- **GameSessionControl** - Start/stop game session
  - Toggle for active/inactive

- **AudioControl** - Play/stop ambient audio
  - Plays last used audio track

### 4.4 Interactive Snippets
**Files to create:** `SnippetIntents.swift`, `SnippetViews.swift`

#### Snippet Intents:
- **CharacterStatsSnippetIntent** - Show character card
  - Interactive buttons: "Heal", "Take Damage", "Rest"

- **DiceResultSnippetIntent** - Show roll result
  - Interactive buttons: "Roll Again", "Add to Log"

- **EncounterSnippetIntent** - Show encounter details
  - Interactive buttons: "Start Combat", "Add to Notes"

---

## Phase 5: Spotlight & Discovery (Priority: MEDIUM)

### 5.1 Indexed Entities
Make all major entities searchable in Spotlight:

**Entities to index:**
1. **CharacterEntity** - Search characters by name, class, level
2. **AdventureEntity** - Search adventures by name, tags
3. **MapEntity** - Search maps by name, location
4. **TableEntity** - Search tables by name, category
5. **DiceRollResultEntity** - Search recent rolls
6. **AudioEntity** - Search audio tracks

**Implementation:**
- Named Spotlight index: `"com.masterrpg.spotlight"`
- Index on entity creation/update
- Delete on entity removal
- Use `indexingKey` for iOS 26+ metadata mapping

### 5.2 OpenIntent Implementations
Every indexed entity needs an OpenIntent:
- **OpenCharacterIntent** - Opens character sheet
- **OpenAdventureIntent** - Opens adventure
- **OpenMapIntent** - Opens map view
- **OpenTableIntent** - Opens table reference
- **OpenAudioIntent** - Plays audio track

---

## Phase 6: App Shortcuts Provider (Priority: HIGH)

### 6.1 Pre-defined Shortcuts
**File to create:** `MasterRPGShortcuts.swift`

```swift
struct MasterRPGShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Core shortcuts that appear immediately
    }
    static var shortcutTileColor: ShortcutTileColor = .red
}
```

#### Shortcuts to provide:
1. "Roll d20 in MasterRPG"
2. "Show my character in MasterRPG"
3. "Start game session in MasterRPG"
4. "Generate NPC in MasterRPG"
5. "Play tavern music in MasterRPG"
6. "What's the weather in MasterRPG"
7. "Roll on random table in MasterRPG"
8. "Open my adventure in MasterRPG"

---

## Implementation Details

### Directory Structure
```
MasterRPG/
├── AppIntents/
│   ├── Core/
│   │   ├── MasterRPGShortcuts.swift
│   │   └── AppIntentsPackage.swift
│   ├── Dice/
│   │   ├── DiceIntents.swift
│   │   ├── DiceEntities.swift
│   │   ├── DiceEntityQuery.swift
│   │   └── DiceSnippets.swift
│   ├── Character/
│   │   ├── CharacterIntents.swift
│   │   ├── CharacterEntities.swift
│   │   ├── CharacterEntityQuery.swift
│   │   └── CharacterSnippets.swift
│   ├── Adventure/
│   │   ├── AdventureIntents.swift
│   │   ├── AdventureEntities.swift
│   │   └── AdventureEntityQuery.swift
│   ├── Audio/
│   │   ├── AudioIntents.swift
│   │   ├── AudioEntities.swift
│   │   └── AudioEntityQuery.swift
│   ├── Generator/
│   │   ├── GeneratorIntents.swift
│   │   ├── GeneratorEntities.swift
│   │   └── GeneratorSnippets.swift
│   ├── Maps/
│   │   ├── MapIntents.swift
│   │   └── MapEntities.swift
│   ├── Weather/
│   │   ├── WeatherIntents.swift
│   │   └── WeatherEntities.swift
│   ├── Tables/
│   │   ├── TableIntents.swift
│   │   └── TableEntities.swift
│   ├── GameSession/
│   │   ├── GameSessionIntents.swift
│   │   └── GameSessionEntities.swift
│   ├── Photos/
│   │   └── PhotoIntents.swift
│   ├── VisualIntelligence/
│   │   ├── VisualSearchQuery.swift
│   │   └── VisualSearchIntents.swift
│   └── ControlWidgets/
│       └── RPGControlWidgets.swift
```

### Dependency Injection Pattern
Use existing AppDependencyManager for intent access to app state:

```swift
struct RollDiceIntent: AppIntent {
    func perform() async throws -> some IntentResult {
        let diceModel = AppDependencyManager.shared.resolve(DiceRootModel.self)
        let result = await diceModel.roll(dice: dice)
        return .result(value: result, dialog: "Rolled \(result.total)")
    }
}
```

### App Group for Widget Communication
Ensure App Group is configured:
- **App Group ID:** Already using `UserDefaults.appGroupString`
- Share data between app, widgets, and intents

### Testing Strategy
1. **Shortcuts App Testing**
   - Create test shortcuts for each intent
   - Test parameter resolution
   - Verify dialogs and results

2. **Siri Testing**
   - Test voice phrases
   - Verify disambiguation
   - Test error cases

3. **Spotlight Testing**
   - Verify entities appear in search
   - Test OpenIntent navigation
   - Validate metadata

4. **Widget Testing**
   - Test Control Center widgets
   - Verify Live Activities integration
   - Test interactive buttons

---

## Success Metrics

### User Experience Goals
- [ ] Users can perform 90% of common actions via Siri
- [ ] All major content types are searchable in Spotlight
- [ ] Quick actions available from Control Center
- [ ] Rich interactive snippets for complex results
- [ ] Voice commands work reliably with natural language

### Technical Goals
- [ ] All intents have proper parameter summaries
- [ ] All entities have display representations
- [ ] Spotlight index stays synchronized
- [ ] Confirmation required for destructive actions
- [ ] Authentication required for sensitive operations
- [ ] All intents handle errors gracefully
- [ ] Intent performance < 1 second for simple operations

---

## Timeline Estimate

### Week 1-2: Phase 1 (Core Game Actions)
- Dice intents (3 days)
- Character intents (4 days)
- Game session intents (2 days)
- Testing (1 day)

### Week 3: Phase 2 Part 1 (Content Management)
- Adventure intents (2 days)
- Map intents (2 days)
- Audio intents (2 days)
- Weather intents (1 day)

### Week 4: Phase 3 (Generator & Utilities)
- Generator intents (3 days)
- Table intents (2 days)
- Testing (2 days)

### Week 5: Phase 4 (Advanced Features)
- Photo intents (1 day)
- Visual Intelligence (2 days)
- Control Center widgets (2 days)
- Interactive snippets (2 days)

### Week 6: Phase 5 (Spotlight & Discovery)
- Implement IndexedEntity for all major types (2 days)
- OpenIntent implementations (1 day)
- Spotlight indexing logic (2 days)
- Testing (2 days)

### Week 7: Phase 6 & Polish
- App Shortcuts Provider (1 day)
- Documentation (1 day)
- End-to-end testing (3 days)
- Bug fixes and refinement (2 days)

**Total Estimated Time:** 7 weeks

---

## Next Steps

1. **Review this plan** - Prioritize features based on user needs
2. **Set up project structure** - Create AppIntents directory
3. **Start with Phase 1** - Implement core dice and character intents
4. **Iterate and test** - Build one feature at a time with testing
5. **Gather feedback** - Test with users and refine

---

## Additional Resources

### Documentation References
- [SKILL.md](SKILL.md) - App Intents skill guide
- [appintents-advanced.md](appintents-advanced.md) - Advanced patterns
- Apple's App Intents documentation
- WWDC 2025 App Intents sessions

### Code Examples Location
- Existing: `DiceRollerProvider.swift` - Widget configuration example
- Existing: `ConfigureDiceWidgetIntent` - Basic intent example

### Testing Resources
- Shortcuts app for manual testing
- Xcode's App Intents preview
- Spotlight testing on device
- Siri phrase testing

---

## Notes

- **Platform Support:** Target iOS 18+ for full feature set, iOS 26+ for Visual Intelligence
- **Localization:** All strings should use `LocalizedStringResource`
- **Privacy:** Request appropriate permissions for photos, location (if used)
- **Performance:** Keep intent execution under 1 second when possible
- **Error Handling:** Always provide clear error messages and recovery paths
- **Accessibility:** Ensure all voice commands work for VoiceOver users


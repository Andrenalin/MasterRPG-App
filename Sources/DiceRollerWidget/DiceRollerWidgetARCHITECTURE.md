# Dice Roller Widget Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Main RPG App                            │
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────┐            │
│  │  GameController  │────────▶│  DiceRoller      │            │
│  │                  │         │  AppIntegration  │            │
│  │  - Rolls dice    │         │                  │            │
│  │  - Game logic    │         │  - Config view   │            │
│  └──────────────────┘         │  - In-app roller │            │
│           │                    └──────────────────┘            │
│           │                             │                      │
│           ▼                             ▼                      │
│  ┌─────────────────────────────────────────────────┐          │
│  │      Shared UserDefaults (App Group)            │          │
│  │   group.de.andretrettin.MasterRPG               │          │
│  │                                                  │          │
│  │  - diceConfiguration                            │          │
│  │  - rollHistory                                  │          │
│  │  - isGameActive                                 │          │
│  │  - currentGameName                              │          │
│  └─────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                           │
                           │ shares data
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Widget Extension                             │
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────┐            │
│  │ DiceRoller       │────────▶│ DiceRoller       │            │
│  │ Widget           │         │ WidgetView       │            │
│  │                  │         │                  │            │
│  │ - Config         │         │ - Small widget   │            │
│  │ - Timeline       │         │ - Medium widget  │            │
│  └──────────────────┘         │ - Large widget   │            │
│                                └──────────────────┘            │
│  ┌──────────────────┐                                          │
│  │ DiceRoller       │         ┌──────────────────┐            │
│  │ Intents          │────────▶│ DiceRoller       │            │
│  │                  │         │ LiveActivity     │            │
│  │ - Roll dice      │         │                  │            │
│  │ - Select dice    │         │ - Dynamic Island │            │
│  │ - Clear history  │         │ - Lock Screen    │            │
│  └──────────────────┘         └──────────────────┘            │
│           │                             │                      │
│           │                             │                      │
│           ▼                             ▼                      │
│     WidgetCenter                  ActivityKit                  │
│     (Reload)                      (Live Activity)              │
└─────────────────────────────────────────────────────────────────┘
                           │
                           │ displays on
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      iOS System UI                              │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Home Screen  │  │   Dynamic    │  │ Lock Screen  │        │
│  │   Widget     │  │    Island    │  │   Widget     │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Roll Dice from Main App
```
User taps "Roll D20"
        │
        ▼
GameController.rollDice()
        │
        ▼
Create DiceRollResult
        │
        ▼
Save to App Group UserDefaults
        │
        ├─────────────────────────┐
        ▼                         ▼
WidgetCenter.reload()    Start/Update LiveActivity
        │                         │
        ▼                         ▼
  Widget updates          Dynamic Island shows
   on Home Screen           dice result
```

### Roll Dice from Widget
```
User taps dice button in widget
        │
        ▼
RollDiceIntent.perform()
        │
        ▼
Roll random value
        │
        ▼
Create DiceRollResult
        │
        ▼
Save to App Group UserDefaults
        │
        ├─────────────────────────┐
        ▼                         ▼
WidgetCenter.reload()    Start/Update LiveActivity
        │                         │
        ▼                         ▼
  Widget shows result     Dynamic Island animates
```

## Liquid Glass Architecture

### Widget Glass Effects
```
┌─────────────────────────────────────────────────────┐
│              DiceRollerWidgetView                   │
│                                                     │
│  ┌────────────────────────────────────────────┐   │
│  │     containerBackground(for: .widget)      │   │
│  │     - Transparent in normal mode           │   │
│  │     - Replaced with glass in accented mode │   │
│  └────────────────────────────────────────────┘   │
│                                                     │
│  ┌────────────────────────────────────────────┐   │
│  │          widgetRenderingMode               │   │
│  │          @Environment                      │   │
│  │          - .fullColor                      │   │
│  │          - .accented                       │   │
│  └────────────────────────────────────────────┘   │
│                                                     │
│  ┌────────────────────────────────────────────┐   │
│  │            Glass Elements                  │   │
│  │                                            │   │
│  │  Dice Result                               │   │
│  │    └─ .widgetAccentable()                 │   │
│  │                                            │   │
│  │  Quick Roll Buttons                        │   │
│  │    └─ .widgetAccentedRenderingMode()      │   │
│  └────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Live Activity Glass Effects
```
┌─────────────────────────────────────────────────────┐
│          DiceRollerLiveActivityView                 │
│                                                     │
│  ┌────────────────────────────────────────────┐   │
│  │      GlassEffectContainer                  │   │
│  │      spacing: 20                           │   │
│  │                                            │   │
│  │  ┌──────────────────────────────────┐     │   │
│  │  │  Dice Result Display             │     │   │
│  │  │  .glassEffect(                   │     │   │
│  │  │    .regular                      │     │   │
│  │  │    .tint(resultColor)            │     │   │
│  │  │    .interactive()                │     │   │
│  │  │  )                               │     │   │
│  │  └──────────────────────────────────┘     │   │
│  │                                            │   │
│  │  ┌──────────────────────────────────┐     │   │
│  │  │  Quick Roll Buttons              │     │   │
│  │  │  .buttonStyle(.glass)            │     │   │
│  │  └──────────────────────────────────┘     │   │
│  └────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Component Hierarchy

### Widget Extension Target
```
DiceRollerWidget.swift (main entry)
│
├── DiceRollerProvider.swift
│   ├── DiceRollerEntry
│   ├── DiceConfiguration
│   ├── DiceType (enum)
│   └── DiceRollResult
│
├── DiceRollerWidgetView.swift
│   ├── smallWidgetView
│   ├── mediumWidgetView
│   ├── largeWidgetView
│   ├── diceResultView
│   └── quickDiceGrid
│
├── DiceRollerIntents.swift
│   ├── RollDiceIntent
│   ├── SelectDiceIntent
│   └── ClearDiceHistoryIntent
│
└── DiceRollerLiveActivity.swift
    ├── DiceRollerActivityAttributes
    ├── DiceRollerLiveActivityView
    └── DiceRollerLiveActivityManager
```

### Main App Target
```
DiceRollerAppIntegration.swift
│
├── DiceRollerWidgetConfiguration
│   ├── Widget settings
│   ├── Live Activity toggle
│   └── Liquid Glass preview
│
└── DiceRollerView
    ├── In-app dice roller
    ├── Glass effect demonstrations
    └── Widget synchronization
```

## Live Activity Lifecycle

### State Diagram
```
┌─────────────┐
│  Game Not   │
│   Active    │
└──────┬──────┘
       │ User starts game
       │ isGameActive = true
       ▼
┌─────────────┐
│  Waiting    │──────┐
│  for Roll   │      │ User ends game
└──────┬──────┘      │
       │ First roll  │
       ▼             │
┌─────────────┐      │
│   Active    │      │
│  Activity   │◀─┐   │
└──────┬──────┘  │   │
       │          │   │
       │ New roll │   │
       ├──────────┘   │
       │              │
       │ End game     │
       ▼              │
┌─────────────┐      │
│  Dismissing │      │
│  (delay)    │      │
└──────┬──────┘      │
       │             │
       └─────────────┘
       ▼
┌─────────────┐
│   Ended     │
└─────────────┘
```

## Widget Size Layouts

### Small Widget (2x2)
```
┌──────────────┐
│              │
│   ┌──────┐   │
│   │  🎲  │   │  ← Dice icon or result
│   │  18  │   │
│   └──────┘   │
│              │
│     D20      │  ← Dice type
│              │
└──────────────┘
```

### Medium Widget (4x2)
```
┌────────────────────────────────┐
│  ┌────────┐  │  Quick Roll     │
│  │  🎲    │  │                 │
│  │  18    │  │  [D4][D6][D8]  │
│  │        │  │  [D10][D12][D20]│
│  │  D20   │  │                 │
│  └────────┘  │                 │
└────────────────────────────────┘
```

### Large Widget (4x4)
```
┌────────────────────────────────┐
│       Dice Roller              │
├────────────────────────────────┤
│         ┌──────┐               │
│         │  🎲  │               │
│         │  18  │               │
│         └──────┘               │
│          D20                   │
├────────────────────────────────┤
│      Quick Roll                │
│                                │
│  [D4]  [D6]  [D8]  [D10]      │
│                                │
│  [D12] [D20] [D100]            │
└────────────────────────────────┘
```

## Dynamic Island States

### Compact
```
Left: [🎲]    Right: [18]
```

### Minimal
```
[🎲]
```

### Expanded
```
┌─────────────────────────────────┐
│  🎲          Roll: 18        ⭕18│
│                                 │
│  Quick Roll:                    │
│  [D4] [D6] [D8] [D10] [D12] [D20]│
└─────────────────────────────────┘
```

## File Dependencies

```
DiceRollerWidget.swift
    └─ requires: DiceRollerProvider.swift
    └─ requires: DiceRollerWidgetView.swift

DiceRollerWidgetView.swift
    └─ requires: DiceRollerProvider.swift (models)
    └─ requires: DiceRollerIntents.swift (buttons)

DiceRollerLiveActivity.swift
    └─ requires: DiceRollerProvider.swift (models)
    └─ requires: DiceRollerIntents.swift (actions)
    └─ requires: ActivityKit (framework)

DiceRollerIntents.swift
    └─ requires: DiceRollerProvider.swift (models)
    └─ requires: AppIntents (framework)
    └─ requires: WidgetKit (reload)

DiceRollerAppIntegration.swift
    └─ requires: DiceRollerProvider.swift (models)
    └─ requires: DiceRollerLiveActivity.swift (manager)
    └─ requires: WidgetKit (reload)
```

## Integration Points with Existing Code

```
┌─────────────────────────────────────────────────┐
│           Your Existing Code                    │
│                                                 │
│  DiceRoll.swift                                 │
│    └─ roleDice()                                │
│         └─ Add: updateDiceWidget() ─────────┐  │
│                                              │  │
│  GameController.swift                        │  │
│    └─ role(die:for:)                        │  │
│         └─ Add: updateDiceWidget() ─────────┤  │
│                                              │  │
│  DieModel.swift                              │  │
│    └─ Add: widgetDiceType property ─────────┤  │
│                                              │  │
└──────────────────────────────────────────────┼──┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────┐
│         Widget Integration Layer                │
│                                                 │
│  Extension GameController {                    │
│    func updateDiceWidget(die:for:)             │
│  }                                             │
│                                                 │
│  Extension DieModel {                          │
│    var widgetDiceType: DiceType? { }           │
│    func updateWidget()                         │
│  }                                             │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│            Widget System                        │
│                                                 │
│  - Updates widget timeline                     │
│  - Triggers Live Activity                      │
│  - Syncs configuration                         │
└─────────────────────────────────────────────────┘
```

## Threading & Concurrency

```
Main App Thread
    │
    ├─ User Action (roll dice)
    │   └─ @MainActor functions
    │
    ├─ GameController logic
    │   └─ async functions
    │
    └─ Widget Update
        └─ Background: Save to UserDefaults
        └─ Main: WidgetCenter.reload()
        └─ Task: Update Live Activity

Widget Extension Background
    │
    ├─ TimelineProvider
    │   └─ getTimeline() on background queue
    │
    ├─ App Intent
    │   └─ perform() on background queue
    │       └─ WidgetCenter.reload() switches to main
    │
    └─ Live Activity Manager
        └─ @MainActor functions
```

## Security & Privacy

```
┌─────────────────────────────────────────┐
│          App Sandbox                    │
│  ┌───────────────────────────────────┐  │
│  │      Main App Container           │  │
│  │  - Full app data                  │  │
│  │  - Private files                  │  │
│  └───────────────────────────────────┘  │
│                                          │
│  ┌───────────────────────────────────┐  │
│  │   Shared App Group Container      │  │
│  │   group.de.andretrettin.MasterRPG │  │
│  │                                   │  │
│  │  - DiceConfiguration              │  │◀─ Shared
│  │  - Roll history                   │  │  between
│  │  - Game status                    │  │  targets
│  │  - Current game name              │  │
│  └───────────────────────────────────┘  │
│                                          │
│  ┌───────────────────────────────────┐  │
│  │   Widget Extension Container      │  │
│  │  - Widget-specific cache          │  │
│  │  - Timeline data                  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

This architecture provides:
- ✅ Clear separation of concerns
- ✅ Efficient data sharing via App Groups
- ✅ Beautiful Liquid Glass UI
- ✅ Seamless Live Activity integration
- ✅ Type-safe Swift code
- ✅ Minimal performance impact
- ✅ Easy integration with existing code

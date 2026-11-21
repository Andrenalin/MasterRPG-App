# Agent guide for Swift and SwiftUI
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. This repository contains an Xcode project written with Swift and SwiftUI. Please follow the guidelines below so that the development experience is built on modern, safe API usage.

## Role
You are a **Senior iOS Engineer**, specializing in SwiftUI, CoreData, and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.
## About MasterRPG
MasterRPG is a multi-platform Apple app for managing RPG data: Adventures, Characters, Maps, Photos, Audios, PDFs, 3D Objects, Tables, Weathers. It has a game mode where players can join via Shareplay or local network. Platforms: iOS, macOS, tvOS, visionOS.

## Build Commands
```bash
# Build main app for iOS Simulator
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
# Build for macOS
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterMac -destination 'platform=macOS' build
# Build for visionOS (concrete simulator, see "Simulators" below)
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination "platform=visionOS Simulator,id=$(xcrun simctl list devices available | awk '/^-- visionOS 27/{f=1;next} /^--/{f=0} f&&/Apple Vision Pro/{match($0,/[0-9A-F-]{36}/);print substr($0,RSTART,RLENGTH);exit}')" build
# Build for tvOS
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
```

## Simulators
Several runtimes are installed side by side (iOS 26.5/27.2, visionOS 26.5/27.2, tvOS 27.2), so a device **name** can resolve to a different simulator than the one the app was installed on. Always check with `xcrun simctl list devices available`.
- Use the **newest runtime** (27.x). Pin the simulator with `id=<UDID>` whenever the name exists on more than one runtime (e.g. `Apple Vision Pro`). A name-based destination installs/launches on one device and tests on another, which fails with `Simulator device failed to launch de.AndreTrettin.GameMaster ... NotFound ("Launch Transaction error")`.
- iOS/iPadOS: `iPhone 18 Pro` (unique name, fine by name). tvOS: `Apple TV 4K (3rd generation)`. visionOS: `Apple Vision Pro` on the visionOS 27.2 runtime, by id.
- The generic `platform=visionOS Simulator` / `generic/platform=visionOS Simulator` destination can fail with a stale `EagerLinkingTBDs` x86_64 linker error; build for the concrete simulator instead.

## Test Commands
```bash
# Run all tests (iOS)
xcodebuild test -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
# One suite
xcodebuild test -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:GameRPGTests/GameTablePinPawnTests
```

visionOS-only suites (`#if os(visionOS)`, e.g. `GameTablePinPawnTests`) need the visionOS simulator by id, and the `MasterRPG` scheme's visionOS `build-for-testing` currently fails inside the third-party `swift-snapshot-testing` package (`cannot find 'Image' in scope`). Workaround:
1. Copy `MasterRPG.xcodeproj/xcshareddata/xcschemes/GameRPGTests.xcscheme` to a temporary scheme and remove its `GameRPGSnapshotTests` `<TestableReference>` (the snapshot tests do not build for visionOS).
2. `xcodebuild build-for-testing` then `test-without-building` with that scheme, `-destination 'platform=visionOS Simulator,id=<UDID>'` and `-only-testing:GameRPGTests/<Suite>`.
3. Delete the temporary scheme afterwards; never commit it.

The Xcode MCP `RunSomeTests` can report "not run" (cached test list, wrong simulator, empty result bundle); fall back to `xcodebuild` and read its `✔`/`✘` lines.

## Tech Stack
- **Language**: Swift 6.3 and `SWIFT_STRICT_CONCURRENCY = complete` for all targets
- **Build Setting**: Swift 6.0, SWIFT_STRICT_CONCURRENCY = complete, no default actor isolation (for skill swift concurrency)
- **Approachable concurrency**: `SWIFT_APPROACHABLE_CONCURRENCY = YES`, so a `nonisolated` async function runs on its caller's actor (often the main actor). Mark CPU or I/O work `@concurrent`, or run it through `runOffCallerExecutor`, to leave the caller's actor; protocol-extension functions such as `importStream`, `updateGame` and `reveal` run wherever they are called from.
- **SDK**: iOS26, iPadOS26, tvOS26, visionOS26, macOS26 or later
- Swift 6.3 or later, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- **Pattern**: Model View Controller
- **Dependency management**: Swift Package Manager for visionOS 3d content

## Swift instructions
- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.
- Naming convention: use `Id`/`Url` casing (e.g. `itemId`, `fileUrl`), not `ID`/`URL` (e.g. `itemID`, `fileURL`) — this matches the existing, dominant convention across the codebase. Don't drift to Swift API Design Guidelines casing for these two suffixes specifically, even in new code.

## SwiftUI instructions
- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and `defaultScrollAnchor`); avoid older scrollView APIs like ScrollViewReader.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.

## CoreData instructions
If CoreData is configured to use CloudKit:
- Model properties must always either have default values or be marked as optional.
- All relationships must be marked optional.

## Architecture
- MVC: Model @Observable classes, Controller stateless structs, View SwiftUI structs
- RootModel for each module, that holds the controller hierarchy as ItemRootController
- RootManager hold the root models for the modules
- Module Factory builds the root model and root views
- Domain Model mapped into the Core Data model

### Targets
- **MasterRPG**: Main iOS/visionOS app
- **MasterMac**: Mac app
- **MasterTV**: AppleTV app
- **DiceRollerWidgetExtension**: iOS home screen widgets, LiveActivity, LockScreen (Dice, DiceRoller)

### Controllers
- **ItemController** holds the items and manage the list, trigger the save into the database
- **EditController** manipulate the item model and entry model
- **DataController** is the mapper between domain model and database model
- **SyncDataController** merges the cloudkit core data updates into the ItemController.
- **CacheController** is the cache for the images and thumbnails
- **ImportController** handles the import from file or network
- **ExportController** exports the item model into streamable json / binary data
- **FolderListController** handles the list / folder display, selection state
- **LinkController** handles the link generation, validation and toggling.
- **GameController** has the logic during the game runs
- **SearchController** handles how to search / filter
- **SheetController** generates a sheet representation of the item / entries
   
### Key Patterns
**State Management**: Uses modern `@Observable` macro (iOS 26+) instead of `ObservableObject`. Views use `@Environment(Type.self)` for dependency injection, not `@EnvironmentObject`.
**Data Persistence**: Core Data with CloudKit sync (`NSPersistentCloudKitContainer`). Saved rpg data across all devices in  iCloud or stores only locally

### Key Modules
- AdventureRPG: Module Adventure manage and manipulate the adventure for a game. It is the story and link all other modules
- AudioRPG: Module Audio manage and manipulate the music for a game, It manages the files in iCloud.
- CharacterRPG: Module Character manage and manipulate the character (player), NPC and monster for a game. It link tables, dice, photo and pdf into the values. It groups values.
- DiceRPG: Module Dice manage and manipulate the dice for a game. It rolls a dice and feed the dice widget
- MapRPG: Module Map manage and manipulate the maps for a game. A map is photo with layers to hide content from the players. It has a own MapEditor to create these layers (rooms). It can link to character, maps, dice, tables, audio, pdf and photo. 
- PdfRPG: Module Pdf manage and manipulate the pdf for a game. It manages the files in iCloud.
- PhotoRPG: Module Photo manage and manipulate the photo for a game. It manages the files in iCloud.
- SpaceRPG: Module Space manage and manipulate the 3d objects for a game. It manages the files in iCloud.
- TableRPG: Module Table manage and manipulate the tables for a game. It can link to dice, pdf and tables.
- WeatherRPG: Module Weather manage and manipulate the weather for a game. It can link to photo.
- RuleRPG: Module Rule manages an editable, importable rules/compendium hierarchy normalized from sources like Foundry VTT system packages; linked from AdventureRPG, GameRPG search/logging, and RolePlayGameKit navigation.

### Other Modules
- CoreRPG: It is the shared code for the modules and has core views, models and controller.
- GeneratorRPG: FoundationModel and Views used in Pdf, Adventure. Planned in Character.
- GameRPG: All Game Views, Shareplay, Network, Bonjour and MasterController, PlayerController to send the gamestate. GameTableView uses TabletopKit for visionOS
- RolePlayGameKit: Merges all Modules and provide navigation / layout views for all apps.  

### Dependencies (SPM)
- **RPGTabletopGameContent**: visionOS 3D content

### Folder Structure

- **Modules** Source code for the modules / dynamic frameworks
- **Resources** info.plist, entitlements and Resource Modules
- **Sources** Target Apps specific source code
- **Tests** Tests for modules
- **TestPlans** Test plan for MasterRPG and modules

#### Module Folder Structure
- **Controller** for the different controllers
- **Intent** for App-Intents, Siri, Shortcuts and Widgets
- **Menu** for Menu on mac / iPad command
- **Preview** for `#if DEBUG` preview and mock fixtures (GameRPG)
- **Model** Domain Model and Database Model
- **Resources** Database file, Localizations
- **Root** Root View, Models and entry of the module
- **Route** Routes for the Navigator
- **View** Other views
 
## 3D Game Table (`Modules/GameRPG/Table3D`)
Two implementations share one model (`GameTableModel`), `Board`/`BoardTextureRenderer`, `MapTableProjection`, `PinPawn` and `RoomHitArea`:
- **visionOS**: a volumetric TabletopKit table with seats, a pre-allocated dice pool per seat (`GameDice.swift`), SharePlay seat assignment (`TableSeatAssignment`) and pinch-to-scale.
- **iOS/macOS**: a camera-based RealityKit table (`GamePortable*`, `GameTableView+PlatformFlat`) showing map, fog and pins. It has **no dice or seats by design**. On macOS a bare mouse drag orbits the camera; on iOS it moves the table.

Rules for this module:
- Every game-master edit is broadcast through `broadcastMapEdit(for:)`, which honours the "pause sharing" toggle (`isStreaming`). Only `sendMapUpdates()` (explicit "Refresh Shared Map") calls `broadcastMapState(for:)` directly.
- Fog/board renders go through `replaceFogOfWarTask()` / `handleMapChange` (cancel-then-replace). Never call the render pipeline directly from another module; use `refreshFogOfWar(isGameMaster:)`.
- A closure stored on the model must never capture a SwiftUI view value (its `@State` storage holds the model).
- Keep syncs idempotent: `PinPawn.update`, `RoomHitArea.update` and `applyDiceRoll` skip unchanged state because they run on every map sync (each TabletopKit action is a SharePlay message).
- On visionOS a started game opens the table by itself: `MasterGameScreen`/`PlayerGameScreen` call `GameTableLauncher.open` (decided by `GameTableAutoOpenPolicy`, one shot per game screen). The 2D game screen must stay alive behind it (it hosts the game logic and quits the game on disappear), so it is pushed aside by the Recover window, never dismissed.
- Put decisions that don't need TabletopKit/RealityKit in pure types (`TableSeatAssignment`, `MapTableProjection`) so they can be unit-tested on iOS.

## Platform Conditionals
Use `#if os(iOS)`, `#if os(macOS)`, `#if os(tvOS)`, `#if os(visionOS)` for platform-specific code. Widget extensions gate extension-unavailable APIs with `#if !os(...)`/API-availability checks on a case-by-case basis — no `WIDGET_EXTENSION` Swift compilation condition is defined on any target, so don't write `#if !WIDGET_EXTENSION` expecting it to do anything (it silently evaluates as always-true).
All modules using the bundle version of SwiftUI views for example `Text("Editor Window", bundle: .module)` for the correct Localizations.

## App Groups & Entitlements
- App Group: `group.de.andretrettin.MasterRPG` (shared data between app and widgets)
- iCloud Container: `iCloud.de.andretrettin.gamemaster`
- Background Modes: audio, airplay, remote-notification

## Xcode MCP
If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this project:
- `DocumentationSearch` — verify API availability and correct usage before writing code
- `BuildProject` — build the project after making changes to confirm compilation succeeds
- `GetBuildLog` — inspect build errors and warnings
- `RenderPreview` — visually verify SwiftUI views using Xcode Previews
- `XcodeListNavigatorIssues` — check for issues visible in the Xcode Issue Navigator
- `ExecuteSnippet` — test a code snippet in the context of a source file
- `XcodeRead`, `XcodeWrite`, `XcodeUpdate` — prefer these over generic file tools when working with Xcode project files

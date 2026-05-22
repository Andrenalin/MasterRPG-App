# CLAUDE.md
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About MasterRPG
MasterRPG is a multi-platform Apple app for managing RPG data: Adventures, Characters, Maps, Photos, Audios, PDFs, 3D Objects, Tables, Weathers. It has a game mode there players can join via Shareplay or local network. Platforms: iOS, macOS, tvOS, visionOS.

## Build Commands
```bash
# Build main app for iOS / visionOS Simulator
xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Build for macOS
xcodebuild -scheme MasterMac -destination 'platform=macOS' build
# Build for tvOS
xcodebuild -scheme MasterTV -destination 'platform=tvOS Simulator' build
```

## Test Commands
```bash
# Run all tests
xcodebuild test -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Tech Stack
- **Language**: Swift 6.3
- **SDK**: iOS26, iPadOS26, tvOS26, visionOS26, macOS26
- **UI**: SwiftUI
- **Pattern**: MVC
- **Dependency management**: Swift Package Manager for visionOS 3d content

## Architecture
- MVC: Model @Observable classes, Controller stateless structs, View swiftUI structs
- RootModel for each module, that holds the controller hierarchy as ItemRootController
- RootManager hold the root models for the modules
- Module Factory builds the root model and root views
- Domain Model mapped into the Core Data model

### Targets
- **MasterRPG**: Main iOS/visionOS app
- **MasterMac**: Mac app
- **MasterTV**: AppleTV app
- **DiceRollerWidgetExtension**: iOS home screen widgets, LiveActivity, LockScreen (Dicem RiceRoller)

### Controllers
- **ItemController** holds the items and manage the list, trigger the save into the database
- **EditController** manipulate the item model and entry model
- **DataController** is the mapper between domain model and database model
- **SyncDataController** merges the cloudkit core data updates into the ItemController.
- **CacheController** is the cache for the imsges and thumbnails
- **ImportController** handles the import from file or network
- **ExportController** exports the item model into streamable json / binary data
- **FolderListController** handles the list / folder display, selection state
- **LinkController** handles the link generation, validation and toggling.
- **GameController** has the logic during the game runs
- **SearchController** handles how to search / filter
- **SheetController** generates a sheet representation of the item / entries
   
### Key Patterns
**State Management**: Uses modern `@Observable` macro (iOS 17+) instead of `ObservableObject`. Views use `@Environment(Type.self)` for dependency injection, not `@EnvironmentObject`.
**Data Persistence**: Core Data with CloudKit sync (`NSPersistentCloudKitContainer`). Saved rpg data across all devices in  iCloud or stores only locally

### Key Modules
- AdventureRPG: Module Adventure manage and manipluate the adventure for a game. It is the story and link all other modules
- AudioRPG: Module Audio manage and manipluate the music for a game, It manages the files in iCloud.
- CharacterRPG: Module Character manage and manipluate the character (player), NPC and monster for a game. It link tables, dice, photo and pdf into the values. It groupes values.
- DiceRPG: Module Dice manage and manipluate the dice for a game. It rolls a dice and feed the dice widget
- MapRPG: Module Map manage and manipluate the maps for a game. A map is photo with layers to hide content from the players. It has a own MapEditor to create these layers (rooms). It can link to charactere, maps, dice, tables, audio, pdf and photo. 
- PdfRPG: Module Pdf manage and manipluate the pdf for a game. It manages the files in iCloud.
- PhotoRPG: Module Photo manage and manipluate the photo for a game. It manages the files in iCloud.
- SpaceRPG: Module Space manage and manipluate the 3d objects for a game. It manages the files in iCloud.
- TableRPG: Module Table manage and manipluate the tables for a game. It can link to dice, pdf and tables.
- WeatherRPG: Module Weather manage and manipluate the weather for a game. It can link to photo.

### Other Modules
- CoreRPG: It is the shared code for the modules and has core views, models and controller.
- GeneratorRPG: FoundationModel and Views used in Pdf, Adventure. Planned in Character.
- GameRPG: All Game Views, Shareplay, Network, Bonjour and MasterController, PlayerController to send the gamestate. GameTableView uses TableTopKit for visionOS
- RolePlayGameKit: Merges all Moduls and provide navigation / layoput views for all apps.  

### Dependencies (SPM)
- **RPGTabletopGameContent**: visionOS 3D content

### Folder strrcture in modules
- **Controller** for the different controllers
- **Intent** for App-Intentm, Siri, Shrotcuts and Widgets
- **Menu** for Menu on mac / iPad command
- **Model** Domain Model and Database Model
- **Module** Module specific code
- **Resources** Database file, LOcalaizations
- **Root** Root View, Models and entry of the module
- **Route** Routes for the Navigator
- **View** Other views
 
## Platform Conditionals
Use `#if os(iOS)`, `#if os(macOS)`, `#if os(tvOS)`, `#if os(visionOS)` for platform-specific code. Widget extension code uses `#if !WIDGET_EXTENSION` to exclude unavailable APIs.

## App Groups & Entitlements
- App Group: `group.de.andretrettin.MasterRPG` (shared data between app and widgets)
- iCloud Container: `iCloud.de.andretrettin.MasterRPG`
- Background Modes: audio, airplay, remote-notification, fetch

# MasterRPG

Multi-platform Apple app (iOS, iPadOS, macOS, visionOS, tvOS) for managing RPG data: Adventures, Characters, Maps, Photos, Audios, PDFs, 3D Objects, Tables, Weathers, Rules. Game mode lets players join via SharePlay or local network. Follow Apple's Human Interface Guidelines and App Review Guidelines.

## Build & verify
Use the `build-verify` skill for build/test commands, simulator selection, visionOS test workarounds and runtime verification. The essentials:
- After shared-code changes, build ALL platforms. Before merging to main, also do a Release build.
- Stale-module/TBD link errors: clean build the affected module right away, don't retry incremental builds.
- A successful build is not proof a UI change works: verify in the simulator, or tell the user the exact manual steps when that's impossible.

## Editing rules
- Never use regex bulk edits or helper scripts to split or rewrite Swift files. Make targeted Edit calls.
- In `.xcstrings` catalogs, insert new keys in place. Never re-sort or reformat the whole file.
- After any large edit, check for duplicated content with `git diff --stat`.
- Don't introduce third-party frameworks without asking first. Avoid UIKit unless requested.

## Git workflow
- Work happens on `develop`. "Ship it" means: follow `.claude/skills/ship-rpg/SKILL.md` (also `/ship-rpg`).
- GitHub `origin` is the only remote.

## Swift & concurrency
- Swift 6.3 compiler, Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, **no** default main-actor isolation. Deployment target: OS 26 on every platform.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`: a `nonisolated` async function runs on its caller's actor (often the main actor). Mark CPU or I/O work `@concurrent`, or run it through `runOffCallerExecutor`, to leave the caller's actor. Protocol-extension functions such as `importStream`, `updateGame` and `reveal` run wherever they are called from.
- `@Observable` classes must be `@MainActor`; flag any that aren't. Pass them with `@State` (ownership) and `@Environment` / `@Bindable`. No `ObservableObject` / `@Published` / `@EnvironmentObject` outside legacy code.
- Prefer async/await APIs, modern Swift concurrency (no GCD) and `FormatStyle` (no `Formatter` subclasses, no `String(format:)`).
- Filter user-entered text with `localizedStandardContains()`.

## Project conventions
- Use `Id`/`Url` casing (`itemId`, `fileUrl`), never `ID`/`URL`, even in new code.
- Don't name new types after system types (`MapKind`); prefix them with the domain (`MapPlaceKind`).
- Modules localize through their own bundle: `Text("Editor Window", bundle: .module)`.
- Don't break views up into computed properties; make new `View` structs. Put view logic in models/controllers so it can be tested.
- No hard-coded font sizes (use Dynamic Type), padding or stack spacing unless requested.
- Platform code uses `#if os(iOS)` / `os(macOS)` / `os(tvOS)` / `os(visionOS)`. No `WIDGET_EXTENSION` compilation condition exists, so `#if !WIDGET_EXTENSION` is always true; gate widget-unavailable APIs with `#if !os(...)` or availability checks.
- Core Data syncs through CloudKit: model properties need a default or must be optional, and all relationships are optional.

## Architecture
MVC: models are `@MainActor @Observable` classes, controllers are stateless structs, views are SwiftUI structs. Domain models are mapped into the Core Data model.
- Each module has a RootModel holding its controller hierarchy (`ItemRootController`); `RootManager` holds the root models; a module Factory builds the root model and root views.
- Controller roles by name: `Item` (list + save), `Edit`, `Data` (domain ↔ Core Data), `SyncData` (merges CloudKit updates), `Cache`, `Import`, `Export`, `FolderList`, `Link`, `Game`, `Search`, `Sheet`.
- `Modules/` holds one dynamic framework per domain (`AdventureRPG`, `MapRPG`, …). Non-obvious ones: `CoreRPG` (shared code), `GameRPG` (game views, SharePlay/network, Master/PlayerController, 3D table), `GeneratorRPG` (Foundation Models), `RuleRPG` (rules/compendium imported e.g. from Foundry VTT), `RolePlayGameKit` (merges the modules, app navigation/layout).
- Apps: `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `DiceRollerWidgetExtension`. App-specific code in `Sources/`, tests in `Tests/`, test plans in `TestPlans/`.
- App Group `group.de.andretrettin.MasterRPG`, iCloud container `iCloud.de.andretrettin.gamemaster`.
- The 3D game table has its own rules in `Modules/GameRPG/Table3D/CLAUDE.md`.

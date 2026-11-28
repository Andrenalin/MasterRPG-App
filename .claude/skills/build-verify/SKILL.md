---
name: build-verify
description: Build, test and runtime-verify MasterRPG across iOS, macOS, tvOS and visionOS. Use before running xcodebuild or Xcode MCP build/test tools, when picking a simulator, running a test suite (including visionOS-only suites), doing a Release build before merging, or verifying a UI/interaction change in the simulator.
---

# Build, test and verify MasterRPG

## Build all platforms
After shared-code changes build ALL platforms, not just iOS.

```bash
# iOS
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
# macOS
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterMac -destination 'platform=macOS' build
# visionOS (concrete simulator by id, see "Simulators")
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination "platform=visionOS Simulator,id=$(xcrun simctl list devices available | awk '/^-- visionOS 27/{f=1;next} /^--/{f=0} f&&/Apple Vision Pro/{match($0,/[0-9A-F-]{36}/);print substr($0,RSTART,RLENGTH);exit}')" build
# tvOS
xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
```

- Before merging to main, also do a Release build (`-configuration Release`). DEBUG-only members and missing `#if os(tvOS)` guards have broken Release before. Release destinations that work: generic iOS/visionOS **device** with `CODE_SIGNING_ALLOWED=NO`, macOS, tvOS. The iOS Simulator Release config fails in `DiceRollerWidgetExtension` (incompatible module target).
- Preview fixtures (`CoreRPG/Fake/*`, `*PreviewData.swift`, `*MockData.swift`) can't be `#if DEBUG`: ~760 `#Preview` blocks compile in Release and use them. Gating needs every `#Preview` wrapped first; ask before doing it. Production code must not use fixtures.

### Stale link / module errors
The project uses `EAGER_LINKING = YES`. After adding public API to a framework (e.g. CoreRPG), dependents can fail with `Undefined symbol: (extension in CoreRPG): …` although the symbol exists: the `EagerLinkingTBDs/…/<Framework>.tbd` stub is stale.
- Don't retry incremental builds and never delete files inside DerivedData. Run `xcodebuild -workspace MasterRPG.xcworkspace -scheme <scheme> -destination <dest> clean`, then build. The clean is per scheme and destination; tell the user their next Xcode build of other platforms may need Product > Clean Build Folder.
- Variant: a build/test reports success or old-signature errors while the edited module's Swift compile was skipped (only `ProcessInfoPlistFile` ran). Grep the build log for the edited file name; `touch` on the edited sources or `xcodebuild clean test …` fixes it.
- New files in a synced group are sometimes not seen by the first `BuildProject` ("Cannot find X in scope"): just build again.

## Simulators
Several runtimes are installed side by side (iOS 26.5/27.2, visionOS 26.5/27.2, tvOS 27.2), so a device **name** can resolve to a different simulator than the one the app was installed on. Check with `xcrun simctl list devices available`.
- Use the **newest runtime** (27.x). Pin with `id=<UDID>` whenever the name exists on more than one runtime (e.g. `Apple Vision Pro`). A name-based destination installs/launches on one device and tests on another: `Simulator device failed to launch de.AndreTrettin.GameMaster ... NotFound ("Launch Transaction error")`.
- iOS/iPadOS: `iPhone 18 Pro` (unique, fine by name). tvOS: `Apple TV 4K (3rd generation)`. visionOS: `Apple Vision Pro` on the visionOS 27.2 runtime, by id.
- The generic `platform=visionOS Simulator` / `generic/platform=visionOS Simulator` destination can fail with a stale `EagerLinkingTBDs` x86_64 linker error; use the concrete simulator.

## Tests
```bash
# All tests (iOS)
xcodebuild test -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
# One suite / one test
xcodebuild test -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:GameRPGTests/GameTablePinPawnTests
```

- Filters need the exact identifier with the `()` suffix: `-only-testing:Target/Suite/testName()`. 0 tests run = filter error, not a pass.
- After targeted fixes, run the full suite of the affected target before reporting success. Unit plan: `-testPlan MasterRPG`; also `MasterThreadSanitizer` and `MasterRPGAndSnapshot`.
- The Xcode MCP `RunSomeTests` can report "not run" (cached test list, wrong simulator, empty result bundle); fall back to `xcodebuild` and read its `✔`/`✘` lines. The MCP's active scheme/destination may be whatever the user last used (MasterMac, a physical iPad): switch with `XcodeSwitchScheme` (MasterRPG) and `XcodeSwitchRunDestination` ("iPhone 18 Pro") and check `GetBuildLog` before trusting results. A hung `RunSomeTests` task needs `TaskStop`.
- Snapshot failures: first check whether a recent change caused a real view regression. Re-record references only after confirming the new rendering is intended. Snapshots must be bundled into test targets for Xcode Cloud.
- Flaky tests: look for main-actor starvation, timing thresholds, machine-dependent paths and time-zone dependence.

### visionOS-only suites
Suites under `#if os(visionOS)` (e.g. `GameTablePinPawnTests`) need the visionOS simulator by id. The `MasterRPG` scheme's visionOS `build-for-testing` fails inside `swift-snapshot-testing` (`cannot find 'Image' in scope`). Workaround:
1. Copy `MasterRPG.xcodeproj/xcshareddata/xcschemes/GameRPGTests.xcscheme` to a temporary scheme and remove its `GameRPGSnapshotTests` `<TestableReference>`.
2. `xcodebuild build-for-testing`, then `test-without-building` with that scheme, `-destination 'platform=visionOS Simulator,id=<UDID>'` and `-only-testing:GameRPGTests/<Suite>`.
3. Delete the temporary scheme afterwards; never commit it.

## Runtime verification
- A successful build is NOT proof that a UI or interaction change works. For any UI, gesture, menu, focus, hover or keyboard-shortcut change: launch the app in the simulator with the Xcode MCP tools, exercise the change with `DeviceInteractionSynthesize`, take a screenshot, and only then report it done.
- If runtime verification is impossible (device-only, SharePlay, Vision Pro hardware), say so explicitly and list the exact manual steps the user should do to confirm.
- iOS/iPadOS: read `references/ios-simulator-interaction.md` first (session quirks, Synthesize command grammar, text entry, navigator log predicate, which simulators have data). Bundle id `de.AndreTrettin.GameMaster`, process name `MasterRPG`.
- visionOS/tvOS and RealityKit content: `RenderPreview` and device interaction don't work there; read `references/visionos-probe-app.md` (screenshots via `simctl`, swiftc probe apps, glass/material findings). Never touch a simulator the user already has booted.

## Xcode MCP
Prefer its tools when available: `BuildProject` / `GetBuildLog` / `XcodeListNavigatorIssues` for builds, `DocumentationSearch` to verify API availability, `RenderPreview` for SwiftUI previews, `ExecuteSnippet` to test code in a file's context.

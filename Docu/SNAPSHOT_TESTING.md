# SwiftUI snapshot tests

Snapshot tests use Point-Free's `SnapshotTesting` package and Swift Testing. Each suite is serialized because image rendering and reference-file recording share process-global resources.

All snapshot assertions apply `deterministicSnapshotEnvironment()` from `Tests/SnapshotTestSupport`. It fixes the locale, Gregorian calendar, UTC time zone, left-to-right layout, Dynamic Type size, light color scheme, and animation transaction independently of the developer machine or CI runner. Module-specific model and environment dependencies are installed before this shared modifier.

Every suite calls `assertRepositorySnapshot`. The shared wrapper passes an explicit `snapshotDirectory` to Point-Free's `verifySnapshot`, reports failures through Swift Testing, and stores references in the repository root:

```text
Snapshots/
├── Xcode26/<TestTarget>/<SnapshotSuite>/*.png
└── Xcode27/<TestTarget>/<SnapshotSuite>/*.png
```

SwiftUI pixels can differ between Xcode releases. The wrapper reads `DTXcode` from the loaded `.xctest` bundle and automatically selects the matching major-version tree. The test plan maps the runner's `SNAPSHOT_BASELINE_VARIANT_BUILD_SETTING` into the simulator test process when a temporary recording location is required; an ordinary verification leaves that value empty and therefore always exercises automatic `DTXcode` selection.

Most cases are generated directly from their view's same-file `#Preview`, keeping the preview and snapshot fixture identical. Regenerate committed cases after editing previews:

```bash
ruby Scripts/generate_snapshot_tests.rb
```

The generator's handled/skipped inventory is written to `Tests/SNAPSHOT_GENERATION_REPORT.md`. Previews with `@Previewable` local state use small hand-written snapshot cases instead.

## Run and record snapshots

Snapshot suites have their own `TestPlans/SnapshotTests.xctestplan`; ordinary unit and integration tests are not selected by it. Verification explicitly selects Point-Free's `never` record mode, so it cannot create or replace a reference:

```bash
./Scripts/run_snapshot_tests.sh verify 27
```

Record and immediately verify either tree, or both trees sequentially:

```bash
./Scripts/run_snapshot_tests.sh record 26
./Scripts/run_snapshot_tests.sh record 27
./Scripts/run_snapshot_tests.sh record both
```

The runner passes snapshot controls as Xcode build-setting arguments. The test plan expands them into `SNAPSHOT_RECORD_MODE` and `SNAPSHOT_BASELINE_VARIANT` inside the simulator test process. Do not rely on shell-prefixed variables for this purpose: `xcodebuild` does not forward arbitrary parent-process environment variables to simulator tests.

A recording is transactional:

1. Point-Free records into an empty `Snapshots/Xcode26Recording` or `Snapshots/Xcode27Recording` staging tree.
2. The runner requires at least one PNG and verifies the entire staged tree with record mode `never`. Starting from an empty tree also removes obsolete images and Finder metadata from the result.
3. The verified tree replaces `Snapshots/Xcode26` or `Snapshots/Xcode27`, while the previous tree is retained as a temporary backup.
4. A final read-only run removes the baseline override and proves that the test bundle's `DTXcode` selects the promoted tree automatically.

If recording, staged verification, promotion, or final verification fails or is interrupted, the previous canonical tree is restored. Point-Free reports intentionally recorded cases as failures, so a nonzero recording pass is expected; both subsequent verification passes must succeed.

CI should call `verify`, which prevents writes and fails when a reference is absent:

```bash
./Scripts/run_snapshot_tests.sh verify both
```

Use an iPhone 17 Pro running iOS 26.5 when Xcode 26 is selected, and an iPhone 17 Pro running iOS 27.0 when Xcode 27 is selected. Record each reference tree with its matching developer tools and simulator runtime. Never copy one version's images into the other version's folder.

The defaults use `/Applications/Xcode-26.6.0.app` and `/Applications/Xcode-27.0.0-Beta.3.app`. Override them with `XCODE26_APP` or `XCODE27_APP`. Override a destination with `SNAPSHOT_DESTINATION_26` or `SNAPSHOT_DESTINATION_27`.

Default DerivedData is created below `TMPDIR` and deleted after each toolchain finishes, so `both` never retains two multi-gigabyte build caches in the repository. Set `SNAPSHOT_DERIVED_DATA_26` or `SNAPSHOT_DERIVED_DATA_27` to opt into a persistent caller-owned cache; explicit override paths are never deleted by the script.

## View coverage

Production views are exercised from explicit snapshot roots. These markers are the source-controlled coverage registry. Add one directly above every test that renders a new root view:

```swift
// snapshot-root: AdventureRPG::AdventureRootView
@Test("Adventure root")
func adventureRoot() async throws { /* ... */ }
```

`Scripts/verify_snapshot_view_coverage.rb` follows concrete child-view construction from those roots and enforces all of the following:

- one concrete SwiftUI `View` per source file;
- a same-file `#Preview` that directly constructs that view;
- every registered root is attached to a Swift Testing `@Test` with a Point-Free snapshot assertion;
- every snapshot assertion uses the shared deterministic environment and a serialized `.snapshots` suite;
- every assertion resolves through `assertRepositorySnapshot` rather than an adjacent `Tests/**/__Snapshots__` directory;
- both toolchain roots exist and each Xcode 27 suite has a migrated reference directory;
- at least 80% declaration-level snapshot coverage across eligible views.

Run the structural audit with:

```bash
ruby Scripts/verify_snapshot_view_coverage.rb
```

Xcode code coverage remains enabled in `TestPlans/MasterRPG.xctestplan`; declaration coverage complements rather than replaces executable line coverage. Physical-device-only views may be listed in `Scripts/snapshot_view_exclusions.txt` with a specific reason.

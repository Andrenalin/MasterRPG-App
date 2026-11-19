# SwiftUI snapshot tests

Snapshot tests use Point-Free's `SnapshotTesting` package and Swift Testing. Each suite is serialized because image rendering and reference-file recording share process-global resources.

All snapshot assertions apply `deterministicSnapshotEnvironment()` from `Tests/SnapshotTestSupport`. It fixes the locale, Gregorian calendar, UTC time zone, left-to-right layout, Dynamic Type size, light color scheme, and animation transaction independently of the developer machine or CI runner. Module-specific model and environment dependencies are installed before this shared modifier.

Every suite calls `assertRepositorySnapshot`. The shared wrapper passes an explicit `snapshotDirectory` to Point-Free's `verifySnapshot`, reports failures through Swift Testing, and stores references in the repository root:

```text
Snapshots/
└── Xcode27/<SnapshotTestTarget>/<SnapshotSuite>/*.png
```

SwiftUI pixels can differ between Xcode releases. The wrapper reads `DTXcode` from the loaded `.xctest` bundle and automatically selects the matching major-version tree. The command-line runner forwards recording overrides with Xcode's `TEST_RUNNER_` environment convention; the shared test plans contain no snapshot-specific environment configuration.

Every framework has separate `<Module>Tests` and `<Module>SnapshotTests` targets. Source-directory ownership performs the split, so unit plans cannot discover snapshot suites accidentally.

Most cases are generated directly from their view's same-file `#Preview`, keeping the preview and snapshot fixture identical. Regenerate committed cases after editing previews:

```bash
ruby Scripts/generate_snapshot_tests.rb
```

The generator's handled/skipped inventory is written to `Docu/SNAPSHOT_GENERATION_REPORT.md`. Previews with `@Previewable` local state use small hand-written snapshot cases instead.

## Run and record snapshots

Snapshot suites have their own `TestPlans/MasterSnapshot.xctestplan`; ordinary unit and integration tests are not selected by it. `MasterRPG.xctestplan` contains unit targets only, while `MasterAll.xctestplan` contains both target sets. Verification explicitly selects Point-Free's `never` record mode, so it cannot create or replace a reference:

```bash
./Scripts/run_snapshot_tests.sh verify 27
```

Record and immediately verify the supported Xcode 27 tree:

```bash
./Scripts/run_snapshot_tests.sh record 27
```

The runner passes `TEST_RUNNER_SNAPSHOT_RECORD_MODE` and `TEST_RUNNER_SNAPSHOT_BASELINE_VARIANT`; Xcode exposes them to the test process as `SNAPSHOT_RECORD_MODE` and `SNAPSHOT_BASELINE_VARIANT`.

A recording is transactional:

1. Point-Free records into an empty `Snapshots/Xcode27Recording` staging tree.
2. The runner requires at least one PNG and verifies the entire staged tree with record mode `never`. Starting from an empty tree also removes obsolete images and Finder metadata from the result.
3. The verified tree replaces `Snapshots/Xcode27`, while the previous tree is retained as a temporary backup.
4. A final read-only run removes the baseline override and proves that the test bundle's `DTXcode` selects the promoted tree automatically.

If recording, staged verification, promotion, or final verification fails or is interrupted, the previous canonical tree is restored. Point-Free reports intentionally recorded cases as failures, so a nonzero recording pass is expected; both subsequent verification passes must succeed.

Xcode 27 CI should call `verify`, which prevents writes and fails when a reference is absent:

```bash
./Scripts/run_snapshot_tests.sh verify 27
```

Use an iPhone 18 Pro running iOS 27.0. Xcode 27 is the only supported snapshot toolchain; a test bundle built with another Xcode major version looks for its own `Snapshots/Xcode<major>` tree and fails because no reference exists.

The default uses `/Applications/Xcode27-RC.app`. Override it with `XCODE27_APP`, or override the destination with `SNAPSHOT_DESTINATION_27`.

Default DerivedData is created below `TMPDIR` and deleted after the run. Set `SNAPSHOT_DERIVED_DATA_27` to opt into a persistent caller-owned cache; an explicit override path is never deleted by the script.

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
- the Xcode 27 toolchain root exists and each suite has a reference directory in it;
- at least 80% declaration-level snapshot coverage across eligible views.

Run the structural audit with:

```bash
ruby Scripts/verify_snapshot_view_coverage.rb
```

Xcode code coverage remains enabled in `TestPlans/MasterRPG.xctestplan` and `TestPlans/MasterAll.xctestplan`; declaration coverage complements rather than replaces executable line coverage. Physical-device-only views may be listed in `Scripts/snapshot_view_exclusions.txt` with a specific reason.

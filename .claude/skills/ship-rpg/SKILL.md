---
name: ship-rpg
description: Ship MasterRPG — commit on develop, clean build and fix warnings, run the MasterRPGAndSnapshot, MasterThreadSanitizer and MasterAppIntents test plans, Release-build all platforms, push develop, fast-forward main, push main
disable-model-invocation: true
---

Build commands, simulator ids and stale-link recovery are in the `build-verify` skill. Use the `iPhone 18 Pro` simulator (iOS 27) for tests.

1. **Commit.** Run `git status` and split uncommitted changes into logical commits on `develop`.
   - Message style: lowercase prefix `added:` / `changed:` / `fixed:` and a short sentence (e.g. `fixed: thumbnail cache has only cost not count`).
   - Ask before committing changes you didn't make in this session (e.g. modified `Snapshots/` references or files from another session); leave them out unless the user says otherwise.
2. **Clean build, fix all errors and warnings.** Clean build (`clean build`) the Debug configuration for iOS, macOS, visionOS and tvOS. Fix every error and every warning in our code. Report warnings from third-party packages instead of editing them.
3. **Build for testing, fix all errors and warnings.** Run `xcodebuild build-for-testing -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro'` and fix every error and warning in our code and tests.
4. **Run the test plans**, one `xcodebuild test-without-building` per plan, with `-testPlan MasterRPGAndSnapshot`, then `MasterThreadSanitizer`, then `MasterAppIntents`.
   - Fix real failures. Check the "Known failing tests" memory first: re-run a known flaky or pre-existing failure once on its own, and report it instead of fixing it if it is unrelated to the changes being shipped.
   - Snapshot failures: first check whether a change caused a real view regression. Re-record references only after confirming the new rendering is intended. If `Snapshots/Xcode27` is missing, report that the snapshot plan cannot verify anything.
   - Stop before pushing if any real failure is left.
5. **Commit the fixes** from steps 2-4 as their own logical commits (same message style).
6. **Release build** for every platform. Stop if any build fails.
   ```bash
   xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -configuration Release -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterMac -configuration Release -destination 'platform=macOS' build
   xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterTV -configuration Release -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build
   ```
   Don't use simulator destinations here: the iOS Simulator Release config fails in `DiceRollerWidgetExtension`, and the generic visionOS Simulator fails linking x86_64.
7. Run `git push origin develop`.
8. Run `git checkout main && git merge --ff-only develop && git push origin main && git checkout develop`. If the fast-forward fails, stop and report; never merge or rebase main another way.
9. **Report** the number of commits shipped, the test results per plan (passed / failed / skipped, known failures), and any remaining warnings.

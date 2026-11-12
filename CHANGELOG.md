# Change Log

## 3.1 (build 631) — changes since 3.0.1

123 commits, from tag `3.0.1` to `d8d524b66`.

### New features
- **Players and characters**
  - Full player feature for games.
  - Character and player management.
  - Player pin control.
  - Players' companions use the same manager as the master.
  - "Move into character".
  - Characters can be added and selected in the Map Editor.
- **Maps**
  - Photo on map.
  - New resize-map dialog.
  - Clear map button.
  - Generate a map during the game.
  - Map editing with Apple Pencil.
  - Map state-change dialogs and tips.
  - New photo popover.
- **Sync and platforms**
  - New iCloud sync feature.
  - External player screen on macOS.
  - 3D inline viewer and capture mode fixes.
- **Quick tools**
  - Quick Dice overlay, with a new location, buttons and a more readable colour scheme. The tvOS overlay was removed.
  - QuickLinker is back, and multiple copies of the same link in the quick editor are fixed.
- **AI**
  - Photo description and tagging with Foundation Models.
  - PDF/photo tagging evaluation tests.
- **Diagnostics**
  - Download-speed logs for players.
- **Intents and tests**
  - App Intent tests.

### visionOS and 3D
- The game master's dice work on the visionOS table.
- Fixes for window and table position, and for game options.
- Fixed the dice line view.
- Several smaller visionOS improvements.
- A 3D weather feature was added, then turned off again.

### Fixes
- **Battle rounds**
  - Opponents now join in 2D and 3D in all rounds.
  - Fixed battle-round start with opponents.
- **Maps and pins**
  - Pin location on the first shown map.
  - Audio repeat play.
  - Game map data was being deleted.
  - The map editor without an image is now disabled.
- **Characters**
  - Repair of old or broken character data.
  - Character sheet issues with old data.
  - Character-selection folder appearance.
  - Link generation for one character link per room.
- **Folders and imports**
  - Double or empty folders from game imports.
  - Duplicate items in folders with the same item id.
  - Folder and item delete now prunes folders.
  - Search and refresh after a move.
  - URL display.
- **UI**
  - Flicker in the entry editor and on selection, and state restoration.
  - iPhone drop.
  - iPad keyboard and resizing.
  - Search field sync between Inspector and Link window.
  - Port selection view layout.
  - Mac audio-player menu.
- **Platform**
  - TV game statistics and Game Center.
  - NSUserActivity error.
  - Core Spotlight indexer no longer throws errors.
  - Proxy and observer no longer count as game statistics.
  - Chart errors.
- Weather fixes.

### Audits and hardening
Most of the remaining commits apply findings from code audits. The audit numbers are as named in the commit messages.
- **App Intents** (audits 1–3): many fixes and additions, plus performance work.
- **Audits 22, 23 and 24**: concurrency, performance and cleanup.
- **Game / SharePlay audit**
  - Drain-queue cancel.
  - Journal hangs.
  - Concurrency issues.
  - Size limits.
  - Message handling (§3–§9).
- **Game, Photo and Audio audit**: §3, §5, §7 and §9 fixed. §7.3 is marked won't-fix.
- **Audio2 audit**: first bug fixes.
- Several SharePlay concurrency and loading fixes.

### Build, test and housekeeping
- Version bumped to 3.1 (build 631).
- Compiler switches removed; Xcode 27 is now the default.
- Fixes for unit-test flakiness, data races, CI test runs, warnings and a bundle-loader issue.
- Profile no longer takes arguments for debugging.
- Skills updated.

Audit of Modules/GameRPG/{Controller,Model,Master,Player}, about 9.9k LOC in 100 files. Read whole: every MasterController and PlayerController file, MasterControllerModel, PlayerControllerModel, PendingMapUpdateQueue, FileBackedModuleAccess, CharacterRejectionPolicy, LogGameController, GameMessagePipeline, GameNetworkModel(+Shape), ListSequenceTracker, MasterSequenceGate, SharedWorkCoalescer, MasterPackageCache, MapPhotoPresentation, GameLimits, LogGameModel, TablePlayersModel, MasterNetworkController (+Listener, +Browser), PlayerNetworkController, HostingSessionStore. Not opened: GameConfigModel, GameVersionMismatch, TableWeather, RPGMessageType, Localization+Extensions, PlayerNetworkController+Browser/+Listener, MasterNetworkModel, PlayerNetworkModel, PlayerBrowserModel. Overall health is very good: the pipeline-owned drain worker, ticket waits and generation handling, the pending-audio-play state machine, the map content/state ordering and the master-side sender checks all hold up against the await-gap and reordering scenarios I traced. Nothing reaches Critical or High. The remaining findings are one design gap (hidden players still receive content), one real bug at a module boundary (dice reset by display name), and a set of Low items. All were checked against the cited lines; where something could not be traced end to end it says so.

### Per-player "show" toggle is enforced only on the receiving device
- Category: Security
- Location: Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:142-183; Modules/GameRPG/Controller/MasterController+Show.swift:140-150; Modules/GameRPG/Network/GameNetworkController+Delivery.swift:38-72
- What: The game master's sharing control (`controls[].show == false`) is checked only in the player's `applyPlayerGates`. The master builds `playersMissing` from `gameRoster.players` (not `controls`), `sendPresentation` sends the package to every missing connection, and `sendPlayer(data:)` broadcasts references and map state to everyone.
- Why: A player the GM has hidden still receives the bytes of every photo, PDF, 3D object, audio track and map (over the LAN socket or the SharePlay Journal); only an unmodified client refuses to apply them. Under the "players are trusted" policy this is tolerable, but the UI promises that the player is not shown the item, the data is on the device and in the Journal, and nothing in CODE_AUDIT_*.md or GAME_CONNECTIONS.md records the toggle as a client-side display gate.
- Action: Either leave hidden players out of `playersMissing` and of targeted/Journal sends (and deliver the pending content when they are switched on), or state in GAME_CONNECTIONS.md that the toggle is a display gate only.
- Severity: Medium
- Status: NEW

### Player-dice reset keys on display names and breaks with two players of the same name
- Category: Bug
- Location: Modules/DiceRPG/Controller/GameController.swift:290-301 (callee); Modules/GameRPG/Controller/MasterController+Control.swift:83-88 and Modules/GameRPG/Controller/PlayerController+Control.swift:86-87 (callers)
- What: `resetPlayerDice(to:)` does `names.compactMap { name in playerDice.first { $0.name == name } }`. `addGameDiceResult` deliberately keeps one die set per sender id so two players with the same name keep their own dice, but the next `resetPlayers()` (every roster change on the master; every master broadcast that is applied on a player) maps both "Alex" entries to the first die found.
- Why: With players A and B both named "Alex" the list becomes [dieB, dieB]: A's die is lost, B's appears twice with the same id (duplicate `ForEach` identity in `DicePlayer`), and `playerSupporterTiers`/`playerDiceSenders` are pruned for A's die. The callers also disagree on the list: the master excludes observers, the player passes every `controls` name (observers and hidden players included, plus the master's name), so the two devices prune differently.
- Action: Reset by sender id (`playerDiceSenders`) instead of by name, using the roster ids; make master and player build the same list. Add a test with two same-named players (`GameControllerTests` only covers distinct names).
- Severity: Medium
- Status: NEW

### A joining player's audio list delivers the pending track inside the serial master pipeline
- Category: Performance
- Location: Modules/GameRPG/Controller/MasterController+AudioMessages.swift:70-83 (also :289-310 `handleAudioDeliveryFailure`, :398-405 `showAudioStartItems`)
- What: The `.audioList` branch awaits `deliverPendingAudio(pending, to: [sender])`, which exports the track (`audioPackage`) and hands it to the transport, while still inside `process(_:)` of the pipeline's single worker. `startAudioDelivery` (:222) was added precisely so the delivery does not run in the master's action chain, but this path and the failure-retry path bypass it.
- Why: While the first export of a large track runs, every other player's receipts, asset requests and pin moves queue behind it (the queue holds 128 messages / 300 MB and then drops). It happens once per track version because the package is cached, but it lands exactly at join time, when the burst of lists and Character announcements arrives.
- Action: Route these two call sites through `startAudioDelivery`-style detached delivery (keeping the supersession checks), or at least do not await the export inside the handler.
- Severity: Medium
- Status: NEW

### Asset request for an arbitrary map id is answered and marks that map as unshared
- Category: Bug
- Location: Modules/GameRPG/Controller/MasterController+MapMessages.swift:44-65, 162-166; Modules/GameRPG/Controller/MasterController+Show.swift:83-117
- What: `handleMap` serves a player's map request for `model.data.id` without checking it is the map on screen. While "Share Map" is paused, `mayShareMapState(for:)` inserts whatever id was asked into `mapsWithUnsharedStructure`, and with sharing on `sendMapFollowUps` builds content and state for that id.
- Why: A stale request (an old map shown earlier, a pin link) grows `mapsWithUnsharedStructure` with maps that are not current, so a later resume/"Refresh Shared Map" may push structure for maps that are not on screen. This is bounded by the ids a player knows, so it is not a leak of unknown maps.
- Action: Compare the requested id with `mapRoot.gameControllable.gameModel.currentItemId` before calling `mayShareMapState` and `sendMapFollowUps`.
- Severity: Low
- Status: NEW (unverified end to end: the Map module's `networkMapUpdate` for a non-current map was not read)

### Informational notes are wiped by the first message the master sends
- Category: Bug
- Location: Modules/GameRPG/Controller/LogGameController.swift:98-102, 143-164, 257-265; Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:273-275
- What: `addNote` stamps a note with `currentSessionID ?? legacySessionID`. When the log holds no message row yet (`incompatibleVersion` fires at join, before any send), the note gets the legacy session id; the next `addMessage` calls `beginDeliverySession(real)`, sees `currentSessionID` (legacy) != real and runs `logs.removeAll()`.
- Why: The "update the app" notice shown to the game master disappears as soon as the master shows anything.
- Action: Let `beginDeliverySession` keep rows whose session is the legacy one (or store the master's session id for notes), and add a test.
- Severity: Low
- Status: NEW

### Late-join audio bookkeeping not cleared when a player disconnects
- Category: Bug
- Location: Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:135-149; Modules/GameRPG/Controller/MasterController+ProxyDelegate.swift:11-16; Modules/GameRPG/Controller/MasterController.swift:71
- What: `lostPlayer`/`lostProxy` call `gameModel.forget(playerId:)` but never remove the id from the controller property `lateAudioPlayers`.
- Why: The set is cleared only by the next play or pause. If the same participant id returns (SharePlay keeps it), `joinRunningAudioPlay` sends the running play to it before its role and route are rebound.
- Action: Remove the id from `lateAudioPlayers` in both paths.
- Severity: Low
- Status: NEW

### `process(_:)` checks the sender's route once, then awaits
- Category: Bug
- Location: Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:189-257; Modules/GameRPG/Controller/MasterController+ValueMessages.swift:54-101
- What: `isBound` is evaluated at the top; the roster add, `resetPlayers()` and the handler then suspend. `lostPlayer` is not serialised with the pipeline, so it can remove the route, roster entry and ownership binding in between; the handler then goes on to `bindCharacterOwnership`, `importPeerCharacter` and `setPlayerPin` for a player that has left.
- Why: The departed player's pin and Character binding stay until the next roster change (`lostPlayer` already ran its `resetPlayers()`). Narrow window, self-heals; not traced to a visible failure.
- Action: Re-check the route before the pin/binding side effects in `handleValue`, or run `lostPlayer`'s cleanup through the same pipeline.
- Severity: Low
- Status: NEW (unverified end to end)

### `stop()` cancels only the newest `resetPlayers` task
- Category: Concurrency
- Location: Modules/GameRPG/Controller/MasterController+Control.swift:31-35, 58-67
- What: `resetPlayers()` chains each task behind `previous`. `stop()` cancels only `resetPlayersTask`, the last one. Earlier queued tasks are not cancelled; they pass `guard !Task.isCancelled` and run `performResetPlayers` after the game has been stopped.
- Why: After `stop()` has emptied the roster and stopped the stores, a still-queued reset can recompute pins and `send` map state to a stopped transport. Harmless today; it will bite if `performResetPlayers` ever gains a side effect.
- Action: Keep a generation counter (or cancel the whole chain) so every queued reset checks it.
- Severity: Low
- Status: NEW

### Every player's audio and file list triggers a broadcast of all lists
- Category: Performance
- Location: Modules/GameRPG/Controller/MasterController+AudioMessages.swift:70-73, 113-117; Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:76-79
- What: Each accepted report list from any player makes the master send the authoritative list for all players to everyone.
- Why: N players joining produce about 4N broadcasts of an N-player list (audio, photo, pdf, space), each also taking a pipeline slot of the receivers.
- Action: Coalesce per module with one pending broadcast task.
- Severity: Low
- Status: NEW

### "Unknown Player" is a hard-coded English string in the delivery log
- Category: API
- Location: Modules/GameRPG/Controller/LogGameController.swift:254
- What: `namesById[$0] ?? "Unknown Player"` is shown in the log rows, not localized (CLAUDE.md: module strings use `bundle: .module`).
- Why: German UI shows an English fallback; the neighbouring `noPlayersText` is localized.
- Action: Use a localized string with `bundle: .module`.
- Severity: Low
- Status: NEW

### Test-only and flag-disabled code kept in production
- Category: Dead code
- Location: Modules/GameRPG/Controller/LogGameController.swift:83-92 (`addMessage(counter:...)`, only tests call it); Modules/GameRPG/Model/GameMessagePipeline.swift:327-330 (`hasQueuedMessages`, only tests); Modules/GameRPG/Controller/MasterController+TableWeather.swift:16-69, Modules/GameRPG/Controller/PlayerController+TableWeather.swift, Modules/GameRPG/Model/TableWeather.swift (all behind `isTableWeatherEnabled = false`; three tests are disabled by it)
- What: A legacy overload and a query used by tests only, and a complete table-weather send/replay/receive path that cannot run.
- Why: Maintenance weight; the receiving side still accepts the message from any master, so the path is half live.
- Action: Move the test-only members under `#if DEBUG` (as the neighbours are) and either delete the table-weather path or document the flag in GAME_CONNECTIONS.md with a removal date.
- Severity: Low
- Status: NEW

Not audited in this area: Modules/GameRPG/Network (transport, routes, throttles), SharePlay, Root, BattleRound, Table3D and the views (other areas); the module-side controllables the controllers call (MapRPG `networkMapUpdate`/`createMapGameData`, DiceRPG) were read only where a finding needed them; the files listed as not opened in the first paragraph.

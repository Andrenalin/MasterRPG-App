# Game Connection And Communication Documentation

Implementation audit: 2026-07-15.

This document describes how the game communication layer works in MasterRPG:
participants, transports, counters, roster/control state, message types, replies,
and module-specific behavior for audio, photo, dice, map, PDF, table, character,
weather, space, and screen updates.

For broader controller responsibilities, import/export controllers, and how
`GameRoot`, `MasterController`, `PlayerController`, and module `GameController`
fit into the root graph, see [Controllers](CONTROLLERS.md).
For the completed redesign record and remaining compatibility/transport work,
see [Game Communication Redesign](GAME_COMMUNICATION_PLAN.md).

Primary source files:

- `Modules/GameRPG/Root/GameRootModel.swift`
- `Modules/GameRPG/Controller/MasterController.swift`
- `Modules/GameRPG/Controller/PlayerController.swift`
- `Modules/GameRPG/Network/GameNetworkController.swift`
- `Modules/GameRPG/Network/ConnectionController.swift`
- `Modules/GameRPG/Model/GameNetworkModel.swift`
- `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`
- `Modules/CoreRPG/Controllable/GameControllable.swift`
- `Modules/CoreRPG/Model/NetworkCodableDataType.swift`
- `Modules/CoreRPG/Model/RPGMessageActionType.swift`
- `Modules/GameRPG/Model/RPGMessageType.swift`
- Module game controllers under `Modules/*RPG/Controller/GameController.swift`

Behavioral coverage is concentrated in:

- `Tests/GameRPGTests/GameNetworkModelVersionTests.swift`
- `Tests/GameRPGTests/GameMessageCorrectnessRegressionTests.swift`
- `Tests/GameRPGTests/SharePlayPackageTransportTests.swift`
- `Tests/GameRPGTests/MasterPlayerControllerTests.swift`
- `Tests/GameRPGTests/MultiConnectionTests.swift`
- `Tests/GameRPGTests/AudioMessageFlowTests.swift`

## 1. Mental Model

The game is a master-authoritative session.

The master owns the canonical game state:

- game identity and selected adventure
- roster of connected participants
- sharing controls per player
- feature gates such as dice/audio/photo/space sharing
- current shared content such as revealed maps, photos, audio, weather, etc.

Players and observers receive master broadcasts and respond with ACK/failure or
requests for missing payload data. Players can also send selected live updates
back to the master, for example dice rolls, character/player data, audio lists,
map pin movement, and space transforms.

Every game message uses the same current in-memory envelope:

```swift
GameNetworkModel(
    version: Int,
    counter: Int,
    proxyCounter: Int,
    type: RPGMessageType,
    subType: RPGMessageActionType,
    masterId: UUID,
    sender: GameSenderModel,
    masterState: GameMasterStateModel?,
    targetId: UUID?,
    data: NetworkCodableDataType
)
```

Master messages carry `masterState`, the authoritative roster, controls,
features, and adventure state. Player messages carry only `sender` identity.
Legacy `gameConfig`/`gameRoster`/`gameControl` fields are still emitted as a
compatibility superset, but current code does not use them as the authority.

The payload in `data` is either:

- ID-only metadata: `id`, `type`, `version`, `data == nil`
- Full/importable payload: same metadata plus `data != nil`

The same message model is used over local network and SharePlay.

## 2. Participants

### Master

Created by `GameRoot.startMaster()`.

The master creates both controllers:

- `MasterController(root: asProxy: false)`
- `PlayerController(root: asGameMaster: true)`

The master therefore acts as:

- the authoritative server for remote players
- a local player/participant for the master's own UI
- a proxy server for proxy clients, through `networkProxyStore.startProxyServer()`

The master starts:

- local network listener for players
- SharePlay session when available
- proxy server listener

### Player

Created by `GameRoot.startGame(to: mode: .player)`.

A normal player creates:

- `PlayerController(root: asGameMaster: false)`
- an internal `MasterController(root: asProxy: true)` used as that player's local
  proxy server

When a player starts:

- it connects upstream to the real master through `networkStore`
- it also starts a local proxy server through `networkProxyStore`

This lets additional proxy clients connect to that player.

### Observer

Created with `mode: .observer`.

Observers:

- have no selected character
- can receive master content
- are filtered out of player pin setup
- do not send character data
- are ignored by master handlers for player-origin map/value/dice updates

### Proxy Client

Created with `mode: .proxy`.

A proxy client connects to a player's proxy server, not directly to the real
master. Its messages flow:

```text
Proxy client -> player's proxy master -> real master
Real master -> player -> player's proxy clients
```

The player hosting the proxy relays master broadcasts to its proxy clients from
`PlayerController.prepareForProcessing()` when the message was not already from
proxy.

### Demo

Demo mode uses a local `PlayerController` with `asGameMaster: true` and generates
synthetic reveal/update messages for photos, weather, and maps.

## 3. Transports

There are two `GameNetworkController` instances in `GameRoot`:

- `networkStore`: direct mode, `proxy == false`
- `networkProxyStore`: proxy relay mode, `proxy == true`

Direct mode:

- owns SharePlay
- fans out received local-network data to other peers
- can deliver to the local player when `hasLocalPlayer == true`

Proxy mode:

- has no SharePlay
- avoids fan-out inside `GameNetworkController` to prevent relay loops

### Local Network

Local network uses Bonjour, `NWListener`, `NWConnection`, TLS PSK, and a custom
`NWProtocolFramer`.

Bonjour service roles are defined in `GameServiceType`:

| Case | Advertised by | Browsed by | Service string |
| --- | --- | --- | --- |
| `.player` | Real master | Player/observer | `_gamemastermaster._tcp` |
| `.master` | Player fallback listener | Real master | `_gamemasterplayer._tcp` |
| `.proxyServer` | Proxy master/server | Proxy client | `_gamemasterproxyserver._tcp` |
| `.proxyClient` | Proxy client/fallback | Proxy server | `_gamemasterproxyclient._tcp` |

The naming is from the advertising side's counterpart perspective:
`.player` means "the service players browse", and is advertised by the master.

Connection security:

- shared passcode: `GameSecurity.passcode == "GameMasterCode"`
- TLS PSK derived with HMAC-SHA256 over `"GameMaster"`
- cipher suite: `TLS_PSK_WITH_AES_128_GCM_SHA256`
- TCP keepalive enabled
- peer-to-peer enabled

The passcode is a fixed application constant, not a user-specific pairing secret.
This provides transport encryption and app-protocol separation, but it is not
authorization against a client that knows or extracts the same constant.

Wire framing:

- `GameProtocolHeader.type`: `UInt32`
- `GameProtocolHeader.length`: `UInt32`
- `GameMessageType.gameData == 3`
- body: JSON-encoded `GameNetworkModel`

### SharePlay

SharePlay uses the same `GameNetworkModel`.

`GroupSessionMessenger` is the default path. The encoded envelope is split into
ordered `PackageMessage` chunks of 200,000 bytes, reassembled by package UUID and
sequence number, and throttled for 200 ms after every 60 packages.

`GroupSessionJournal` is used when all of these are true:

- the caller requested file-journal transport
- a journal exists for the configured session
- the payload contains bytes
- the message is untargeted, or the module is audio

Automatic file-journal payloads are reveal/store messages for PDF, audio, space,
photo, and map. A player audio upload (`.update/.generic`) also opts in, and a
caller can explicitly opt another full payload in (the selected-character upload
does this).

The journal stores the bytes as the attachment and a metadata-only
`GameNetworkModel`. There is one current journal publication slot per module.
Publications for the same module are serialized. A replacement is added and
committed before cleanup of the previous attachment starts; cleanup runs in a
separate session-scoped task, so a slow `remove(attachment:)` cannot block the
next map (or every later publication in that module). Attachment IDs are
processed once per snapshot lifetime. A snapshot can retain old presentation
slots from different modules; only its single newest map/photo/PDF/space reveal
is loaded, selected by message counter. File delivery is awaited rather than
launched as independent tasks, so an old payload or repair cannot race back over
the current presentation. Because Apple can expose attachment metadata while
its CloudAsset upload is still in progress, data loading uses bounded,
cancellation-aware retries. A final failure leaves the attachment retryable for
the next journal snapshot. Reveal metadata uses an exact-version local copy or
requests missing bytes through its normal handler; store/update failures issue an
explicit `.store/.store` messenger request so metadata-only handlers cannot ACK
or fail without recovering the bytes. A removed publication becomes publishable
again.

Messenger routing is awaited as well, preserving its sequence before the next
package is handled. Because messenger references and journal payloads can still
finish in either order, each player records one latest visual presentation
intent per master across map, photo, PDF, space, table, value, and weather. An
older payload for a different module/item is ignored; delayed bytes are accepted
only for the intended item and exact expected version (version zero is treated
as an unknown legacy expectation). Map-state snapshots carry the map's content
version so their targeted companion update remains compatible with the repaired
full payload; a targeted version-zero map-state from an older master is accepted
only for the already intended map. Targeted repairs, including mapState's
`.reveal/.store`, do not advance intent and are accepted only when they match it.
Intent state resets with the connection. Messenger and journal handlers verify
their session before delivery so cancellation cannot publish old-session data.

Targeted non-audio repair responses stay on the messenger so they do not replace
a broadcast attachment while another participant is downloading it. One narrow
exception is a full `.store/.store` photo repair: transport is chosen from the
original targeted message, then SharePlay clears `targetId` and coalesces the
photo ID/version. Every participant therefore imports one shared chunk stream
without changing its current presentation. Targeted audio repairs remain
journaled, but their metadata is converted to an untargeted `.store/.show`;
every participant stores the audio without treating the repair as a new
presentation.

If adding an attachment fails, the sender falls back to messenger packages. If
loading attachment bytes fails after metadata arrived, the metadata-only model
is still delivered so the normal missing-data request path can repair it.

Session lifecycle rules:

- the `RPGActivity.sessions()` task is subscribed before activation
- a session becomes configured only after `join()` was requested and state is
  `.joined`
- callbacks from a replaced session are ignored by session ID
- invalidation resets session-scoped tasks/state but leaves the join loop alive
  for automatic rejoin
- a configured/rejoined player immediately re-announces audio availability and
  its selected character

## 4. Game Start And Stop

### Master Start

`GameRoot.startMaster()`:

1. Requires `gameConfig.state == .stopped`.
2. Requires a selected adventure.
3. Creates a `MasterGameModel` with a new master id.
4. Writes `gameConfig.id = master.id` and `gameConfig.master = master`.
5. Sets the network names to the game master name.
6. Sets up SharePlay audio coordination.
7. Starts the adventure game state.
8. Creates the local player controller and real master controller.
9. Sets state to `.started`.
10. Starts network streaming and proxy streaming.
11. Focuses dice linked from the selected adventure.

### Player Start

`GameRoot.startGame(to: mode:)`:

1. Clears selected character for observer/proxy/demo.
2. Creates a `PlayerGameModel` with a new player id.
3. Puts that player in the local `gameRoster`.
4. Sets `gameConfig.id` to the player's id and state to `.prepare`.
5. Resets module game state.
6. Creates a `PlayerController`.
7. Connects to the selected browser model unless demo mode.
8. Calls `joinGame(for:)` after successful connect.

`joinGame(for:)`:

- sets state to `.started`
- ensures the local player is in the roster
- starts the adventure UI
- for non-observers, focuses the selected character and related dice

### Stop

`GameRoot.stopGame()`:

- cancels scheduled network/demo tasks
- sets state to `.stopped`
- resets `gameConfig`
- stops master and player controllers
- resets all adventure/module game state
- resets SharePlay state on visionOS

## 5. Message Envelope

### Wire-Format Versions

| Version | Layout | Sender |
| --- | --- | --- |
| 1 | `players`, `controls`, `features` inside `gameConfig`. No top-level roster/control. | Shipped 2.6 app (`GameNetworkModelV1`). |
| 1/2 (unreleased dev layouts) | Slim `gameConfig`; state in `gameRoster` [+ `gameControl`]. | Dev builds before the sender/masterState redesign. |
| 2 (current) | Explicit `sender` + master-only `masterState` + optional `targetId`. | Current builds. |

Compatibility rules:

- **Decode**: `GameNetworkModel.init(from:)` accepts all layouts. A message with
  a `sender` key is current; a pure V1 envelope (no `gameRoster`/`gameControl`
  keys) is decoded as `GameNetworkModelV1` and up-mapped via `v2Model`, keeping
  `version == 1` so the receiver can tell the peer is old; the unreleased dev
  layouts are derived via `legacyIdentity` (sender/masterState from
  config + roster).
- **Encode**: `encode(to:)` writes a compatibility superset. Besides
  `sender`/`masterState`, `gameConfig` is encoded through the down-mapper
  (`v1Model.gameConfig`) with players/controls/features embedded for V1 peers,
  plus `gameRoster`/`gameControl` for the dev layouts. Player messages embed the
  sender as the only roster entry so V1 peers can resolve the sender name. The
  encoded `version` is deliberately `1`; therefore decoding a message produced
  by the current encoder yields `version == 1` even though its current fields are
  present.
- Mappers exist in both directions: `GameNetworkModelV1.v2Model` and
  `GameNetworkModel.v1Model`.

Compatibility limit: shipped V1 clients do not have `targetId`. They ignore the
unknown JSON key and cannot apply logical recipient filtering. A repair sent to
one direct local-network connection remains physically targeted for every
version. A SharePlay or fallback broadcast carrying `targetId` is only targeted
for current peers; a V1 peer may still process it. SharePlay photo
`.store/.store` repairs intentionally clear the target so every version imports
the shared cache update.

### `GameNetworkModel`

| Field | Meaning |
| --- | --- |
| `version` | In-memory default/current schema is `2`; compatibility encoding writes wire version `1`. Up-mapped and round-tripped envelopes therefore commonly carry `1`. |
| `counter` | Sender-local monotonic message id, or the original master counter copied by a request/ACK. Used by ordering, logs, and deduplication. |
| `proxyCounter` | Reserved proxy-hop counter. Currently preserved, not incremented in traced code. |
| `type` | High-level message kind: reveal, store, update. |
| `subType` | Action/ack subtype: show, store, ok, failed, mapState, playAudio, etc. |
| `masterId` | The authoritative master's id, used to rebuild local master identity, sequence master-state snapshots, map legacy layouts, and include the master in audio availability. Sender role checks use `sender.isMaster`. |
| `sender` | `GameSenderModel`: id, role (`GameType`), name, characterId. The only identity a player ever sends. |
| `masterState` | `GameMasterStateModel`: state, adventureId/title, players, controls, features. **Only master messages carry it** — players structurally cannot change roster/controls. |
| `targetId` | When set, only the addressed participant processes the message (data-request responses, map-state recovery). |
| `data` | Module item id, module type, version, optional payload bytes. |

### Local `GameConfigModel`, `GameRosterModel`, And `GameControlModel`

These remain the `@MainActor` game-root state from which current messages are
built. They are not three current authoritative wire blocks.

`GameConfigModel` contains:

- `id`: local participant/master id for this game root
- `state`: `.stopped`, `.prepare`, `.started`
- `master`: `MasterGameModel`

`isMaster` is true when `gameConfig.id == gameConfig.master.id`.

`GameRosterModel` contains the current players:

```swift
[PlayerGameModel(id: UUID, type: GameType, name: String, characterId: UUID?)]
```

Player types:

- `.master`
- `.player`
- `.observer`
- `.proxy`
- `.demo`
- `.notSet`

`GameControlModel` contains:

- `controls: [SharingControlModel]`
- `features: GameFeatureModel`

`SharingControlModel`:

- `id`: player id
- `name`: player display name
- `show`: whether this player is allowed to see shared content

`GameFeatureModel`:

- `diceMaster`
- `dicePlayers`
- `audioSharing`
- `photoSharing`
- `spaceSharing`

Only dice feature gates are enforced directly in `PlayerController.handleDice()`
in the traced code. The other booleans are available to UI/feature logic.

### `NetworkCodableDataType`

Contains:

- `id`: item id or event id
- `type`: `NetworkModules`
- `version`: item version or `0` for event data
- `data`: optional binary payload

Important meanings:

- `data == nil`: "I am talking about this item/version."
- `data != nil`: "Here is importable data or event data."
- `version == 0`: usually live event/ack, or "any version" checks.
- `version == -1`: can happen when `createGameData` cannot find a local version.

## 6. Ordering, Counters, Deduplication, And Logs

### Master Counters

The master owns the canonical outgoing message counter.

`MasterControllerModel.nextMessageCounter()` returns the current value and then
increments it. The counter starts at `1`.

Every master `send(...)`:

1. reserves a counter
2. snapshots sender and authoritative master state in one `MainActor` hop
3. creates a `GameNetworkModel`
4. adds a log entry keyed by the counter
5. sends to direct peers or proxy peers

The first master message has counter `1` and is deduplicated normally.

### Player Counters

New player-origin messages reserve their own increasing, nonzero counter,
starting at `1`:

- `send(updated:)` -> `.store/.store`
- `game(message:actionType:)` -> `.update/<action>`
- character send -> `.update/.store`
- audio list -> `.update/.audioList`

Player replies copy the counter and proxyCounter from the message they are
answering. This lets the master's delivery log attach an ACK to the original row.
Replies strip payload bytes because a data request only needs the item identity;
the master rebuilds the full payload locally.

Player `messageCounter` remains a separate processed-message statistic. It is not
the outgoing counter.

Screen sends can pass an explicit `responseCounter`, used as the counter for the
`.store/.screen` message.

### Deduplication

`GameMessagePipeline` dedups by:

- sender id
- counter
- proxyCounter
- type
- subtype
- data id
- data type
- data version
- whether payload bytes are present

Deduplication is skipped when:

- `counter <= 0`
- subtype is `.ok`
- subtype is `.failed`

The recent dedup window keeps 256 keys.

The actor also tracks queued and currently processing keys. A key is remembered
only after successful processing; cancellation or failure releases it so a retry
can be accepted. Metadata-only journal delivery and a later full-payload delivery
have different keys and both can be processed.

Player ordering has an additional rule for authoritative master state. The last
applied master-state counter is tracked per `masterId`; an older master snapshot
cannot roll roster, controls, or features backward. Counter `0` remains accepted
for legacy/unsequenced input.

### Logs

`LogGameController` stores:

- outbound master message rows by counter
- ACK/reporting players for reveal messages
- player screen JPEG data
- SharePlay attachment metadata

Only `.reveal` messages are delivery-tracked as missing/partial/all players in
the log UI. Other message types are `notTracked`.

## 7. Message Types And Subtypes

### Top-Level Types

| Type | Meaning |
| --- | --- |
| `.reveal` | Show/share an item. Map/photo/PDF/space start with a full first-show package; later or other-module reveals can be ID-only and request full data. |
| `.store` | Transfer/import item data without necessarily presenting it. Used for background repair/sync. |
| `.update` | Live event, command, or small state update. |

### Action Subtypes

| Subtype | Meaning |
| --- | --- |
| `.generic` | Default live update. Used for dice roll results and generic module updates. |
| `.playAudio` | Audio play/pause request. |
| `.audioList` | Audio availability/report list. |
| `.mapState` | Live map room/pointer/pin state. |
| `.mapPin` | Player map pin/pointer movement sent to master. |
| `.photoSpace` | Photo space action hook. Currently no-op in `PhotoRPG` game controller. |
| `.valueResult` | Character/value result, often generated from table/dice output. |
| `.spaceTransform` | Live 3D object transform sync. |
| `.store` | Store/import subtype. |
| `.show` | Show/present subtype. |
| `.ok` | ACK/report success. |
| `.screen` | Player screen JPEG update. |
| `.failed` | Negative ACK. |

## 8. Authoritative State In Master Messages

Every **master-originated current message** carries a `GameMasterStateModel`:

- game state
- adventure id and title
- current players
- sharing controls
- feature gates

Player, observer, and proxy messages carry `masterState == nil`. This structural
boundary prevents a peer from overwriting authoritative state. Legacy fields may
still exist in encoded bytes for compatibility, but current routing trusts
`sender` and `masterState`.

### Master Broadcast Application

When a non-master player receives a message from the master, it applies the
master broadcast atomically:

```swift
root.gameModel.applyMasterBroadcast(
    masterId: model.masterId,
    masterName: model.sender.name,
    state: masterState
)
```

That updates:

- master identity
- sharing controls
- feature gates
- roster

It also preserves the local player in the roster if the master broadcast does
not contain it yet.

Master state is applied only when:

- `model.sender.isMaster`
- `masterState` is present
- its counter is newer than the last master-state counter for that `masterId`,
  unless the legacy counter is `0`

### Master Roster Updates From Player Messages

When the real master receives a player/observer message:

1. It updates the log row for the message counter.
2. It maps the physical connection id to the sender/player id.
3. It adds or updates the participant from `model.sender.playerModel`.
4. It adds or updates the sharing control by participant ID.
5. If the player is new, it resets player-dependent module state.

The proxy-host `MasterController(asProxy: true)` takes a different path: proxy
clients are private mirrors and are never added to the host or real-master
roster.

Player connection id mapping evicts stale mappings for reconnects, so a lost old
connection does not remove a player that already reconnected.

### Controls And Filtering On Players

Players process a master message only when one of these is true:

- local type is `.proxy`
- local type is `.observer`
- controls are empty
- a control exists where `control.id == localPlayerId && control.show == true`

After that, non-proxy players only accept:

- messages from the master
- dice messages from players
- `.spaceTransform` messages from players

This prevents ordinary player-origin fan-out messages from changing other player
state. The main exceptions are dice rolls and 3D transforms, which are intended
to be visible live.

`targetId` filtering happens first. Only the addressee processes a targeted
message. A host still forwards a message addressed to another participant to its
local proxy clients because the actual addressee may be behind that proxy server.
When the target is the host itself, the host clears `targetId` before forwarding,
so its private mirrors process the same repair.

## 9. General Request And Reply Patterns

### Pattern A: Master Reveals An Item, Everyone Already Has It

For map, photo, PDF, and space, the first show in a game exports and broadcasts
the full package immediately. Later shows of the same item are ID-only. Other
modules normally start with an ID-only reference.

```text
Master -> all:
  .reveal/.show
  data: full first-show payload, or an ID/version reference on a reshow

Each player:
  imports the payload or resolves the matching local item/file
  sets current/display state if needed

Each player -> master:
  same counter
  type .reveal
  subtype .ok
  data: same id/type, version 0, data nil

Master:
  records player report for that item
```

For audio, a reveal ACK also updates audio reporting. For map/photo/pdf/table/
weather/space/value it records that player as having the revealed item.

### Pattern B: Master Reveals An Item, One Player Does Not Have It

```text
Master -> all on a reshow or reference-based module:
  .reveal/.show, data nil

Player with item:
  -> .reveal/.ok

Player missing item:
  -> .reveal/.show, data nil

Master receives missing-data request:
  createGameData(for: itemId)
  -> requester only: .reveal/.show, targetId requester, exported payload

Player imports payload:
  -> .reveal/.ok
```

On a local direct connection, the master sends the repair only to that physical
connection. If no matching connection exists (for example the requester arrived
through SharePlay), it uses the normal fan-out transport with `targetId`; other
current player pipelines ignore it. A shipped V1 pipeline cannot enforce that
field. Targeted non-audio SharePlay repairs use messenger packages rather than
replacing the journal publication.

### Pattern C: Master Reveals An Item, Local File Is Missing

`GameControllable.reveal(...)` checks both:

- item/version exists
- backing file data exists, if the module has file-backed data

If metadata exists but the binary file is missing, a full payload is imported
when it arrives. This repairs cases where CloudKit/local metadata arrived but
the actual photo/audio/PDF/space file did not.

### Pattern D: Store/Repair Transfer

`.store/.store` is used when the sender wants the receiver to import an item
without necessarily showing it. Players use this for missing map-pin photos:

```text
Player detects a map pin photo ID that exists in neither the local
photo game controller nor the persistent photo item controller
Player -> master:
  .store/.store, data: photo id/type/version, data nil

Master:
  createGameData(for: photoId)
  -> direct connection: requester-only .store/.store photo payload
  -> SharePlay: one untargeted, coalesced .store/.store chunk stream per
     photo ID/version

SharePlay participants (or the direct requester):
  import hidden pin-photo data
  -> .store/.ok
```

`requestedRepairIds` permits one photo repair request per item per connection
lifetime and releases the ID only after a delivered repair verifies local bytes.
The initial scan is based on photo-model ownership; a separately unavailable
iCloud/local binary does not cause another map-pin SharePlay request. SharePlay's
session-scoped coalescer suppresses overlapping requests from other players and
resets when a participant joins, so a late joiner can request the same version.

The map background is never added to this repair list. It is embedded in the
full map package; the first SharePlay map show publishes that package through
the journal. If the background is unavailable after delivery, the player checks
it separately and may request the full map once.

### Pattern E: Live Update

Live updates use `.update/<specific subtype>`.

Examples:

- `.update/.playAudio`
- `.update/.audioList`
- `.update/.generic` for dice result
- `.update/.mapState`
- `.update/.mapPin`
- `.update/.valueResult`
- `.update/.spaceTransform`

Most live updates do not ACK. Reveal/store transfers generally ACK. An ACK or
request copies the original counter and never echoes the incoming payload bytes.

## 10. Transport Fan-Out Details

### Master Receives Direct Local-Network Data

In direct mode, `GameNetworkController.masterReceived(...)` does this before the
master controller handles the message:

1. decode `GameNetworkModel`
2. send the same model to all other local-network peers except the sender
3. send the same model through SharePlay
4. call `MasterController.received(...)`

This means player-origin messages can be seen by other peers immediately.
However, `PlayerController.prepareForProcessing()` filters most player-origin
messages unless they are dice or space transforms.

### Master Sends Data

`MasterController.send(...)` sends:

- via `networkStore.sendPlayer(data:fileJournal:)` for real master
- via `networkProxyStore.sendPlayer(...)` for proxy master

Real-master broadcast sends derive `fileJournal` from the envelope: only
file-backed `.reveal`/`.store` payloads with bytes opt in automatically. A
targeted local-network response first tries `sendResponse(..., id:)`; on failure
it falls back to normal transport fan-out while `targetId` preserves logical
addressing. At the SharePlay boundary, a full photo `.store/.store` repair is the
exception: it becomes one untargeted, coalesced group store.

The real master also has a local `PlayerController(asGameMaster: true)`.
That controller calls `networkStore.setupLocal()`, which marks the direct
network controller as having a local player. When the master sends a broadcast,
`GameNetworkController.sendPlayer(...)` also delivers the model to the local
player delegate, so the master's own UI processes the same reveal/update path as
remote players. A successfully delivered targeted response also reaches the
local player pipeline, which applies the same `targetId` filter. Direct
`sendMaster(...)` returns early when a local player is registered, avoiding a
local upstream loop.

### Player Sends Data

`PlayerController.sendOriginating(...)`:

- if local game type is `.proxy`, sends upstream through `networkProxyStore`
- otherwise sends upstream through `networkStore`
- also forwards to local proxy clients through `networkProxyStore.sendPlayer`

Player messages request SharePlay journal automatically for file-backed
`.reveal`/`.store` payloads (PDF, audio, space, photo, map) and full
`.update/.generic` audio uploads. `useJournal == true` can opt in another full
payload, as used by selected-character upload. The SharePlay controller still
applies its own journal-availability and targeting rules.

### Player Receives Master Data

When a player receives a direct, non-proxy message:

- it may apply master broadcast state
- it forwards the same message to its local proxy clients
- it schedules selected-character sync
- it handles the module message
- it sends a response when the handler returns one

When a player receives from proxy, it does not forward the message again to
proxy clients.

### Concurrency And Task Ownership

The project builds in Swift 6 mode with complete strict-concurrency checking and
no configured default actor isolation. The communication layer therefore uses
explicit boundaries:

- `GameRoot`, `GameRootModel`, controller models, browser/listener UI models,
  and `RPGSharePlayController` are `@MainActor`
- `ConnectionController` is an actor around one `NWConnection` and its receive
  loop
- `GameMessagePipeline` is an actor that serializes module processing and owns
  deduplication state
- master/player delegate boxes are actors holding weak delegate references
- browser and listener worker actors bridge Network callbacks through
  `AsyncStream`
- local-network fan-out uses a discarding task group so independent peer sends
  run concurrently

Long-lived unstructured tasks are generally stored by their controller/model and
cancelled on stop, reset, replacement, or disconnection. Short callback-hop tasks
are not retained. The SharePlay join sequence is intentionally long-lived across
session resets and is cancelled only when the game stops. Group-session `join()`
is the narrow detached operation because the framework call can block the main
thread while audio is active; it captures only the selected session for the
one-shot `join()` call, while controller state remains on the main actor.

`GroupActivities` is currently imported with `@preconcurrency`. The safety
invariant is that messenger, journal, lifecycle, task registries, and all other
mutable SharePlay controller state stay on `@MainActor`; the detached join call
does not access that controller state. Re-evaluate this escape hatch when the SDK
annotations used by the deployment toolchain no longer require it.

## 11. Proxy Topology

In a session with 1 master, 4 players, 2 observers, and 2 proxies on 2 different
players, the topology is:

```text
                 SharePlay/local direct
                         |
                      Master
        /          /      |      \          \
   Player A   Player B  Player C Player D  Observers
      |          |
 Proxy A1    Proxy B1
```

Each normal player can host one proxy server through its `networkProxyStore`.
Proxy clients discover `_gamemasterproxyserver._tcp` and connect to the selected
player's proxy server.

### Master To Proxy Client

```text
Real master -> Player A direct connection
Player A PlayerController receives direct message
Player A forwards to local proxy clients
Proxy A1 receives through networkProxyStore
Proxy A1 handles the same GameNetworkModel
```

### Proxy Client To Master

```text
Proxy A1 -> Player A proxy master
Player A proxy MasterController receives proxy message
Player A proxy MasterController handles or remaps it as Player A
Real master receives and handles it
```

The proxy is a private mirror of its host and is invisible to the real master:

- it is never added to either roster
- ACK/failed, screen, audio-list, and proxy character-announcement messages are
  consumed locally
- every message that must go upstream is rebuilt through the host
  `PlayerController`, with a fresh host counter and host `sender` identity
- dice, map-pin, and space-transform updates are first applied on the host, then
  remapped upstream
- an ID-only reveal/store request is served from the host's game memory when the
  host has all required local bytes; otherwise the host asks the master as itself

When a master repair is targeted at the host, the host clears the target before
forwarding it downstream. Its proxy mirrors can then import the same repair. A
message targeted at someone else is forwarded unchanged because that target may
be behind this proxy server.

### Proxy Ready

When a proxy client connects to a player's proxy server, the proxy master first
replays the host's current presentation (and current map state when applicable),
then sends that player's character payload:

```text
type .update
subtype .store
data: character/value payload
target: proxy connection id
```

## 12. Common Photo Transfer Scenarios

The first photo show in a game is the efficient baseline:

```text
Master -> all:
  .reveal/.show with the full photo package

Direct participants:
  import/show and return .ok

Proxy hosts:
  process the reveal and mirror it to their private proxy clients
```

Over SharePlay this broadcast package uses the photo journal slot. Over local
network the payload remains inside the JSON envelope. Once the export succeeds,
the master records that the photo has been sent for the current game.

Later shows of that photo use an ID/version reference. Participants with the
item and local file show it from memory and ACK. A participant missing metadata
or bytes returns the same `.reveal/.show` as a request. The master exports the
requested photo and responds with `targetId == requesterId`; only that player
imports and acknowledges the full response. This remains true when several
players or observers request the same photo: each request gets its own targeted
answer and never changes another participant's current screen.

That rule is for photo presentation repair (`.reveal/.show`). A map-pin cache
repair uses `.store/.store`; SharePlay can safely broadcast and coalesce that
response because storing it does not change the current screen.

For a proxy client, the host first tries to serve the request from its own
photo/file state. If it cannot, it remaps the request as the host. The master's
host-targeted answer is then mirrored downstream with the target cleared. Proxy
receipts do not appear in the master's player reports because the proxy is not a
roster participant.

The multiplayer photo test matrix deliberately marks a photo as already sent to
exercise this reference-and-targeted-repair path across players, observers, and
proxies. Separate regression tests cover alternating photos so a repair for an
older photo cannot replace the newer presentation for everyone else.

## 13. Module Behavior

### Adventure

Adventure drives game start/reset/save but is not actively handled as a network
payload in `MasterController.handle(...)`.

On master start:

- adventure focus is set
- map editor display mode changes to master
- linked adventure dice can be focused

On stop:

- adventure game reset cascades to audio, dice, map, PDF, photo, space, table,
  character/value, and weather game state.

Network messages with module `.adventure` are currently unsupported by the
master handler.

### Audio

Main payload types:

- exported audio item graph from `createGameData(for:)`
- `AudioPlayRequest(id: UUID, shouldPlay: Bool)`
- `AudioListRequest(list: [UUID], players: [UUID: [UUID]])`

Master handling:

- `.ok`: record the player's audio availability, broadcast the converged
  `.update/.audioList`, then continue any pending play
- `.failed`: release that player's in-flight transfer so a later report/reconnect
  can retry it
- `.reveal` / `.store`: return full audio payload
- `.update/.generic`: import/update audio locally, then broadcast `.reveal/.show`
- `.update/.playAudio`: cancel immediately for pause; for play, wait until every
  controlled player has the audio, target `.store/.show` payloads at missing
  player IDs, then broadcast the play command
- `.update/.audioList`: apply player's list, then broadcast all-player audio list

Player handling:

- `.reveal`: import/show if available, otherwise request payload
- `.store`: import hidden/background audio data, ACK
- `.update/.audioList`: update audio reports for the sending player
- `.update/.playAudio`: mark the audio as available for all controlled players
  and the master, then play/load it

SharePlay audio special case:

- targeted repair payloads use the journal as an untargeted `.store/.show`, so
  every participant can cache the audio and proxy hosts can mirror it
- the master device initiates playback; other SharePlay receivers load the
  playlist but do not call play locally
- `AVPlayerPlaybackCoordinator` propagates coordinated playback

Player join sync:

- after ready, player immediately sends `.update/.audioList`
- it then schedules selected-character upload
- observer sends no character; proxy sends neither audio list nor character

Audio reports are recursive for playlist entries. `allPlayersReported(for:)`
checks the root audio item and nested entries.

### Photo

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal` / `.store`: return full photo payload
- `.update`: import/update photo, then broadcast `.reveal/.show`

Player handling:

- `.reveal`: reveal/import, set current photo, reset photo space, ACK or request data
- `.store`: import hidden/background photo data, verify local bytes, ACK or
  request repair again; a successful repair releases its request-loop guard
- `.update/.photoSpace`: calls the photo game controller hook
- other `.update` with payload: imports data and sets current photo

Player-origin reveal/update messages are not presentation commands. A player
accepts those photo paths only from the master; `.store` remains accepted for
repair. The first master show carries the full package, and subsequent shows use
references.

`PhotoRPG` currently has a `photoSpace` hook but no payload behavior in the
game controller.

### Map

Main payload types:

- full exported map item payload
- live map state string from `mapUpdateResult(for:)`
- encoded `MapPinModel` for `.mapPin`

Live map state contains:

- room/entry id
- room shown state
- room focused state
- pointer
- map pins

The final map pin section is JSON for `[pointer] + mapPins`.

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal`: create full map payload
- `.reveal/.mapState`: special recovery path:
  - send targeted `.reveal/.store` with full map data
  - send targeted `.update/.mapState` to the requesting player
- `.store`: ignored for map itself
- `.update/.mapPin`: update the player's pin/pointer, then broadcast
  `.update/.mapState`
- `.update/.mapState` from players: ignored
- observer-origin updates: ignored

Player handling:

- `.reveal`: clear pending map request, reveal/import map, set current map,
  request missing pin images, ACK or request full data
- if a delivered map still lacks its background, request the full map once; the
  background never falls back to the pin-photo repair path
- `.store`: import hidden map payload; when it completes a map-state recovery,
  present the map and repair its missing pin images
- `.update/.mapState`: if map exists, apply live room/pointer/pin state, then
  rescan every pin photo reference introduced by the snapshot
- `.update/.mapState` when map is missing: send one `.reveal/.mapState` request
- `.update/.mapPin`: ignored on players; only master handles player pin updates

Missing map pin images:

After map reveal or map state update, the player checks all pin photos, including
ordinary monster/character pins added during the game.

The IDs are de-duplicated. For each pin photo absent from both the photo game
controller and persistent photo item controller, the player sends:

```text
.store/.store
data: photo id/type/version, data nil
```

The master responds through the normal photo store path. Local backing-file
availability is handled by PhotoRPG/iCloud and is not a reason for this map
reference repair when the photo item already exists.

The map background is checked independently by `hasBackgroundImage`. It is not
a pin-photo repair candidate because it belongs to the full map payload, whose
first SharePlay broadcast uses the journal.

On SharePlay, both legs use the ordered chunked messenger path. The data-less
request cannot use the journal because it contains no attachment bytes. The
full response first selects packages while still targeted, then becomes an
untargeted `.store/.store` so every member caches it without changing screens.
Responses for the same photo ID/version are coalesced, so players with different
photo subsets cause one full group transfer per unique missing photo. The cache
resets when a participant joins.

`pendingMapRequests`, `requestedFullMapIds`, `requestedRepairIds`, and the
SharePlay photo-repair coalescer bound the recovery paths so bursts cannot create
a request storm.

visionOS:

- map state updates fog of war
- pawns are synced with map pins

### Dice

Main payload types:

- full dice item payload for reveal/store
- `DiceResultModel` for normal roll results

Master handling:

- ignores `.ok`, `.failed`, and observer-origin dice
- `.reveal` / `.store`: return full dice payload
- `.update`: decode/add dice result
- if dice result has a `ResultCategory`, update the table result too

Player handling:

- applies feature gates:
  - `diceMaster`
  - `dicePlayers`
- ignores own dice echo
- `.reveal`: import if missing; request payload if needed
- `.store`: import hidden/focused dice payload
- `.update/.show` or `.update/.store`: update full dice game data
- `.update/.generic`: add the visible dice roll result

Player-origin dice is one of the few player messages that other players accept.
That is why dice rolls can fan out live before/alongside master processing.

### PDF

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal` / `.store`: return full PDF payload
- `.update`: import/update PDF, then broadcast `.reveal/.show`

Player handling:

- `.reveal`: import/show PDF, set game update type, ACK or request data
- `.store`: import hidden/background PDF data, ACK
- `.update`: no current player-side behavior

### Table

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal` / `.store`: return full table payload
- `.update`: ignored

Player handling:

- `.reveal`: import/show table, ACK or request data
- `.store`: import hidden/background table data, ACK
- `.update`: ignored

Table can still be affected by dice results. When a dice result carries a table
`ResultCategory`, the master writes that result into the table game controller.
`TableGameController.requestTableResult(...)` can also create a value result and
send it as `.update/.valueResult`.

### Character / Value

Network module is `.value`.

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal` / `.store`: return full character/value payload
- `.update`: ignore observers; import player data with force save
- after player value update, set/update that player's map pin photo if the
  player has a selected character

Player handling:

- proxy clients use `handleProxyValue(...)`
- non-proxy players only accept value messages from the master
- `.reveal`: import/show value, ACK or request data
- `.store`: import hidden/background value payload, ACK
- `.update/.generic`: add item data into the local selected character's
  adventure section
- `.update/.valueResult`: add result entries into the selected character's
  adventure section
- other `.update`: set current value item

Player ready sync:

- if not observer and the player has a character, the player sends full character
  data as `.update/.store`
- `useJournal == true` for that character send

Proxy value behavior:

- proxy client reveal/store is ignored
- proxy client update imports value data
- proxy focus is scheduled so the proxy client focuses the character after a
  short delay

### Weather

Master handling:

- `.ok`: record report; `.failed` is ignored
- all other non-ack messages return full weather payload

Player handling:

- `.reveal`: import/show weather, ACK or request data
- `.store`: import hidden/background weather data, ACK
- `.update`: set current weather item and show weather module if available

### Space

Main payload types:

- full exported space/3D item payload
- `SpaceTransformModel` for live manipulation sync

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal` / `.store`: return full space payload
- `.update/.spaceTransform`: apply transform locally only
- other `.update`: import/update space, then broadcast `.reveal/.show`

Player handling:

- `.reveal`: import/show space, ACK or request data
- `.store`: import hidden/background space data, ACK
- `.update/.spaceTransform`: apply shared transform locally
- other `.update`: set current space item

Player-origin `.spaceTransform` is accepted by other players, similar to dice.
The direct network layer fans the transform out, and handlers apply it locally.

visionOS:

- SharePlay reveal can switch presentation mode to immersive
- current immersive selection updates through bindings

### Game / Screen

`NetworkModules.game` is used for player screen data.

Player sends:

```text
type .store
subtype .screen
data.type .game
data.data: JPEG at compressionQuality 0.5
```

Master handling:

- stores the JPEG in `gameModel.playerScreens[playerId]`
- screen data appears in log/player screen views

Player handling for `.game` does nothing.

## 14. GameControllable Import/Export Contract

Most modules use the shared `GameControllable` extension.

### Sharing ID-Only Data

`share(id:)` returns:

```swift
NetworkCodableDataType(
    id: itemId,
    type: module,
    version: item.version,
    data: nil
)
```

This is what most `networkActions.shareId(...)` calls send first.

### Creating Full Game Data

`createGameData(for:)`:

1. asks the module export controller for the item graph
2. exports that graph into an in-memory stream
3. returns `NetworkCodableDataType` with payload bytes

This is the master-side answer when a participant is missing an item.

### Revealing Data

`reveal(itemId:data:save:)`:

1. checks whether the item/version exists in the game model or item controller
2. checks local backing file availability when the module has a file controller
3. imports payload data if needed
4. sets the item current/visible in game state
5. optionally persists it when `save == true`

Important detail: matching metadata is not enough for file-backed modules.
If the file is missing and the incoming message has payload data, it imports the
payload anyway.

### Updating Data

`updateGame(data:hide:deep:)`:

1. imports payload data if present
2. verifies module type for data-less updates
3. applies the item into `ItemGameModel`
4. persists only when policy is `.persist`

The default policy is:

- hidden updates: memory only
- non-hidden updates: persist

## 15. Module Entry Points To Networking

The app UI does not call `MasterController` directly. It uses
`NetworkActions` from the environment:

```swift
NetworkActions(
    shareId: { idType in ... },
    send: { update in ... },
    game: { message, actionType, playerId in ... }
)
```

Routing:

- if master controller exists, actions go through master
- otherwise actions go through player controller

Common UI/module calls:

| Module/UI | Network action |
| --- | --- |
| Generic share button | `shareId(gameController.share(id: itemId))` |
| Audio play/pause | `game(requestPlay(id:), .playAudio, nil)` |
| Dice roll | `game(diceResult, .generic, nil)` |
| Map room/pointer state | `game(networkMapUpdate(for:), .mapState, nil)` |
| Map player pin move | `game(networkPin(...), .mapPin, nil)` |
| Photo space | `game(result, .photoSpace, nil)` |
| Table result to character | `game(result, .valueResult, nil)` |
| Space manipulation | `game(transformData, .spaceTransform, nil)` |

## 16. Failure And Reconnect Behavior

### Local Network Reconnect

When a player loses the master connection:

1. `PlayerNetworkController` marks state `.lost`
2. starts its own listener using service type `.master`
3. notifies `PlayerController.lostConnection()`

The real master also browses `.master`, so it can find and reconnect to a player
that had to create a fallback listener.

`PlayerController.lostConnection()` also cancels pending character work, clears
map/audio/photo repair guards and master-state ordering, marks the master lost,
and allows identity/availability to be announced again after ready.

### Lost Player On Master

When a connection fails/cancels:

1. `MasterNetworkController` removes the connection
2. `MasterController.lostPlayer(for:)` looks up the player id by connection id
3. if the roster still contains that player, it removes roster/control entries
4. resets player-dependent module state

Stale connection mappings are evicted when a player reconnects.

When a direct or proxy connection becomes ready, its master controller replays
the current presentation immediately. A current map also gets its live map state.
A proxy connection additionally receives the host player's selected-character
payload.

### SharePlay Lost Participant

SharePlay participant removal calls:

- `masterDelegate.lostPlayer(for:)` on the master side
- `playerDelegate.lostConnection()` when the session invalidates

On SharePlay session configured, the player is notified as ready so it resends
audio availability and character data. Session invalidation resets player
connection state, but the long-lived session sequence remains subscribed so a
running game can rejoin a replacement session.

## 17. Practical Message Flow Examples

### Audio Play

```text
Player taps audio play
Player -> master:
  .update/.playAudio
  data: AudioPlayRequest(id, shouldPlay)

Master:
  checks authoritative audio availability
  if players are missing bytes:
    sends targeted .store/.show audio payloads
    waits for successful receipts/audio-list convergence

Master -> all:
  .update/.playAudio

Players:
  mark audio as available for controlled players/master
  play normally, or load for SharePlay-coordinated playback
```

Peer play requests that fan out before master processing are ignored by players;
only the master's play command can trigger player playback.

### Player Dice Roll

```text
Player rolls dice
Player -> master:
  .update/.generic
  data: DiceResultModel

Direct network fans original dice result to other players

Other players:
  accept player-origin dice
  show dice result

Master:
  records dice result
  updates table result if ResultCategory targets a table
```

### Map Reveal And State Recovery

```text
Master shares map
Master -> all:
  first show: .reveal/.show with full map payload (SharePlay journal)
  later show: .reveal/.show with map id/version only

Player has map:
  set current map
  request missing pin images if needed
  .ok

Player missing map:
  .reveal/.show request full map

Master:
  requester only: targeted .reveal/.show full map payload

Later master sends live state:
  .update/.mapState

Player missing map during state update:
  sends .reveal/.mapState once

Master:
  sends targeted .reveal/.store full map
  sends targeted .update/.mapState to requester
```

### Player Map Pin Move

```text
Player moves own pin
Player -> master:
  .update/.mapPin
  data: MapPinModel

Other players ignore original player-origin mapPin

Master:
  updates canonical pin
  broadcasts .update/.mapState

Players:
  apply map state
  rescan all pin photo references
  if a photo ID exists in neither local photo controller:
    send .store/.store with photo id/type/version and data nil

SharePlay master transport:
  send one chunked, untargeted .store/.store response per photo ID/version
  all members import it without changing the current presentation
```

### Space Transform

```text
Player manipulates 3D object
Player -> master:
  .update/.spaceTransform
  data: SpaceTransformModel

Direct network fans original transform to other players

Players:
  accept player-origin spaceTransform
  apply transform locally

Master:
  applies transform locally
```

## 18. Important Invariants And Gotchas

- Outgoing messages are encoded as a version superset: V1 peers (shipped 2.6),
  intermediate dev builds, and V2 peers all decode the same bytes. Do not remove
  the duplicated roster/control fields from the encoder without a version
  negotiation replacing them.
- Master is authoritative for roster, controls, features, and most module state.
- Current master messages carry `masterState`; current player messages carry only
  `sender`. Compatibility copies do not change that authority boundary.
- Sender/master-state snapshots are captured in one `MainActor` hop to avoid torn
  state inside a message.
- Master and player-origin counters start at `1` and increase independently.
- Requests and ACKs echo the counter they answer and strip payload bytes.
- `.ok` and `.failed` are never deduped.
- Dedup keys include payload presence; failed processing releases a key for retry.
- A player applies authoritative state only from a newer master counter.
- `proxyCounter` exists in the envelope but is not incremented by current code.
- Master direct network fan-out happens before module handling.
- Player filters block most player-origin messages. Dice and space transforms are
  intentional exceptions.
- The first map/photo/PDF/space reveal carries a full payload; later reveals use
  references. The full map includes its background and uses the SharePlay journal
  for the initial broadcast. Other modules can still begin ID-only.
- A missing receiver requests the full payload by returning the same type/subtype
  instead of `.ok`; the master's answer is targeted to that receiver.
- Logical `targetId` filtering requires a current peer. V1 peers remain protected
  only when the transport itself sends to one direct connection.
- File-backed reveal/import validation checks local file data, not only item
  metadata. Map-pin photo-reference discovery excludes the background and requests
  only pin IDs absent from both local photo controllers.
- SharePlay has one current journal publication per module. Targeted non-audio
  repairs use packages; full photo `.store/.store` repairs become coalesced group
  stores on those packages; targeted audio repairs become untargeted stores.
- A replacement attachment is published before old-attachment cleanup, and slow
  cleanup never blocks the next publication for that module.
- Journal metadata can arrive while its CloudAsset is still `uploadInProgress`.
  Attachment loading retries briefly; exhausted attempts remain eligible for a
  later journal snapshot. Reveal failures use conditional local-data recovery;
  store/update failures explicitly request full bytes over messenger. Payload
  presence prevents dedup from discarding the later full delivery.
- A normal player is also a proxy server for private local mirrors. Proxy identity
  is never sent upstream; eligible actions are remapped to the host.
- Observers receive content but should not mutate master gameplay state.
- Pin photos absent from both photo controllers are repaired with photo
  `.store/.store` requests after map reveal/state application. The background
  remains part of the full journaled map package and is never requested here.
  SharePlay carries the pin-photo requests and one untargeted, coalesced answer
  per unique photo ID/version over ordered messenger packages.

## 19. Suggested Debug Checklist

When diagnosing game communication:

1. Check the message counter and subtype in `LogGameController`.
2. Confirm whether the sender is master, player, observer, or proxy.
3. Check `targetId` before treating a received message as lost or ignored.
4. Check whether `data.data` is nil or contains a payload.
5. For file-backed items, verify `hasLocalFileData(for:)` after import.
6. Check whether controls contain the local player ID with `show == true`.
7. Check dice feature gates if dice messages are failing.
8. For map issues, inspect `pendingMapRequests`, `requestedFullMapIds`, and
   `requestedRepairIds`, and whether the map existed before `.mapState`.
9. For proxy issues, trace both legs and confirm the upstream sender is the host,
   not the proxy client.
10. For SharePlay, distinguish chunked messenger, journal metadata, and journal
    payload delivery; verify the active session ID and attachment module slot.
11. If a message appears stale, compare its counter with the last applied master
    state and remember that only legacy/unsequenced counter `0` skips dedup/order.
12. `AttachmentDownloadTask.Errors 0` with `uploadInProgress` is a transient
    CloudAsset publication race. A following `.reveal/.ok` means the receiver
    already had an exact usable local copy; `.reveal/.show` requests missing
    bytes, while failed store/update loads recover through `.store/.store`.

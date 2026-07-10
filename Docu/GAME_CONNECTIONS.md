# Game Connection And Communication Documentation

This document describes how the game communication layer works in MasterRPG:
participants, transports, counters, roster/control state, message types, replies,
and module-specific behavior for audio, photo, dice, map, PDF, table, character,
weather, space, and screen updates.

Primary source files:

- `Modules/GameRPG/Root/GameRootModel.swift`
- `Modules/GameRPG/Controller/MasterController.swift`
- `Modules/GameRPG/Controller/PlayerController.swift`
- `Modules/GameRPG/Network/GameNetworkController.swift`
- `Modules/GameRPG/Model/GameNetworkModel.swift`
- `Modules/CoreRPG/Controllable/GameControllable.swift`
- `Modules/CoreRPG/Model/NetworkCodableDataType.swift`
- `Modules/CoreRPG/Model/RPGMessageActionType.swift`
- `Modules/GameRPG/Model/RPGMessageType.swift`
- Module game controllers under `Modules/*RPG/Controller/GameController.swift`

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

Every game message uses the same envelope:

```swift
GameNetworkModel(
    counter: Int,
    proxyCounter: Int,
    type: RPGMessageType,
    subType: RPGMessageActionType,
    gameConfig: GameConfigModel,
    gameRoster: GameRosterModel,
    gameControl: GameControlModel,
    data: NetworkCodableDataType
)
```

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

Wire framing:

- `GameProtocolHeader.type`: `UInt32`
- `GameProtocolHeader.length`: `UInt32`
- `GameMessageType.gameData == 3`
- body: JSON-encoded `GameNetworkModel`

### SharePlay

SharePlay uses the same `GameNetworkModel`.

Small messages are sent through `GroupSessionMessenger` as packaged data.

Large/file-like payloads can be sent through `GroupSessionJournal` when
`fileJournal == true` and `gameNetworkModel.data.data != nil`. The metadata
stored with the journal attachment is the same `GameNetworkModel`, but with
`data.data` temporarily cleared. When a participant loads the attachment, the
binary payload is put back into `metadata.data.data` and delivered as a file
update.

If a journal attachment cannot be loaded because it was replaced during transfer,
the metadata-only model is still delivered. The player then follows the normal
missing-data path and requests the full payload from the master.

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
  sender as the only roster entry so V1 peers can resolve the sender name.
- Mappers exist in both directions: `GameNetworkModelV1.v2Model` and
  `GameNetworkModel.v1Model`.

### `GameNetworkModel`

| Field | Meaning |
| --- | --- |
| `version` | Envelope version. New messages are stamped `2` (`GameNetworkModel.currentVersion`); up-mapped V1 messages keep `1`. |
| `counter` | Master message id or copied request id. Used by logs and deduplication. |
| `proxyCounter` | Reserved proxy-hop counter. Currently preserved, not incremented in traced code. |
| `type` | High-level message kind: reveal, store, update. |
| `subType` | Action/ack subtype: show, store, ok, failed, mapState, playAudio, etc. |
| `masterId` | The master's id — routing and `isMaster` checks without roster lookups. |
| `sender` | `GameSenderModel`: id, role (`GameType`), name, characterId. The only identity a player ever sends. |
| `masterState` | `GameMasterStateModel`: state, adventureId/title, players, controls, features. **Only master messages carry it** — players structurally cannot change roster/controls. |
| `targetId` | When set, only the addressed participant processes the message (data-request responses, map-state recovery). |
| `data` | Module item id, module type, version, optional payload bytes. |

### `GameConfigModel`

Contains:

- `id`: sender id for this message
- `state`: `.stopped`, `.prepare`, `.started`
- `master`: `MasterGameModel`

`isMaster` is true when `gameConfig.id == gameConfig.master.id`.

### `GameRosterModel`

Contains the current players:

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

### `GameControlModel`

Contains:

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

## 6. Counters, Deduplication, And Logs

### Master Counters

The master owns the canonical outgoing message counter.

`MasterControllerModel.nextMessageCounter()` returns the current value and then
increments it. The counter starts at `0`.

Every master `send(...)`:

1. reserves a counter
2. snapshots config, roster, and control in one `MainActor` hop
3. creates a `GameNetworkModel`
4. adds a log entry keyed by the counter
5. sends to direct peers or proxy peers

The first master message has counter `0`. The deduplication layer only dedups
messages with `counter > 0`, so counter `0` messages are intentionally not
deduped.

### Player Counters

Player-origin normal sends use `counter: 0`:

- `send(updated:)` -> `.store/.store`
- `game(message:actionType:)` -> `.update/<action>`
- character send -> `.update/.store`
- audio list -> `.update/.audioList`

Player replies copy the counter and proxyCounter from the message they are
answering.

Player `messageCounter` is currently local process state. It is increased after
processing a message/response, but ordinary outgoing player messages still use
counter `0`.

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

Deduplication is skipped when:

- `counter <= 0`
- subtype is `.ok`
- subtype is `.failed`

The recent dedup window keeps 256 keys.

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
| `.reveal` | Show/share an item. Usually starts as ID-only, can be answered with full data. |
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

## 8. Authoritative State In Every Message

Every message carries:

- `gameConfig`
- `gameRoster`
- `gameControl`

This is deliberate. The transport does not only send the item/event. It also
sends the current game context.

### Master Broadcast Application

When a non-master player receives a message from the master, it applies the
master broadcast atomically:

```swift
root.gameModel.applyMasterBroadcast(
    master: model.gameConfig.master,
    players: model.gameRoster.players,
    controls: model.gameControl.controls,
    features: model.gameControl.features
)
```

That updates:

- master identity
- sharing controls
- feature gates
- roster

It also preserves the local player in the roster if the master broadcast does
not contain it yet.

### Master Roster Updates From Player Messages

When the master receives any player message:

1. It updates the log row for the message counter.
2. It maps the physical connection id to the sender/player id.
3. It adds or updates the player in `gameRoster`.
4. It adds or updates the sharing control for that player.
5. If the player is new, it resets player-dependent module state.

Player connection id mapping evicts stale mappings for reconnects, so a lost old
connection does not remove a player that already reconnected.

### Controls And Filtering On Players

Players process a master message only when one of these is true:

- local type is `.proxy`
- local type is `.observer`
- controls are empty
- a control exists where `control.name == localGameName && control.show == true`

After that, non-proxy players only accept:

- messages from the master
- dice messages from players
- `.spaceTransform` messages from players

This prevents ordinary player-origin fan-out messages from changing other player
state. The main exceptions are dice rolls and 3D transforms, which are intended
to be visible live.

## 9. General Request And Reply Patterns

### Pattern A: Master Reveals An Item, Everyone Already Has It

Example: master shows a photo with ID-only data.

```text
Master -> all:
  type .reveal
  subtype .show
  data: photo id, version, data nil

Each player:
  has item with matching version and local file data
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
Master -> all:
  .reveal/.show, data nil

Player with item:
  -> .reveal/.ok

Player missing item:
  -> .reveal/.show, data nil

Master receives missing-data request:
  createGameData(for: itemId)
  -> .reveal/.show, data contains exported payload

Player imports payload:
  -> .reveal/.ok
```

The master currently broadcasts the full reveal response, not only to the
requesting player, except for the special map-state recovery path.

### Pattern C: Master Reveals An Item, Local File Is Missing

`GameControllable.reveal(...)` checks both:

- item/version exists
- backing file data exists, if the module has file-backed data

If metadata exists but the binary file is missing, a full payload is imported
when it arrives. This repairs cases where CloudKit/local metadata arrived but
the actual photo/audio/PDF/space file did not.

### Pattern D: Store/Repair Transfer

`.store/.store` is used when the sender wants the receiver to import an item
without necessarily showing it. Players use this for missing map-related photos:

```text
Player detects missing map background/player-pin photo
Player -> master:
  .store/.store, data: photo id/type/version, data nil

Master:
  createGameData(for: photoId)
  -> .store/.store, data contains exported photo payload

Players:
  import hidden/background data
  -> .store/.ok
```

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

Most live updates do not ACK. Reveal/store transfers generally ACK.

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

Real master reveal messages set `fileJournal: true`. SharePlay only uses the
journal if the message actually contains payload bytes.

The real master also has a local `PlayerController(asGameMaster: true)`.
That controller calls `networkStore.setupLocal()`, which marks the direct
network controller as having a local player. When the master sends a message,
`GameNetworkController.sendPlayer(...)` also delivers the model to the local
player delegate, so the master's own UI processes the same reveal/update path as
remote players. Direct `sendMaster(...)` returns early when a local player is
registered, which avoids looping local messages back upstream.

### Player Sends Data

`PlayerController.send(model:)`:

- if local game type is `.proxy`, sends upstream through `networkProxyStore`
- otherwise sends upstream through `networkStore`
- also forwards to local proxy clients through `networkProxyStore.sendPlayer`

Player messages use SharePlay journal automatically for:

- audio
- photo
- space
- explicit `useJournal == true`

### Player Receives Master Data

When a player receives a direct, non-proxy message:

- it may apply master broadcast state
- it forwards the same message to its local proxy clients
- it schedules character/audio-list sync
- it handles the module message
- it sends a response when the handler returns one

When a player receives from proxy, it does not forward the message again to
proxy clients.

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
Player A proxy MasterController relays upstream through direct networkStore
Real master receives and handles it
```

Special case for proxy dice:

- proxy master records the dice result locally under the proxy host's game name
- it relays a model using the proxy host's gameConfig/roster/control

Other proxy messages are relayed unchanged.

### Proxy Ready

When a proxy client connects to a player's proxy server, the proxy master sends
that player's character payload to the proxy client:

```text
type .update
subtype .store
data: character/value payload
target: proxy connection id
```

## 12. Common Photo Transfer Scenarios

These scenarios match the multiplayer photo tests and the real message flow.

### Scenario 1: All Participants Already Have The Photo

Participants:

- master
- 4 players
- 2 observers
- 2 proxy clients on 2 different players

Flow:

```text
Master sends .reveal/.show with photo id only.

Direct players and observers:
  find photo item/version and local file
  set current photo
  send .ok

Players hosting proxies:
  forward the master message to their proxy clients

Proxy clients:
  find photo item/version and local file
  set current photo
  send .ok through proxy path

Master:
  receives OKs
  records reports for the photo
```

Expected network shape:

- one master reveal
- one OK per participant path that processes the reveal
- no full payload needed

### Scenario 2: One Player Does Not Have The Photo

```text
Master -> all:
  .reveal/.show, photo id only

Players with photo:
  .reveal/.ok

Missing player:
  .reveal/.show, photo id only

Master:
  exports photo via PhotoRPG game controller
  sends .reveal/.show with photo payload

Missing player:
  imports payload
  sets current photo
  .reveal/.ok
```

Because the master broadcasts the full reveal response, other participants may
also receive the payload. Their `reveal(...)` path will see the existing matching
item and ignore the import unless their backing file is missing.

### Scenario 3: One Player, One Observer, And One Proxy Do Not Have The Photo

```text
Master -> all:
  .reveal/.show, photo id only

Missing player -> master:
  .reveal/.show, request full data

Missing observer -> master:
  .reveal/.show, request full data

Missing proxy -> proxy host -> master:
  .reveal/.show, request full data

Master:
  may receive multiple missing-data requests
  sends full .reveal/.show payload for each handled request

Each missing participant:
  imports the first usable payload it receives
  sends .ok
```

Since request messages generally carry counter `0` from players/proxies, the
dedup layer does not collapse them. Multiple full responses are possible under
real conditions.

### Scenario 4: No One Has The Photo

```text
Master -> all:
  .reveal/.show, photo id only

Every participant:
  cannot reveal from local item/file
  requests full data

Master:
  handles requests and sends full payload responses

Every participant:
  imports payload
  sends .ok
```

This is the highest-traffic case. In SharePlay, the full payload can use the
journal path. On local network, the full payload is still encoded inside the
JSON `GameNetworkModel`.

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

- `.ok` / `.failed`: record report for audio id, then broadcast `.update/.audioList`
- `.reveal` / `.store`: return full audio payload
- `.update/.generic`: import/update audio locally, then broadcast `.reveal/.show`
- `.update/.playAudio`: master plays locally and returns the play command to echo it
- `.update/.audioList`: apply player's list, then broadcast all-player audio list

Player handling:

- `.reveal`: import/show if available, otherwise request payload
- `.store`: import hidden/background audio data, ACK
- `.update/.audioList`: update audio reports for the sending player
- `.update/.playAudio`: mark the audio as available for all controlled players
  and the master, then play/load it

SharePlay audio special case:

- if SharePlay is active and the sender is not the master, players load the
  playlist but do not call play locally
- `AVPlayerPlaybackCoordinator` propagates playback from the initiator

Player join sync:

- after ready, player sends selected character
- after a 5 second delay, player sends `.update/.audioList`

Audio reports are recursive for playlist entries. `allPlayersReported(for:)`
checks the root audio item and nested entries.

### Photo

Master handling:

- `.ok` / `.failed`: record report
- `.reveal` / `.store`: return full photo payload
- `.update`: import/update photo, then broadcast `.reveal/.show`

Player handling:

- `.reveal`: reveal/import, set current photo, reset photo space, ACK or request data
- `.store`: import hidden/background photo data, ACK
- `.update/.photoSpace`: calls the photo game controller hook
- other `.update` with payload: imports data and sets current photo

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

- `.ok` / `.failed`: record report
- `.reveal`: create full map payload
- `.reveal/.mapState`: special recovery path:
  - broadcast `.reveal/.store` with full map data
  - send targeted `.update/.mapState` to the requesting player
- `.store`: ignored for map itself
- `.update/.mapPin`: update the player's pin/pointer, then broadcast
  `.update/.mapState`
- `.update/.mapState` from players: ignored
- observer-origin updates: ignored

Player handling:

- `.reveal`: clear pending map request, reveal/import map, set current map,
  request missing map images, ACK or request full data
- `.store`: import hidden map payload, ACK
- `.update/.mapState`: if map exists, apply live room/pointer/pin state
- `.update/.mapState` when map is missing: send one `.reveal/.mapState` request
- `.update/.mapPin`: ignored on players; only master handles player pin updates

Missing map images:

After map reveal or map state update, the player checks:

- map background photo
- player pin photos

For each missing photo item or missing local file, the player sends:

```text
.store/.store
data: photo id/type/version, data nil
```

The master responds through the normal photo store path.

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

- `.ok` / `.failed`: record report
- `.reveal` / `.store`: return full PDF payload
- `.update`: import/update PDF, then broadcast `.reveal/.show`

Player handling:

- `.reveal`: import/show PDF, set game update type, ACK or request data
- `.store`: import hidden/background PDF data, ACK
- `.update`: no current player-side behavior

### Table

Master handling:

- `.ok` / `.failed`: record report
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

- `.ok` / `.failed`: record report
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

- `.ok` / `.failed`: record report
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

- `.ok` / `.failed`: record report
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

### Lost Player On Master

When a connection fails/cancels:

1. `MasterNetworkController` removes the connection
2. `MasterController.lostPlayer(for:)` looks up the player id by connection id
3. if the roster still contains that player, it removes roster/control entries
4. resets player-dependent module state

Stale connection mappings are evicted when a player reconnects.

### SharePlay Lost Participant

SharePlay participant removal calls:

- `masterDelegate.lostPlayer(for:)` on the master side
- `playerDelegate.lostConnection()` when the session invalidates

On SharePlay session configured, the player is notified as ready so it resends
character data and triggers state sync.

## 17. Practical Message Flow Examples

### Audio Play

```text
Player taps audio play
Player -> master:
  .update/.playAudio
  data: AudioPlayRequest(id, shouldPlay)

Direct network fans original update to other peers

Master:
  plays locally
  returns same audio command

Master -> all:
  .update/.playAudio

Players:
  mark audio as available for controlled players/master
  play or load playlist depending on SharePlay state
```

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
  .reveal/.show, map id only

Player has map:
  set current map
  request missing map images if needed
  .ok

Player missing map:
  .reveal/.show request full map

Master:
  .reveal/.show full map payload

Later master sends live state:
  .update/.mapState

Player missing map during state update:
  sends .reveal/.mapState once

Master:
  broadcasts .reveal/.store full map
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
- Every message carries config, roster, and controls to keep receivers synced.
- Config/roster/control snapshots are captured in one `MainActor` hop to avoid
  torn state inside a message.
- Master counters start at `0`; only counter values greater than `0` are deduped.
- Player-origin normal messages use counter `0`, so duplicate requests can be
  processed under real network races.
- `.ok` and `.failed` are never deduped.
- `proxyCounter` exists in the envelope but is not incremented by current code.
- Master direct network fan-out happens before module handling.
- Player filters block most player-origin messages. Dice and space transforms are
  intentional exceptions.
- `.reveal` often begins ID-only. Missing receivers request the full payload by
  returning the same type/subtype instead of `.ok`.
- Full reveal responses are generally broadcast to all participants, not just the
  requester. Map state recovery has a targeted follow-up.
- File-backed modules must check local file data, not only item metadata.
- SharePlay journal replacement can deliver metadata without bytes; the normal
  missing-data request path repairs that.
- A normal player is also a proxy server for local proxy clients.
- Observers receive content but should not mutate master gameplay state.
- Map background/player-pin photos are repaired with photo `.store/.store`
  requests after map reveal/state application.

## 19. Suggested Debug Checklist

When diagnosing game communication:

1. Check the message counter and subtype in `LogGameController`.
2. Confirm whether the sender is master, player, observer, or proxy.
3. Check whether `data.data` is nil or contains a payload.
4. For file-backed items, verify `hasLocalFileData(for:)`.
5. Check whether the player was filtered by sharing controls.
6. Check dice feature gates if dice messages are failing.
7. For map issues, check whether the map exists before `.mapState` arrives.
8. For proxy issues, trace both legs: proxy client -> player proxy -> master.
9. For SharePlay, check whether data came through messenger or journal.
10. Remember that player counter `0` messages are not deduped.

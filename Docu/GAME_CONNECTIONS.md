# Game Connection And Communication Documentation

Implementation audit: 2026-07-19.

This document describes how the game communication layer works in MasterRPG:
participants, transports, counters, roster/control state, message types, replies,
and module-specific behavior for audio, photo, dice, map, PDF, table, character,
weather, space, and screen updates.

For broader controller responsibilities, import/export controllers, and how
`GameRoot`, `MasterController`, `PlayerController`, and module `GameController`
fit into the root graph, see [Controllers](CONTROLLERS.md).
For the completed redesign record and remaining compatibility/transport work,
see [Game Communication Redesign](GAME_COMMUNICATION_PLAN.md).
For the focused topology, state/identity flow, and prioritized code-review
findings, see [Game Message Communication Flow Review](GAME_MESSAGE_COMMUNICATION_FLOW_REVIEW.md).
For recursive Table selection, generated values, targeted result sharing, and
delegated player Dice rolls, see [Table Generator](TABLE_GENERATOR.md).

Primary source files:

- `Modules/GameRPG/Root/GameRootModel.swift`
- `Modules/GameRPG/Controller/MasterController.swift`
- `Modules/GameRPG/Controller/PlayerController.swift`
- `Modules/GameRPG/Network/GameNetworkController.swift`
- `Modules/GameRPG/Network/GameNetworkController+Delivery.swift`
- `Modules/GameRPG/Model/GameNetworkModel+Shape.swift`
- `Modules/GameRPG/SharePlay/SharePlayJournalLedger.swift`
- `Modules/GameRPG/Network/ConnectionController.swift`
- `Modules/GameRPG/Model/GameNetworkModel.swift`
- `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`
- `Modules/CoreRPG/Controllable/GameControllable.swift`
- `Modules/CoreRPG/Model/NetworkCodableDataType.swift`
- `Modules/CoreRPG/Model/RPGMessageActionType.swift`
- `Modules/GameRPG/Model/RPGMessageType.swift`
- Module game controllers under `Modules/*RPG/Controller/GameController.swift`

Behavioral coverage is concentrated in:

- `Tests/GameRPGTests/SimpleFileFlowTests.swift`
- `Tests/GameRPGTests/PlayerShareReportTests.swift`
- `Tests/GameRPGTests/SharePlayJournalLedgerTests.swift`
- `Tests/GameRPGTests/GameMessageShapeTests.swift`
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
back to the master, for example dice rolls, character/player data, audio/photo
availability lists, validated photo reveals, map pin movement, and space
transforms.

Every game message uses the same current in-memory envelope:

```swift
GameNetworkModel(
    version: Int,
    messageID: UUID?,
    replyToMessageID: UUID?,
    timestamp: TimeInterval,
    counter: Int,
    proxyCounter: Int,
    type: RPGMessageType,
    subType: RPGMessageActionType,
    masterId: UUID,
    sender: GameSenderModel,
    masterState: GameMasterStateModel?,
    targetId: UUID?,
    audience: GameMessageAudience,
    purpose: GameMessagePurpose,
    journalAdmissionOnly: Bool?,
    journalPayloadDigest: Data?,
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

The master starts:

- local network listener for players
- SharePlay session when available

The real master does not start a proxy listener. Each normal player hosts its
own private proxy server for that player's mirrors.

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
ordered `PackageMessage` chunks of 64,000 raw bytes, reassembled by package UUID
and sequence number, and throttled for 200 ms after every 60 packages. The raw
size leaves room below the 256 KB messenger limit after Codable/Base64 expansion
and worst-case JSON escaping.
Each package retries transient send failures twice; a terminal failure is logged
instead of being silently discarded. A stream stays bound to the messenger that
created it, and session reset clears incomplete receive assemblies.

`GroupSessionJournal` is used when all of these are true:

- the caller requested file-journal transport
- a journal exists for the configured session
- the payload contains bytes
- the message is untargeted, or the module is audio or weather

Automatic file-journal payloads are reveal/store messages for PDF, audio, space,
photo, and the full map/background asset. A player audio upload
(`.update/.generic`) also opts in. Character/value messages never use the
Journal: a player advertises the selected character ID/version first, and the
master requests the full package only when its local version differs. A map
metadata update is never journaled: its `.update/.generic` envelope goes through
the ordered chunked messenger.

The journal stores the bytes as the attachment and a metadata-only
`GameNetworkModel`. There is one current journal publication slot per module.
Publications for the same module are serialized. A replacement is added and
committed before cleanup of the previous attachment starts; cleanup runs in a
separate session-scoped task, so a slow `remove(attachment:)` cannot block the
next map (or every later publication in that module). Attachment IDs are
processed once per snapshot lifetime. A snapshot can retain old presentation
slots from different modules; only its newest eligible map/photo/PDF/space/weather
presentation is loaded using causal reply relationships and bounded
timestamp/counter compatibility ordering. File delivery is awaited rather than
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
as an unknown legacy expectation). Map updates are structural synchronization,
not presentation intents. They have their own monotonic ordering, and the newest
update is retained if it arrives before the full base map. `mapState` remains the
volatile room/pointer/pin channel. A targeted version-zero map state from an older
master is accepted only for the already intended map. Targeted repairs, including
mapState's `.reveal/.store`, do not advance intent and are accepted only when they
match it. Intent state resets with the connection. Messenger and journal handlers
verify their session before delivery so cancellation cannot publish old-session
data.

Targeted repairs outside audio/weather stay on a physically participant-targeted
Messenger stream, so they do not replace a broadcast attachment while another
participant is downloading it. Targeted audio repairs remain journaled, but
their metadata is converted to an untargeted `.store/.show`; every participant
stores the audio without treating the repair as a new presentation. Targeted
weather repairs also remain journaled and retain `targetId`, so only the
requester applies them.

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
10. Starts direct network streaming and SharePlay when available.
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

Rewritten 2026-10-11 for the simple message flow. Sections 5, 6, 9, 10 and 12 describe the
current protocol; where a later section still mentions a repair state, a targeted Journal
repair or a first-show package, this description wins.

### Wire Format

There is one wire format, stamped `version` 3. `GameNetworkModel.init(from:)` throws for any
other version, and an envelope of the released 2.6 app (no `sender`, roster inside
`gameConfig`) does not decode at all. A 2.6 device in the same FaceTime call still joins the
GroupSession, but no message decodes in either direction.

### `GameNetworkModel`

| Field | Meaning |
|---|---|
| `version` | 3 |
| `timestamp` | Wall-clock intent time, used by last-wins peer events (map pins, Space transforms) |
| `counter` | The master's message number. A player echoes it in an acknowledgement or an asset request, and the master echoes it again in the delivery |
| `proxyCounter` | Counter of a private mirror behind a player |
| `type` | `reveal`, `store`, `update` |
| `subType` | Action, see section 7 |
| `masterId` | The game master of the session |
| `sender` | `GameSenderModel`: id, role, name, characterId, supporterTier |
| `masterState` | Roster, controls, features. Present only in master messages |
| `targetId` | When set, only that participant processes the message |
| `senderPlatform` | Device kind of the sender, for the 3D table seats |
| `data` | `NetworkCodableDataType`: id, module, version, optional bytes, optional `assetVersion`/`contentVersion` |

### Message Shapes

What a message is follows from its shape (`GameNetworkModel+Shape.swift`). There is no
audience or purpose field.

| Shape | Definition |
|---|---|
| Acknowledgement | `subType` is `.ok` or `.failed`; the counter of the answered message is echoed |
| Asset request | Sender is not the master, `type` is `reveal` or `store`, `subType` is `show` or `store`, no bytes, module is audio, dice, map, pdf, photo, space, table or weather |
| Player group event | Sender role is `player`, no target, has bytes, plausible timestamp, and it is a Dice roll (`update/generic` dice), a moved pin (`update/mapPin`) or a Space transform (`update/spaceTransform`) |
| Presentation | A master `reveal` of map, photo, pdf, space, table or weather, or a master `update/mapState` |
| Carries an asset | Has bytes of pdf, audio, space, photo, map or weather, in a `reveal`, a `store`, or a player's `update/generic` contribution |

Everything a player sends that is not a group event is for the game master only.

## 6. Ordering, Counters, Deduplication, And Logs

### Counters

The master numbers its messages from 1 (`MasterControllerModel.nextMessageCounter()`). A
message that delivers what an earlier message named keeps that message's counter: the package
that answers a request has the counter of the show the player could not use. A player numbers
its own messages independently and echoes the master's counter when it answers one.

### Presentation Order

A package can take much longer than the reference of the next show. The player keeps the
newest presentation it has seen: counter, module and item (`PlayerControllerModel.lastPresentation`).

- a presentation with the same or a newer counter is shown,
- a presentation of the item the newest one is for is shown as well: the package of a map
  arrives after the state of that map, and the state has a newer counter,
- a package of an older show of another item is stored (handled as a `store`) and not shown,
- a reference of an older show of another item is ignored.

The counter is reset with the connection, because a restarted master counts from 1 again.

### Deduplication

`GameMessagePipeline` drops a message whose `GameMessageKey` it has already processed: sender,
counter, proxy counter, type, subtype, item, module, version, target and whether it has bytes.
The reference and the package of one show therefore are two messages. Acknowledgements and
messages with counter 0 are never deduplicated.

### Logs

The master logs every message it sends with a new counter as one row
(`LogGameController.addMessage`). An `.ok` is matched to its row by the echoed counter, the
module and the item; an `.ok` that matches no row is ignored. A matched `.ok` for a `reveal`
or `store` also updates the availability report of the acknowledging player.

## 7. Message Types And Subtypes

### Top-Level Types

| Type | Meaning |
| --- | --- |
| `.reveal` | Show/share an item. A map starts with a full package for each background `assetVersion`; photo/PDF/space start with a full first-show package. Later reveals can be ID-only and request full data. |
| `.store` | Transfer/import item data without necessarily presenting it. Used for background repair/sync. |
| `.update` | Live event, command, or small state update. |

### Action Subtypes

| Subtype | Meaning |
| --- | --- |
| `.generic` | Default live update. Used for dice roll results, versioned map metadata updates, and generic module updates. |
| `.playAudio` | Audio play/pause request. |
| `.audioList` | Audio availability/report list. |
| `.photoList` | Versioned photo availability/report matrix (raw value `11`). The master's asset version is the comparison baseline. |
| `.mapState` | Live map room/pointer/pin state. |
| `.mapPin` | Player map pin/pointer movement sent to master. |
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

#### The `show` toggle is a display gate, not an access control

The game master's per-player `show` switch (`controls[].show`) is enforced only
here, on the receiving device. The master does not leave a hidden player out of
`playersMissing` or out of the sends and Journal entries of a shown item, so a
hidden player's device still receives the bytes of the photos, PDFs, 3D objects,
audio tracks and maps (over the LAN socket or the SharePlay Journal); an
unmodified client refuses to apply them and shows nothing. This is deliberate:
players are trusted by design (CODE_AUDIT_26 §6.5, decided 2026-11-15), and
holding content back and delivering it when a player is switched on would add a
second delivery path for every module. Do not describe the toggle as keeping data
off a player's device. If that guarantee is ever needed, hidden players must be
left out of `playersMissing` and the targeted/Journal sends, with the pending
content delivered when they are switched on.

#### Table dice are public to every seat

The 3D game table (visionOS `GameTableModel.applyDiceRoll`) mirrors the dice of
the master and of each player to every seat, value and orientation, without
looking at the "Share master dice" / "Share player dice" options. Those options
gate the result popover and the 2D dice overlay (`TableDiceResultVisibility`),
not the dice faces on the table. This is deliberate (CODE_AUDIT_26 §6.4, decided
2026-11-15): a die lying on the shared table is visible to everyone sitting at
it, like a real table. A game master who must keep a roll hidden does not roll it
on the table.

`targetId` filtering happens first. Only the addressee processes a targeted
message. A host still forwards a message addressed to another participant to its
local proxy clients because the actual addressee may be behind that proxy server.
When the target is the host itself, the host clears `targetId` before forwarding,
so its private mirrors process the same repair.

## 9. General Request And Reply Patterns

### Connect

`PlayerController.ready()` sends, to the master only: `update/audioList`, `update/photoList`,
`update/pdfList`, `update/spaceList`, then the Character reference (`update/store` value; the
master asks for the package when its own version differs). The master answers each list with
the authoritative list of all players, so every device knows who holds which version. A
proxy mirror sends no lists; its host answers for it.

### Master Shows An Item

One flow for Photo, Pdf, Space, Audio, Map and Weather (`MasterController.show(for:)`):

1. The master builds the reference: `reveal/show`, a new counter, no bytes.
2. It asks the module's reports which players lack its version
   (`MasterController.playersMissing`). Map, Weather and Table have no reports and name nobody.
3. `GameNetworkController.sendPresentation` delivers: the package to the players that lack
   the item (section 10), then the reference to everyone.
4. A player that holds the item shows it and answers `.ok` with the counter of the reference.
5. A player that lacks it, and that the reports did not show as lacking it, answers with an
   asset request: the same `type`, `subType` and counter, no bytes.
6. The master answers a request with the package under the counter of the request
   (`MasterController.process`), back the way the request came.
7. `.ok` marks the version as available for that player. The `.ok` after which every player
   holds the item makes the master broadcast the authoritative list again.

Two rules keep this from repeating without end:

- Only a reference is answered with a request. A package that arrived and still left the item
  unusable is answered with `.failed` (`PlayerController.response(for:isSuccess:requestData:)`).
- The master sends no package for a file it cannot read, for example an iCloud file that has
  not downloaded. It does not answer such a request; the player stays without the item.

A request that echoes no master message (a pin photo of a map) has counter 0. The master
answers it under a new counter.

### Store

A `store` keeps an item without showing it: pin photos of a map, and an audio that a play is
waiting for. It follows the same steps: reference to everyone, package to the players that
lack it, `.ok` or an asset request back.

### A Player Shares An Item

A player shows a file-backed item through the master (`PlayerController.shareFile`): it sends
`update/generic` naming the item, with the bytes only when the master's list does not contain
the item. The master imports a contribution it lacks and then shows the item like one of its
own (`MasterController.showPlayerContribution`). Players never present to each other.

### Map

A map is shown like every other item. The player holds it when it has the map, its
background image, and the background version of the reference (`assetVersion`). After every
map reveal, and after the package that answers a map request, the master sends the photo-free
content (`update/generic`) and the state (`update/mapState`), unless Share Map is paused.
A map state names the content version it belongs to; when the players last got another one,
the master sends the content before that state (`MasterControllerModel.sentMapContentVersions`),
because revealing a room adds text the players did not get while it was hidden.
Content, state and battle round that arrive before their map wait in one slot per map and are
applied when the map is there. A state for a map the player lacks asks for the map with the
state's counter, at most once in ten seconds. While Share Map is paused a map request is not
answered.

### Live Updates

Dice rolls, map pins, Space transforms, battle rounds, value updates and the availability
lists are `update` messages. They carry their whole payload and need no request.

## 10. Transport Fan-Out Details

`GameNetworkController` (and `RPGSharePlayController` behind it) decides how a message reaches
its recipients. The game controllers never choose a transport.

### Routes

`GamePlayerRoutes` binds each local-network connection and each SharePlay participant to the
first sender it speaks for. A connection cannot change its player or role, and a second
connection cannot take over a bound player. The same table gives the route to one player.

### Master Sends

| Call | Local network | SharePlay | Co-located player |
|---|---|---|---|
| `sendPlayer(data:)` | all connections | Messenger, whole session | delivered directly |
| `sendPresentation(_:missingPlayers:package:)` | package to the connections of the missing players, then the reference to all | Journal upload if a SharePlay player is missing, reference by Messenger | reference |
| `sendAsset(_:to:)` | the requesting connection only | a package through the Journal, a small message by Messenger to that participant | delivered directly |
| `sendPlayer(_:toPlayer:)` | the player's connection | Messenger to that participant | n/a |

### SharePlay Journal

The Journal holds one attachment per module. `SharePlayJournalLedger` decides whether a
package is uploaded:

| Slot | Request or show | Upload |
|---|---|---|
| empty, or another item or version | any | yes |
| same item and version | counter not newer than the upload's | no |
| same item and version | newer counter, upload older than 60 s | yes |
| same item and version | newer counter, upload younger than 60 s | no |

A request for a show that was already uploaded never uploads again. A participant whose
download failed gets the file when the game master shows the item again after a minute.
Every participant receives a Journal attachment; one that already holds that version does not
import it. A package the Journal cannot take is sent through Messenger instead.

Attachments of one snapshot are processed in counter order, the master's last, so a late
joiner ends on the presentation the master showed last. The master also replays its current
presentation to a newly ready participant (`replayCurrentPresentation`).

### Player Sends

`sendMaster(data:)` sends to the master's connection and, on SharePlay, a contributed file
through the Journal and everything else through Messenger.

### Relaying

Only player group events cross between transports. The master forwards a group event it
receives from a connection to the other connections and to SharePlay, and one it receives
from SharePlay to its connections. A player ignores every other message of another player.

### Checks At The Master

`MasterController.accepts` rejects a remote sender that claims to be the master, a role that
does not fit the transport (local network: player, observer; SharePlay and Journal: player;
proxy link: proxy), and a message for another master, except the lists and the Character a
player sends before it knows the master.

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
replays the host's current presentation. For a map it sends the reveal/reference,
latest map update, and latest map state in that order, then sends that player's
character payload:

```text
type .update
subtype .store
data: character/value payload
target: proxy connection id
```

## 12. Common Photo Transfer Scenarios

Covered by `Tests/GameRPGTests/SimpleFileFlowTests.swift` and `PlayerShareReportTests.swift`.

| Scenario | What crosses the network |
|---|---|
| Everyone holds the photo | The reference to all; `.ok` from each player |
| One local-network player reported no copy | The package on that player's connection, the reference to all |
| A player the master had no report from lacks it | The reference to all, an asset request from that player, the package on its connection under the same counter |
| A SharePlay player lacks it | One Journal upload, the reference by Messenger; a second request for the same show uploads nothing |
| A player shares a photo the master holds | `update/generic` without bytes to the master, then the master's show |
| A player shares a photo the master lacks | `update/generic` with bytes to the master, which imports it and shows it |
| The package of an earlier show arrives late | It is stored; the screen keeps the later show |

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

- `.ok`: record the player's audio availability and continue any pending play;
  the eventual `.update/.playAudio` makes a second full-list broadcast unnecessary
- `.failed`: release that player's in-flight transfer so a later report/reconnect
  can retry it
- `.reveal` / `.store`: return full audio payload
- `.update/.generic`: import/update audio locally, then broadcast `.reveal/.show`
- `.update/.playAudio`: cancel immediately for pause; for play, wait until every
  controlled player has the audio, target `.store/.show` payloads at missing
  player IDs, then broadcast the play command
- `.update/.audioList`: accept a successfully decoded report only when its
  per-player message counter is newer, apply it, then broadcast the authoritative
  all-player audio list. Counter zero remains an unsequenced legacy format.

Player handling:

- `.reveal`: import/show if available, otherwise request payload
- `.store`: import hidden/background audio data, ACK
- `.update/.audioList`: accept only a successfully decoded, newer authoritative
  list from the master
- `.update/.playAudio`: for a play command, recursively mark the audio and its
  playlist entries as available for all current visible players and the master,
  then play/load it. Pause does not change availability.

SharePlay audio special case:

- targeted repair payloads use the journal as an untargeted `.store/.show`, so
  every participant can cache the audio and proxy hosts can mirror it
- the master device initiates playback; other SharePlay receivers load the
  playlist but do not call play locally
- `AVPlayerPlaybackCoordinator` propagates coordinated playback

Player join sync:

- after ready, player immediately sends `.update/.audioList`
- it then sends `.update/.photoList`
- it then schedules selected-character upload
- observer sends no character; proxy sends neither availability list nor character

Audio reports are recursive for playlist entries. `allPlayersReported(for:)`
checks the root audio item and nested entries.

When a player disconnects, the master removes that player from every audio
availability report and clears the player's last accepted audio-list counter.

### Photo

Main payload types:

- exported photo data or an ID/version reference
- `PhotoListRequest(list: [UUID: Int], players: [UUID: [UUID: Int]])`

Master handling:

- `.ok`: preserve the master asset version as baseline and record the sender only
  when its ACK version matches; `.failed` is ignored
- valid player `.reveal/.show`: do not import or rebroadcast; transport fan-out
  already sent it, so deliver the same event only to the master's local player
- unavailable or version-mismatched player `.reveal/.show`: ignore player bytes
  and broadcast the master's full canonical version
- `.store`: return the master's full photo payload
- `.update/.photoList`: accept a successfully decoded, newer player report,
  apply it, then broadcast the authoritative matrix
- `.update/.generic` from an older player: never import its bytes; broadcast the
  master's canonical photo for compatibility

Player handling:

- master or validated player `.reveal/.show`: reveal/import, set current photo,
  ACK with the effective photo version, or request the master baseline data
- `.store`: import hidden/background photo data, verify local bytes, ACK or
  request repair again; a successful repair releases its request-loop guard
- `.update/.photoList`: accept only a successfully decoded, newer authoritative
  list from the master
- other `.update` with payload: imports data and sets current photo

A player-origin reveal is a presentation command only when the authoritative
matrix proves the sender owns the exact master baseline and the envelope names
that version. Other player photo updates are rejected; `.store` remains accepted
for repair. The first master show carries the full package, and subsequent shows
can use references.

### Map

Main payload types:

- full exported map/background asset payload for `.reveal/.show`
- schema-versioned `MapUpdatePayload` for `.update/.generic`
- live map state string for `.update/.mapState`
- encoded `MapPinModel` for `.mapPin`

`MapUpdatePayload` is a complete metadata snapshot. It includes map editor
configuration, scales, geometry, rooms, pins, and photo UUID references, but no
photo or other file bytes. Its `contentVersion` fingerprints that structural
snapshot. The separate `assetVersion` fingerprints the background photo UUID and
the photo's content version.

Live map state contains:

- room/entry id
- room shown state
- room focused state
- pointer
- map pins

The final map pin section is JSON for `[pointer] + mapPins`.

Master handling:

- `.ok`: record report; `.failed` is ignored
- `.reveal`: create a full map payload when the background asset is new, otherwise
  reveal by reference; refresh and late-join replay paths send the latest map
  update separately
- `.reveal/.mapState`: special recovery path:
  - send targeted `.reveal/.store` with full map data
  - send the latest targeted `.update/.generic` map update
  - send targeted `.update/.mapState` to the requesting player
- `.store`: ignored for map itself
- `.update/.generic` from players: ignored; the master owns map metadata
- `.update/.mapPin`: update the player's pin/pointer, then broadcast
  `.update/.mapState`
- `.update/.mapState` from players: ignored
- observer-origin updates: ignored

Player handling:

- `.reveal`: clear pending map request, reveal/import map, set current map,
  request missing pin images, ACK or request full data
- current peers reuse a data-less reveal only when `assetVersion` matches; a
  mismatching reference requests the full package, while a newly sequenced full
  payload is imported even when the legacy scale-derived `version` is unchanged
- if a delivered map still lacks its background, request the full map once; the
  background never falls back to the pin-photo repair path
- `.store`: import hidden map payload; when it completes a map-state recovery,
  apply any pending newest map update, present the map, and repair its missing pin
  images
- `.update/.generic` with `MapUpdatePayload`: apply the newest complete metadata
  snapshot in place; if the base map is not present yet, retain the newest update
  until reveal/store completes
- `.update/.mapState`: if map exists, apply live room/pointer/pin state, then
  rescan every pin photo reference introduced by the snapshot
- `.update/.mapState` when map is missing: send one `.reveal/.mapState` request
- `.update/.mapPin`: ignored on players; only master handles player pin updates

The map-update order is independent from visual presentation ordering, so it
cannot switch the player away from a newer photo/map presentation. Neither a
stale update nor a late older Journal payload can roll metadata back. Applying a
structural snapshot preserves newer volatile pointer/pin state while still
accepting authoritative pin metadata such as name, photo, color, and size; the
latest `mapState` remains authoritative for runtime state.

Missing map pin images:

After map reveal, map update, or map state update, the player checks all pin
photos, including ordinary monster/character pins added during the game.

The IDs are de-duplicated. For each pin photo absent from both the photo game
controller and persistent photo item controller, the player sends:

```text
.store/.store
data: photo id/type/version, data nil
```

The master responds through the normal photo store path. Local backing-file
availability is handled by PhotoRPG/iCloud and is not a reason for this map
reference repair when the photo item already exists.

The map background is checked independently by `hasBackgroundImage`. It is never
inserted into the pin-photo request set, even if its UUID appears in the metadata
snapshot. The background belongs to the full map payload, whose first SharePlay
broadcast for an `assetVersion` uses the journal; a missing or mismatched
background requests that full map asset.

On SharePlay, both legs use the ordered chunked messenger path. The data-less
request cannot use the journal because it contains no attachment bytes. The
full response retains its logical recipient and is sent as a physically targeted
Messenger stream, so unrelated members neither import nor acknowledge it.

`pendingMapRequests`, `requestedFullMapIds`, and `requestedRepairIds` bound the
local recovery paths so bursts cannot create a request storm.

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

The Table Generator keeps completed-summary traffic separate from normal Table
transport by using the `.generator` payload module and `.generatedValue` action.
Delegated generator rolls still travel through DiceRPG with a Table
`ResultCategory`; an active generation session consumes that categorized result
before the Table controller's legacy result path. See
[Table Generator](TABLE_GENERATOR.md) for the complete selection and routing
flow.

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
| Map editor refresh (`EditMapToolBar`) | Send the versioned map-update payload with `.update/.generic` |
| Map room/pointer state | Send the volatile map-state payload with `.update/.mapState` |
| Map player pin move | `game(networkPin(...), .mapPin, nil)` |
| Photo share | `game(photoData, .generic, nil)`, converted by the player controller to `.reveal/.show` |
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
map/audio/photo repair guards plus audio/photo list counter sequences and
master-state ordering, marks the master lost, and allows identity/availability
to be announced again after ready.

### Lost Player On Master

When a connection fails/cancels:

1. `MasterNetworkController` removes the connection
2. `MasterController.lostPlayer(for:)` looks up the player id by connection id
3. if the roster still contains that player, it removes roster/control entries
4. removes that participant from all audio and versioned photo reports
5. clears that participant's last accepted audio/photo-list counters
6. resets player-dependent module state

Stale connection mappings are evicted when a player reconnects.

When a direct or proxy connection becomes ready, its master controller replays
the current presentation immediately. A current map is replayed in dependency
order: full-asset reveal/reference first, latest map update second, and latest
volatile map state last. A proxy connection additionally receives the host
player's selected-character payload.

### SharePlay Lost Participant

SharePlay participant removal calls:

- `masterDelegate.lostPlayer(for:)` on the master side
- `playerDelegate.lostConnection()` when the session invalidates

On SharePlay session configured, the player is notified as ready so it resends
audio and photo availability before character data. Session invalidation resets
player connection state, but the long-lived session sequence remains subscribed
so a running game can rejoin a replacement session.

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
    waits for successful receipts

Master -> all:
  .update/.playAudio

Players:
  mark audio as available for current visible players/master
  play normally, or load for SharePlay-coordinated playback
```

Peer play requests that fan out before master processing are ignored by players;
only the master's play command can trigger player playback.

### Player Photo Reveal

```text
At ready:
  player -> master: .update/.photoList with local photo versions
  master -> all: .update/.photoList with master baseline + participant matrix

Player chooses a photo:
  sender has baseline, everyone has baseline:
    player -> all/master: .reveal/.show reference

  sender has baseline, someone is missing/mismatched:
    player -> all/master: .reveal/.show full master-version package
    SharePlay publishes it through the photo journal

  sender is absent/mismatched:
    player -> master: .reveal/.show master-baseline reference, no player bytes
    master -> all: .reveal/.show full canonical master package

Recipients:
  accept a player reveal only when sender report and envelope both equal baseline
  reveal/import, then ACK while preserving the effective photo version

Master for a valid player reveal:
  does not resend to LAN/SharePlay
  delivers the already-fanned-out event only to its co-located local player
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
  first show of an assetVersion: .reveal/.show with full map/background payload
  (SharePlay journal)
  same-asset reshow: .reveal/.show with map id/version only

Late-join replay -> joining player:
  .reveal/.show with map id/version only
  .update/.generic with the latest MapUpdatePayload (chunked messenger)
  .update/.mapState with the latest volatile game state

Master changes map metadata (for example pinScale or hexMapScale) or taps the
refresh button in EditMapToolBar
Master -> all:
  .update/.generic with complete metadata and photo IDs, no photo bytes
  the existing journal attachment remains valid

Master changes the background photo UUID or its file content version
Master -> all:
  new full .reveal/.show publication (SharePlay journal)
  latest .update/.generic map metadata snapshot

Player has map:
  set current map
  request missing pin images if needed
  .ok

Player missing map:
  .reveal/.show request full map

Master:
  requester only: targeted .reveal/.show full map payload
  targeted latest .update/.generic map metadata snapshot

Later master sends live state:
  .update/.mapState

Player missing map during state update:
  sends .reveal/.mapState once

Master:
  sends targeted .reveal/.store full map
  sends targeted latest .update/.generic map update
  sends targeted .update/.mapState to requester

Late join/reconnect:
  map reveal/reference -> latest map update -> latest map state
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

- Outgoing messages use one envelope compatibility superset across V1,
  intermediate dev, and V2 layouts. This does not make a new enum raw value such
  as `.photoList == 11` decodable by a binary that lacks the case. Do not remove
  the duplicated roster/control fields from the encoder without version
  negotiation replacing them.
- Master is authoritative for roster, controls, features, and most module state.
- Current master messages carry `masterState`; current player messages carry only
  `sender`. Compatibility copies do not change that authority boundary.
- Sender/master-state snapshots are captured in one `MainActor` hop to avoid torn
  state inside a message.
- Master and player-origin counters start at `1` and increase independently.
- Those sender-local counters do not provide a global presentation order. A
  delayed player photo Journal reveal cannot be causally compared with a later
  master presentation without adding a master-presentation epoch to the wire
  model; raw player and master counters must never be compared for that purpose.
- Requests and ACKs echo the counter they answer and strip payload bytes; photo
  replies preserve the effective asset version needed for baseline validation.
- `.ok` and `.failed` are never deduped.
- Dedup keys include payload presence; failed processing releases a key for retry.
- A player applies authoritative state only from a newer master counter. Audio
  and photo lists additionally track their own per-sender accepted counters;
  malformed/stale lists never advance those sequences.
- `proxyCounter` exists in the envelope but is not incremented by current code.
- Master direct network fan-out happens before module handling. A valid
  player-photo reveal is therefore not broadcast again by the master; only its
  co-located local player needs explicit delivery.
- Player filters block most player-origin messages. Dice and space transforms are
  intentional exceptions. A photo reveal is accepted only when both the sender's
  authoritative report and the envelope equal the master's asset baseline.
- The first photo/PDF/space reveal of each version carries a full payload;
  same-version reveals use references. Map full-publication identity is instead
  its `assetVersion`, which fingerprints the background photo UUID plus content
  version. Scale and editor changes alter `contentVersion` and send a complete
  file-byte-free map update over `.update/.generic`; they do not replace the SharePlay
  journal attachment. A background change does. The full map includes its
  background. Other modules can still begin ID-only.
- Photo availability is `(photo ID, master asset version)`, not ID-only. The
  master version remains authoritative even when a player starts the reveal. A
  matching player sends a reference when everyone has it or a full group payload
  when someone does not; a mismatched player sends no bytes and causes the master
  to publish its canonical version.
- A missing receiver requests the full payload by returning the same type/subtype
  instead of `.ok`; the master's answer is targeted to that receiver.
- Logical `targetId` filtering requires a current peer. V1 peers remain protected
  only when the transport itself sends to one direct connection.
- File-backed reveal/import validation checks local file data, not only item
  metadata. Map-pin photo-reference discovery excludes the background and requests
  only pin IDs absent from both local photo controllers.
- Map update is a semantic payload discriminator inside the existing
  `.update/.generic` action, not a new action enum case. This preserves V1 envelope
  decoding. The payload is schema-versioned, complete, and contains photo IDs but
  no photo/file bytes, so it always uses the chunked messenger.
- A late join receives the map reveal/reference, latest map update, and latest
  map state in that order. Map-update ordering is independent of presentation
  intent, and a newest update received before its base map is applied after the
  map arrives.
- SharePlay has one current journal publication per module. Targeted repairs
  outside audio/weather use physically targeted Messenger packages. Targeted
  audio repairs become untargeted cache stores; targeted weather repairs retain
  their logical recipient in Journal metadata.
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
  `.store/.store` requests after map reveal/update/state application. The
  background remains part of the full journaled map package and is never requested
  here. Requests are deduplicated locally, and SharePlay returns a physically
  targeted Messenger repair to each requester.
- Table weather (`.update/.tableWeather`) is parked: `MasterController.isTableWeatherEnabled`
  is `false`, so the game master never sends it, while a player still accepts the message from
  any master. The path is `MasterController+TableWeather.swift`,
  `PlayerController+TableWeather.swift` and `Model/TableWeather.swift`; the three
  `TableWeatherTests` that need the flag are disabled with it. No removal date is set.

## 19. Suggested Debug Checklist

When diagnosing game communication:

1. Check the message counter and subtype in `LogGameController`.
2. Confirm whether the sender is master, player, observer, or proxy.
3. Check `targetId` before treating a received message as lost or ignored.
4. Check whether `data.data` is nil or contains a payload.
5. For file-backed items, verify `hasLocalFileData(for:)` after import.
6. Check whether controls contain the local player ID with `show == true`.
7. Check dice feature gates if dice messages are failing.
8. For map issues, inspect the pending base-map/update state,
   `requestedFullMapIds`, and `requestedRepairIds`; compare `assetVersion` and
   `contentVersion`, and confirm whether the map existed before the update/state.
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

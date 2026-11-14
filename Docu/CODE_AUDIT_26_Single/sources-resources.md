# Audit: Sources/{MasterRPG,MasterTV,RPGShare,DiceRollerWidget} + Resources

Files read: every Swift file in Sources/RPGShare (8 files, ~1.0k LOC), Sources/MasterRPG (app, delegates, window lists, menus, shortcuts, Spotlight indexer; ~1.5k LOC), Sources/MasterTV, Sources/DiceRollerWidget (provider, intents, widget views, content widgets; ~1.0k LOC); Resources/Info.plist, InfoTV.plist, all six entitlement files plus the RPGShare and widget ones, the three PrivacyInfo.xcprivacy files; the build settings of MasterRPG, MasterTV, MasterMac, RPGShare and the widget target in MasterRPG.xcodeproj/project.xcproj (the project file is JSON-style, not a pbxproj). Supporting code read for context: ShareExtensionDatabaseService, ShareImportPhotoController, ContentWidgetSnapshot, DiceConfiguration/DiceIntents, RootURLHandler, AppModel+Routing, the App Group defaults (AppGroup.swift, AppSettingsModel). Overall health: good. The app entry points are thin and well guarded (route de-duplication, termination flush with deadline, scene-delegate/SwiftUI double URL delivery handled by `admitsExternalRoute`). Entitlements are consistent: Debug/Release aps-environment pairs are development/production everywhere, App Group + iCloud container identifiers match CLAUDE.md, ATS has no exceptions, usage strings match the APIs actually used (camera only via `UIImagePickerController` on iOS, photo access via `PhotosPicker`, hand tracking on visionOS, local network for Bonjour; no microphone, location, contacts or motion APIs; no required-reason API beyond file timestamps and UserDefaults, which the manifests declare). The main weaknesses are in the share extension (what it does with input it cannot use, memory behaviour in a ~120 MB process), a couple of widget accessibility/representation bugs, and manifest hygiene. No Critical issues.

## Findings

### Share extension accepts files it cannot read and drops failures silently
- Category: Bug
- Location: Sources/RPGShare/Info.plist:9-16 (`NSExtensionActivationSupportsFileWithMaxCount` = 1); Sources/RPGShare/SharingView.swift:181-196 (`try?` on both loads); Sources/RPGShare/ItemProviderImporter.swift:24-31 (per-item failures only logged, remaining photos silently dropped when the 60 MiB budget is hit)
- What: Any single file (PDF, zip, audio, video) activates the extension, but only images and text are loaded; both `loadImages` and `loadTexts` errors are swallowed with `try?`, and per-image failures or the payload-budget `break` are only logged.
- Why: Sharing a PDF opens a normal-looking form with no preview and empty fields; the user can type a name and "Save" an Adventure/Character that contains none of what they shared. Sharing 8 photos where 3 fail or exceed the budget saves 5 without any notice.
- Action: Restrict the activation rule to what is handled (image/text predicate form), and when nothing could be loaded or some items were dropped, show a message ("N of M items could not be added") instead of an empty form.
- Severity: Medium
- Status: NEW

### Save to the Photo module with no images reports success and saves nothing
- Category: Bug
- Location: Sources/RPGShare/ShareExtensionSaveController.swift:86-87 (`case .photo: break`); Sources/RPGShare/SharingView.swift:259-268 (Save only requires a non-empty name); Sources/RPGShare/ModuleChooserView.swift:13 (`.photo` always selectable)
- What: With a text-only share (or after all image loads failed) and "Photo" selected, `saveContent` loops over zero images, hits `break`, saves an unchanged context and the extension closes as if it worked.
- Why: The shared text is silently lost; the user believes a photo item exists.
- Action: Disable Save (or hide `.photo`) while `images` is empty, or throw a "no photo to save" error.
- Severity: Medium
- Status: NEW

### In-memory image paths bypass the size caps meant for the ~120 MB extension limit
- Category: Performance
- Location: Sources/RPGShare/ItemProviderImporter.swift:244-264 (`loadItem` returning `.data` from `Data`/`NSData`), :271-290 (`loadDataRepresentation` has no byte limit), :105-113 (`downsampledIfNeeded` only runs after the whole payload is in memory)
- What: The file/URL path is capped (`maximumSourceFileByteSize`, downsampled from disk), but a provider that hands over `Data` or an object that has to go through `loadDataRepresentation` loads the full original into memory before any check.
- Why: A host app that shares an image as data (browser long-press, some editors) with a 100+ MB original can get the extension jailed-killed; the share is lost with no message. CODE_AUDIT_18 §6.4 only closed the URL/file path.
- Action: Prefer `loadFileRepresentation` (a temporary file the importer already knows how to downsample from disk) for the data fallback, and check `Data.count` against the source cap before decoding.
- Severity: Medium
- Status: NEW

### Shared images are decoded at full resolution inside `body`, up to ten at once
- Category: Performance
- Location: Sources/RPGShare/PhotoSection.swift:20-35 (`AKImage(data:)` per cell in `body`); Sources/RPGShare/SharingView.swift:141 (`.animation(value: imageListModel.images)`)
- What: Each preview cell builds an `AKImage` from JPEG data of up to 4096 px (roughly 50 MB decoded each) every time the cell body runs, and `LazyHStack` keeps created cells alive; `ImageItem` is `Hashable` over its whole `Data`, so the animation `value:` compares megabytes of image data on each SharingView update.
- Why: The memory budget the importer works hard to respect can be spent by the preview alone; unverified on device, but 10 photos are explicitly allowed by the activation rule.
- Action: Create thumbnails once (ImageIO thumbnail at the display size) when the images are loaded and store them in `ImageItem`; animate on `images.map(\.id)`.
- Severity: Medium
- Status: NEW (unverified on device)

### Initial name from shared text is empty when the text starts with whitespace and splits the whole text
- Category: Bug
- Location: Sources/RPGShare/SharingView.swift:191-194
- What: `joined.components(separatedBy: .whitespacesAndNewlines).first` returns `""` for text beginning with a space or newline (common when sharing from Notes/Messages) and walks the entire string (up to 5 MiB per item) just to take the first element.
- Why: The Save button stays disabled ("name is empty") with no hint why; large texts are split needlessly.
- Action: Trim first and use `split(maxSplits: 1, whereSeparator:)`/`prefix(while:)` on the trimmed string; cap the name length.
- Severity: Low
- Status: NEW

### Loading state has no Cancel while the sheet is non-dismissable, and the database is opened on the main actor
- Category: Bug
- Location: Sources/RPGShare/ShareViewController.swift:27 (`isModalInPresentation = true`); Sources/RPGShare/SharingView.swift:76, 237-249 (`SharingLoadingView` has no button), :163-182 (`initialize()` awaits only synchronous work after `extractItems`); Modules/RolePlayGameKit/Model/ShareExtensionDatabaseService.swift:42-80 (`setup()` is `async` but loads the full multi-module Core Data/CloudKit stack synchronously)
- What: While the images are being downsampled and the store is being opened the only controls are hidden; an iOS user cannot swipe the sheet away either.
- Why: A slow store open (store migration after an app update, a large CloudKit store) leaves a spinner the user cannot leave until the system watchdog ends the extension. Unverified how long a typical open takes.
- Action: Show Cancel in the loading view; open the store off the main actor or at least let the UI render the spinner before the synchronous call.
- Severity: Low
- Status: NEW (unverified)

### Error view discards the user's input and offers only Close
- Category: Bug
- Location: Sources/RPGShare/SharingView.swift:97-122, :218-230
- What: A save failure sets `errorMessage`, which replaces the whole content view; the typed name/text and the loaded images are not shown again and there is no Retry.
- Why: After a transient failure (iCloud container momentarily unavailable) the user has to restart the share from scratch.
- Action: Show the error as an alert/banner over the form and keep the form editable.
- Severity: Low
- Status: NEW

### macOS share extension is sandboxed without the outgoing-network entitlement but downloads remote files
- Category: Bug
- Location: MasterRPG.xcodeproj/project.xcproj:1681-1684 (RPGShare: `ENABLE_APP_SANDBOX` yes, no `ENABLE_OUTGOING_NETWORK_CONNECTIONS`, no hardened runtime), :1704 (`macosx` supported); Sources/RPGShare/ItemProviderImporter.swift:138-150, :300-312 (`GuardedRemoteDownload`)
- What: The remote-URL download branches of the importer need `com.apple.security.network.client` on macOS; the main Mac app has it, the extension does not (and does not set `ENABLE_HARDENED_RUNTIME` like the widget does).
- Why: On macOS an image that arrives as a remote URL fails inside the sandbox with a generic error. Unverified at runtime; low reach because the activation rule has no web-URL type.
- Action: Either add the outgoing-network setting for the extension or remove the remote branches on macOS; enable hardened runtime for consistency.
- Severity: Low
- Status: NEW (unverified)

### Accessibility label of the content-widget count hides the number
- Category: SwiftUI
- Location: Sources/DiceRollerWidget/ContentWidgets.swift:121-124
- What: `Text(totalCount, format: .number).accessibilityLabel(Text(countLabel))` replaces the content with the label "characters"/"adventures".
- Why: VoiceOver reads "characters" instead of "3 characters" for the medium widget.
- Action: Use the number as the value (`accessibilityValue`) or build one combined label "\(count) \(countLabel)".
- Severity: Medium
- Status: NEW

### Dice widget shows only the first die of a multi-dice roll
- Category: Bug
- Location: Sources/DiceRollerWidget/DiceRollerWidgetView.swift:153-195; Modules/DiceRPG/Widget/DiceConfiguration.swift:53-62 (`DiceWidgetDice.init(_ diceSnapshot:)` keeps `dice.first`'s sides and last face)
- What: A roll recorded from the app/Siri ("3d6+2") is reduced to one die image with the first die's face, while the accessibility value reads the sum.
- Why: The widget picture contradicts the roll (face 4 shown, total 14); the total is never shown visually in the small/medium layouts.
- Action: Show `lastRoll.sum` as text next to the die (and the notation as the name); keep the die image only for single-die rolls.
- Severity: Medium
- Status: NEW

### Content widgets publish GM-side names to the Home Screen
- Category: Security
- Location: Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:56-70 (publish, `fullVisible` and non-special only); Sources/DiceRollerWidget/ContentWidgets.swift:100-139
- What: Names of the first four visible Characters and Adventures (which include NPCs and monsters the GM keeps private) are copied to App Group defaults and drawn by the widget, including on a Lock Screen/Today view and in screen-shared sessions, with no opt-out setting.
- Why: Spoiler leak to bystanders or players watching a shared screen (the widget is "show on lock screen" capable). Probably acceptable by design, but it is a product decision not yet recorded.
- Action: Decide and document; at minimum honour `widgetRenderingMode`/`redactionReasons` (`.privacy`) and `Text(...).privacySensitive()` for the names.
- Severity: Low
- Status: NEW

### Test gap: share extension, content-widget snapshot and widget timeline have no tests
- Category: Test gap
- Location: Sources/RPGShare/ItemProviderImporter.swift (size caps, downsampling, budget), Sources/RPGShare/ShareExtensionSaveController.swift:38-60 (rollback + removal of written files), Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift, Sources/DiceRollerWidget/DiceRollerProvider.swift:34-61 (two-entry timeline) - no test under Tests/ references any of them (grep of Tests/ for these type names).
- What: The riskiest untrusted-input code of the app targets (image decode limits, partial-save cleanup) is only covered indirectly through `ShareImportPhotoController` in FolderAuditPhotoTests.
- Why: The memory/size findings above cannot regress-test themselves; the extension target cannot be imported by tests as is.
- Action: Move `ItemProviderImporter`'s pure static helpers and the name-derivation into a module (CoreRPG/PhotoRPG) and add tests for oversize, undecodable and zero-length data, and for `ContentWidgetSnapshot` encode/decode and the 4-item cap.
- Severity: Low
- Status: NEW

### UTIs for `.gmz`/`.gms` are both exported and imported in the same plist
- Category: API
- Location: Resources/Info.plist:130-188 vs :370-430 (`de.AndreTrettin.GameMaster.gmz`, `.gms` in `UTExportedTypeDeclarations` and `UTImportedTypeDeclarations`); Resources/InfoTV.plist:111-190
- What: An app should either own a type (export) or consume a foreign one (import); declaring the same identifier in both lists is redundant and the two copies already differ (`public.mime-type` empty array only in the imported copy).
- Why: Conflicting duplicate declarations can make Launch Services pick either copy; harmless today but easy to drift.
- Action: Keep only the exported declarations for the app's own types; leave imported declarations for `org.universalvtt.map`.
- Severity: Low
- Status: NEW

### tvOS and iOS targets carry keys and settings that belong to other platforms
- Category: API
- Location: MasterRPG.xcodeproj/project.xcproj:1506-1512 (MasterTV: camera, photo-library, Desktop/Documents/Downloads usage strings), :1383-1385 (MasterRPG iOS/visionOS: macOS-only folder strings), :1353 (`AUTOMATION_APPLE_EVENTS` = YES on a target without macOS), Resources/Info.plist (UIKit scene manifest and `UIBackgroundModes` shared with MasterMac), Resources/InfoTV.plist:51-62 (ubiquity container with no iCloud Drive on tvOS)
- What: Strings and settings for capabilities the platform does not have.
- Why: Noise for App Review and a wider declared surface than needed; no runtime effect found.
- Action: Trim per-target settings to the platform's real capabilities.
- Severity: Low
- Status: NEW

### tvOS has no `com.apple.developer.group-session` entitlement although GroupActivities code is compiled for it
- Category: API
- Location: Resources/MasterTV-Debug.entitlements, Resources/MasterTV-Release.entitlements; Modules/GameRPG/SharePlay/RPGActivity.swift:1-10 (no tvOS guard); Modules/GameRPG/SetupViews/SharePlayButton.swift:3 (UI is `!os(tvOS)`)
- What: SharePlay session code builds for tvOS while the entitlement is missing; no tvOS UI starts a session, so a failure can only happen if a FaceTime activity targets the TV app.
- Why: Either dead code on tvOS or a latent SharePlay failure.
- Action: Gate the SharePlay controllers with `#if !os(tvOS)` or add the entitlement deliberately.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_17 §6.12] (unverified at runtime)

### macOS entitlements use the iOS key name for push
- Category: API
- Location: Resources/MasterRPG-Mac-Debug.entitlements:5-6, Resources/MasterRPG-Mac-Release.entitlements:5-6 (`aps-environment`)
- What: On macOS the push entitlement key is `com.apple.developer.aps-environment`; the file uses the iOS key. Xcode may translate it through the provisioning profile, which is why builds work today.
- Why: Could break CloudKit silent pushes on Mac for a manual/Developer ID signing flow. Unverified.
- Action: Confirm with a signed Release archive (`codesign -d --entitlements :-`) that the Mac build carries the macOS key; otherwise change the key in the Mac files.
- Severity: Low
- Status: NEW (unverified)

### Viewer windows open a random item id when no selection is passed
- Category: Bug
- Location: Sources/MasterRPG/Window/WindowViewerList.swift:80
- What: `selection ?? WindowItemSelection(itemId: UUID())` creates a window for a non-existent item whenever `openWindow(id:)` is called without a value (the `WindowGroup(for:)` optional is nil).
- Why: The user gets an empty/error viewer window; the fresh UUID also changes identity on every body evaluation.
- Action: Show a `ContentUnavailableView` for nil, like `TableGeneratorWindowContent` already does.
- Severity: Low
- Status: NEW

### Duplicated per-module window lists and widget helpers
- Category: Duplication
- Location: Sources/MasterRPG/Window/WindowViewerList.swift:25-77 (ten near-identical `viewer(root:itemId:configuration:)` blocks), Sources/MasterRPG/Window/WindowLinkList.swift:25-45 (eleven blocks), Sources/DiceRollerWidget/ContentWidgets.swift:81-93 and :136-148 (identical `moduleTitle`/`moduleIcon`/`countLabel` in small and medium views), Sources/DiceRollerWidget/DiceRollerWidget.swift:13-30 (`#if os(iOS)/macOS/else` branches return the same array)
- What: Copy-paste per module/family.
- Why: Every new module needs edits in several places; the widget branches hide that nothing differs per platform.
- Action: Share the content-widget helpers in one small type; collapse `supportedWidgetFamilies` to one array; table-drive the window lists where the root types allow (the typed `root` makes this hard, so low priority).
- Severity: Low
- Status: NEW

### Dead code and CLAUDE.md style drift in the share extension and menus
- Category: Dead code
- Location: Sources/RPGShare/ModuleChooserView.swift:60-63 (`ModuleChooserModel.preview`, unreferenced), Sources/MasterRPG/Menu/AboutMenuCommand.swift:38-41 (`AboutPanelCommand.init(title:options:)` only used by the other init) and :52-56 (`public extension Bundle.displayName` in an app target), Sources/RPGShare/SharingView.swift:97 and :125 (`errorView(message:)`/`contentView(size:)` are methods that return views - CLAUDE.md asks for `View` structs), Sources/RPGShare/SharingView.swift:98, 119-141 and PhotoSection.swift:19-25, :40 (hard-coded spacing, `frame(height: 300)`, `width: size.width - 30`)
- What: Unused declarations and a few forbidden layout patterns.
- Why: Minor maintainability.
- Action: Delete the unused members; extract the two view helpers into structs; use layout containers (`containerRelativeFrame`) instead of `size.width - 30`.
- Severity: Low
- Status: NEW

## Checked and found fine (no finding)
- URL/activity entry: `RootURLHandler` accepts only file URLs for `.gmz`/VTT documents and opens an import UI that needs an explicit confirmation; `RPG://` links only navigate. Scene delegate and SwiftUI both receive the URL; `admitsExternalRoute` and `pendingImportURL` de-duplicate.
- Termination/background flush: macOS `terminateLater` has a 5 s deadline; iOS uses a per-flush background-task token and an expiration handler.
- App Group: `useCloudKit` is read from the App Group defaults in the extension (CODE_AUDIT §5.2 fix confirmed); content/dice snapshots are Codable, written by the app only, decoded with `try?` and fall back to empty.
- Entitlements: Debug=development / Release=production in all MasterRPG, Mac and TV pairs; RPGShare and widget have only the keys they need (iCloud + App Group, App Group).
- Privacy manifests: the three copies are identical; no use of disk-space, boot-time, active-keyboard APIs in Modules/Sources (grep), so the declared categories are sufficient.
- Bonjour service types in both plists match `GameServiceType`; `NSLocalNetworkUsageDescription` present; ATS has no exceptions.

Not audited in this area: the content of the module `Commands`/`Root` views referenced from the window lists, the localized string catalogs (AppShortcuts/InfoPlist/Localizable xcstrings), AccessoryDiceView.swift (skimmed for accessibility only), the RPGResources packages and Resources/RPGTabletopGameContent, asset catalogs, and the pbxproj-level target membership beyond the settings quoted above. Core Data store opening in the extension (CoreDataPersistenceController, CloudKit mirroring from an extension) was only read for context and belongs to the persistence audit.

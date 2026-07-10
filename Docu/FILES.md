# File Handling

This document explains MasterRPG file storage: app JSON side stores, user/media
item files, security-scoped locations, content hashes, import/export, and game
repair behavior.

Related docs:

- [Root Models And Setup](ROOT_MODELS.md)
- [Controllers](CONTROLLERS.md)
- [Database Handling](DATABASE.md)
- [Game Connections](GAME_CONNECTIONS.md)

## Two File Systems

MasterRPG has two different file systems:

1. structured JSON-style app data through `FileDataController`
2. user/media item files through `FileUrlDataController`

Core Data stores the item model and `FileUrl` metadata. Large media bytes are
loaded, saved, exported, and repaired through file controllers.

## FileUrl

`FileUrl` is the persistent reference stored on file-backed item models. It contains:

- `fileId`: usually the owning item id
- raw relative or absolute URL
- `FileLocation`
- module token
- transient `data`
- SHA256 `contentHash`

The transient `data` field is not part of equality or hashing. This prevents
attaching/detaching transport bytes from bumping CRDT versions. `contentHash` is
part of equality because same URL with different binary data is a real change.

`contentVersion` derives a stable integer from the content hash so master and
player devices can agree on file content over the network.

## FileLocation

Supported locations:

- `.appCloud`
- `.icloud`
- `.local`
- `.other`
- `.newCloud`
- `.url`

Most imported or newly picked managed files become `.newCloud`, with data written
under the app-managed iCloud/document area and a bookmark saved for access. The
older location cases remain in the wire/storage model so imports and updates from
old app versions can resolve existing file metadata before rewriting managed
copies.

## FileUrlDataController

`FileUrlDataController` is the main media file controller. It owns:

- `CloudDocumentController`: app-managed cloud document folder operations
- `FileBookmarkController`: security-scoped bookmarks
- `LocationFileManager`: legacy absolute/relative URL conversion
- `FileUrlDataModel`: folder bookmark display state
- allowed `UTType` file types and the module filename extension

It can:

- check download status
- check security-scoped access
- check whether local binary data exists
- load data
- resolve a URL and run a closure with security-scoped access
- create a file URL from imported bytes
- create a file URL from a picker URL
- compare whether a new URL points to the same file
- delete files/bookmarks
- duplicate file-backed items
- move files when categories/folders/names change

When imported bytes are stored, `createNewFileUrl` calculates or reuses a content
hash, writes the data to the app cloud folder, saves a bookmark, and returns a
`FileUrl` without transient data. If storage fails, it returns a `FileUrl` that
keeps transient data as fallback.

## File-Backed Modules

Photo, PDF, audio, map, and space use file URLs heavily:

- Photo/PDF item controllers create `FileUrlDataController` and `CacheController`.
- PDF can create `PDFDocument` after ensuring the file is downloaded.
- Audio loads file URLs into temporary files for `AVURLAsset` so playback streams from disk instead of memory.
- Map uses photo roots and cache controllers for background map images.

## Files During Import

The shared import stream uses optional file chunks before item chunks:

```text
ItemHeader(counter: byteCount, token: file)
<file bytes>
ItemHeader(counter: byteCount, token: item)
<JSON item bytes>
```

When import sees file bytes:

1. It computes a SHA256 content hash.
2. If an existing local file has the same hash and actual local data exists, it reuses the existing file URL.
3. Otherwise it writes the file through `FileUrlDataController.createNewFileUrl`.
4. If cloud/app storage fails, the `FileUrl` keeps the binary in transient memory as a fallback.
5. `ItemControllable.reset(fileUrl:item:)` updates the imported item before it is merged/replaced.

A `file` token applies only to the next `item` token, then it is cleared so later
file-less items do not inherit the old bytes.

This matters in game mode because a player may already have metadata for an item
but not the binary. `GameControllable.reveal` imports again when the version
matches but local file data is missing.

## Files During Export

File-backed modules inline binary bytes unless `exportWithoutFileData` is true.
The exported file bytes precede the JSON item so import can attach the file to
that exact item.

Photo export can fall back to cached JPEG data when the original file data is not
available. Cache fallback is useful when game/export needs something displayable
quickly, but the original file remains the preferred source.

Game networking uses the same module stream in memory. The
`NetworkCodableDataType` envelope carries message metadata, while the stream
carries full module payloads and optional file bytes. For game transfer scenarios
that repair missing local media, see
[Game Connections - Common Photo Transfer Scenarios](GAME_CONNECTIONS.md#12-common-photo-transfer-scenarios).

## CacheController

File-backed image/PDF/map modules expose `cacheControllable`. Cache controllers
load thumbnails or images through `FileUrlDataController`, remove stale cache
entries when files change, and provide fallback data for game/export when the
original file has to be displayed quickly.

## FileDataController

`FileDataController<Datatype>` is a separate JSON persistence helper for smaller
codable app data. It stores an array of `DataModel(id:data)` in a JSON file under
the app group, and can optionally save external binary blobs under
`URL.documentsDirectory/<name>/<uuid><extension>`.

Use this for small structured side stores, not for regular module item
persistence. Module item data belongs in Core Data; item media belongs in
`FileUrlDataController`.

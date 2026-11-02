// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// Regression tests for the untrusted-import hardening of CODE_AUDIT_15
/// (§5.1 path traversal, §5.2 peer import policy, §5.3 clock, §6.3 remote hosts).
@Suite("Untrusted import hardening")
struct UntrustedImportTests {
    // MARK: - §5.1 path traversal

    /// `URL.path` keeps a trailing slash for a directory that exists on disk.
    private func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    @Test("fullUrl(fileUrl:) never leaves the module folder")
    func fullUrlStaysInsideModuleFolder() throws {
        let controller = CloudDocumentController(modulePath: "Photos")
        let moduleRoot = normalizedPath(controller.moduleUrl)

        let hostile = try #require(URL(string: "../../Stores/Private/private.sqlite"))
        let resolved = normalizedPath(try #require(controller.fullUrl(fileUrl: hostile)))

        #expect(resolved.hasPrefix(moduleRoot + "/"))
        #expect(!resolved.contains(".."))
    }

    @Test("fullUrl(filePath:) drops traversal segments")
    func fullUrlFilePathStaysInsideModuleFolder() throws {
        let controller = CloudDocumentController(modulePath: "Pdfs")
        let moduleRoot = normalizedPath(controller.moduleUrl)

        for path in ["/../../Stores/x", "a/../../b", "../../../etc/passwd", "./x/./y"] {
            let resolved = normalizedPath(try #require(controller.fullUrl(filePath: path)))
            #expect(resolved.hasPrefix(moduleRoot + "/"), "\(path) escaped to \(resolved)")
        }
    }

    @Test("An encoded slash cannot climb out of the module folder (CODE_AUDIT_Folder §6.3)", arguments: [
        "..%2F..%2FStores%2FPrivate%2Fprivate.sqlite",
        "/..%2F..%2Fsecret.pdf",
        "a%2F..%2F..%2F..%2Fb",
        "..%2f..%2fx"
    ])
    func encodedSlashStaysInsideModuleFolder(path: String) throws {
        let controller = CloudDocumentController(modulePath: "Pdfs")
        let moduleRoot = normalizedPath(controller.moduleUrl)
        let hostile = try #require(URL(string: path))

        let resolved = normalizedPath(try #require(controller.fullUrl(fileUrl: hostile)))

        #expect(resolved.hasPrefix(moduleRoot + "/"), "\(path) escaped to \(resolved)")
        #expect(CloudDocumentController.hasTraversalComponents(hostile))
    }

    @Test("sanitizedForImport splits an encoded-slash traversal (CODE_AUDIT_Folder §6.3)")
    func sanitizedEncodedSlash() throws {
        let hostile = FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "..%2F..%2FStores%2Fprivate.sqlite")),
            location: .newCloud,
            module: "Photos",
            relativeUrl: nil
        )

        let sanitized = hostile.sanitizedForImport()

        #expect(sanitized.rawUrl.pathComponents.allSatisfy { $0 == "/" || (!$0.contains("/") && $0 != "..") })
        #expect(sanitized.rawUrl.lastPathComponent == "private.sqlite")
    }

    @Test("A clean relative path keeps resolving to the same file")
    func cleanPathIsUnchanged() throws {
        let controller = CloudDocumentController(modulePath: "Photos")
        let moduleRoot = normalizedPath(controller.moduleUrl)
        #expect(normalizedPath(try #require(controller.fullUrl(filePath: "Category/a b.png"))) == moduleRoot + "/Category/a b.png")
    }

    // MARK: - CODE_AUDIT_21 §5.1, §6.1 paths that resolved to the module folder

    @Test("A file in a user folder named Documents resolves to that folder, not the module folder", arguments: [
        ("Documents/Rules.pdf", "/Documents/Rules.pdf"),
        ("/Documents/Rules.pdf", "/Documents/Rules.pdf"),
        ("Campaign/Documents/Rules.pdf", "/Campaign/Documents/Rules.pdf"),
        ("Documents/Maps/x.pdf", "/Documents/Maps/x.pdf"),
        ("Handouts/Rules.pdf", "/Handouts/Rules.pdf")
    ])
    func userFolderNamedDocuments(stored: String, expected: String) throws {
        let controller = CloudDocumentController(modulePath: "Pdfs")
        let moduleRoot = normalizedPath(controller.moduleUrl)
        let storedUrl = try #require(URL(string: stored))

        let resolved = try #require(controller.fullUrl(fileUrl: storedUrl))

        #expect(normalizedPath(resolved) == moduleRoot + expected)
        // The stored path survives the round trip an import or a move takes it through.
        #expect(controller.nameUrl(fullUrl: resolved).path(percentEncoded: false) == expected)
    }

    @Test("A path that names no file below the module folder does not resolve", arguments: [
        "/", ".", "..", "./..", "//"
    ])
    func folderPathDoesNotResolve(path: String) throws {
        let controller = CloudDocumentController(modulePath: "Pdfs")
        #expect(controller.fullUrl(fileUrl: try #require(URL(string: path))) == nil)
        #expect(controller.fullUrl(filePath: path) == nil)
    }

    @Test("An absolute file url is reduced to its path below the container")
    func absoluteFileUrlIsReducedToItsContainerPath() throws {
        let controller = CloudDocumentController(modulePath: "Pdfs")
        let moduleRoot = normalizedPath(controller.moduleUrl)

        // Another device's container.
        let foreign = URL(filePath: "/Users/other/Library/Mobile Documents/iCloud~app/Documents/pdf/Handouts/Rules.pdf")
        #expect(normalizedPath(try #require(controller.fullUrl(fileUrl: foreign))) == moduleRoot + "/Handouts/Rules.pdf")

        // This device's module folder, with a user folder named like the container folder.
        let own = controller.moduleUrl.appending(path: "Documents").appending(path: "Rules.pdf")
        #expect(normalizedPath(try #require(controller.fullUrl(fileUrl: own))) == moduleRoot + "/Documents/Rules.pdf")
        #expect(controller.nameUrl(fullUrl: own).path(percentEncoded: false) == "/Documents/Rules.pdf")

        // The container itself names no file.
        #expect(controller.fullUrl(fileUrl: controller.moduleUrl) == nil)
        #expect(controller.fullUrl(fileUrl: URL(filePath: "/Users/other/Documents/pdf")) == nil)
    }

    @Test("sanitizedForImport relocates a path that would resolve to a storage folder", arguments: [
        ("/", FileLocation.newCloud),
        ("/", FileLocation.appCloud),
        ("/", FileLocation.icloud),
        ("file:///Users/other/Documents/pdf", FileLocation.newCloud),
        ("file:///var/mobile/Documents", FileLocation.local),
        ("/Documents", FileLocation.local)
    ])
    func sanitizedFolderPath(path: String, location: FileLocation) throws {
        let hostile = FileUrl(fileId: UUID(), url: try #require(URL(string: path)), location: location, module: "Pdfs", relativeUrl: nil)

        let sanitized = hostile.sanitizedForImport()

        #expect(sanitized.location == .newCloud)
        #expect(sanitized.fileId == hostile.fileId)
        let controller = CloudDocumentController(modulePath: "Pdfs")
        let resolved = try #require(controller.fullUrl(fileUrl: sanitized.rawUrl))
        #expect(normalizedPath(resolved).hasPrefix(normalizedPath(controller.moduleUrl) + "/"))
    }

    @Test("sanitizedForImport keeps a file in a folder named Documents untouched")
    func sanitizedKeepsDocumentsFolder() throws {
        let clean = FileUrl(fileId: UUID(), url: try #require(URL(string: "Documents/Rules.pdf")), location: .newCloud, module: "Pdfs", relativeUrl: nil)
        #expect(clean.sanitizedForImport().rawUrl == clean.rawUrl)
        #expect(clean.sanitizedForImport().location == .newCloud)
    }

    @Test("sanitizedForImport removes traversal from cloud locations and leaves clean urls untouched")
    func sanitizedCloudLocation() throws {
        let hostile = FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "../../Stores/Private/private.sqlite")),
            location: .newCloud,
            module: "Photos",
            relativeUrl: nil
        )
        let sanitized = hostile.sanitizedForImport()
        #expect(!sanitized.rawUrl.pathComponents.contains(".."))
        #expect(sanitized.rawUrl.lastPathComponent == "private.sqlite")
        #expect(sanitized.location == .newCloud)

        let clean = FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "Category/photo.png")),
            location: .newCloud,
            module: "Photos",
            relativeUrl: nil
        )
        #expect(clean.sanitizedForImport() == clean)
        #expect(clean.sanitizedForImport().rawUrl == clean.rawUrl)
    }

    @Test("sanitizedForImport turns a foreign picked file into an app-owned file and keeps its data")
    func sanitizedOtherLocation() throws {
        var foreign = FileUrl(
            fileId: UUID(),
            url: URL(filePath: "/Users/someone/Documents/secret.pdf"),
            location: .other,
            module: "Pdfs",
            relativeUrl: nil,
            contentHash: "hash"
        )
        foreign.resetData(Data([1, 2, 3]))

        let sanitized = foreign.sanitizedForImport()
        #expect(sanitized.location == .newCloud)
        #expect(sanitized.rawUrl.lastPathComponent == "secret.pdf")
        #expect(sanitized.fileId == foreign.fileId)
        #expect(sanitized.data == Data([1, 2, 3]))
    }

    // MARK: - §6.3 remote hosts

    @Test("Remote urls to private or local hosts are refused, public ones are kept", arguments: [
        ("https://example.com/a.png", true),
        ("http://93.184.216.34/a.png", true),
        ("https://localhost/a.png", false),
        ("https://127.0.0.1/a.png", false),
        ("https://10.1.2.3/a.png", false),
        ("https://192.168.1.20/a.png", false),
        ("https://172.20.0.1/a.png", false),
        ("https://169.254.10.10/a.png", false),
        ("https://nas/a.png", false),
        ("https://printer.local/a.png", false),
        ("https://[::1]/a.png", false),
        // CODE_AUDIT_18 §6.5: shorthand IPv4 literals stay refused, hex-letter hostnames are real names.
        ("https://127.1/a.png", false),
        ("https://0x7f.0.0.1/a.png", false),
        ("https://2130706433/a.png", false),
        ("https://cafe.be/a.png", true),
        ("https://dead.beef.com/a.png", true),
        // CODE_AUDIT_19 §6.1: IPv6 literals are parsed, and leading-zero IPv4 labels are numeric.
        ("https://[0:0:0:0:0:0:0:1]/a.png", false),
        ("https://[0::1]/a.png", false),
        ("https://[::ffff:127.0.0.1]/a.png", false),
        ("https://[::ffff:7f00:1]/a.png", false),
        ("https://[fe80::1%25en0]/a.png", false),
        ("https://[fd12:3456::1]/a.png", false),
        ("https://[2606:4700:4700::1111]/a.png", true),
        ("https://0177.0.0.1/a.png", false),
        ("https://010.0.0.1/a.png", false),
        ("https://224.0.0.251/a.png", false),
    ])
    func publicRemoteHosts(urlString: String, isPublic: Bool) throws {
        let url = try #require(URL(string: urlString))
        #expect(url.isPublicRemoteFileUrl == isPublic)
    }

    @Test("A peer's private-host url is relocated, the user's own import may keep it")
    func remoteUrlPolicy() throws {
        let remote = FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "https://192.168.1.20/map.png")),
            location: .url,
            module: "Photos",
            relativeUrl: nil
        )
        #expect(remote.sanitizedForImport().location == .newCloud)
        #expect(remote.sanitizedForImport(allowsPrivateRemoteHosts: true) == remote)
    }

    // MARK: - §5.2 peer import policy

    @MainActor
    @Test("A peer package may write its own item, items it introduced and new items only")
    func peerImportPolicyAdmission() {
        let primary = UUID()
        let introducedBefore = UUID()
        let foreignExisting = UUID()
        let brandNew = UUID()
        let policy = PeerImportPolicy(primaryItemId: primary, ownedItemIds: [introducedBefore])

        #expect(policy.admit(itemId: primary, existsLocally: true))
        #expect(policy.admit(itemId: introducedBefore, existsLocally: true))
        #expect(!policy.admit(itemId: foreignExisting, existsLocally: true))
        #expect(policy.admit(itemId: brandNew, existsLocally: false))

        #expect(policy.rejectedItemCount == 1)
        #expect(policy.introducedItemIds == [introducedBefore, primary, brandNew])
    }

    @MainActor
    @Test("A peer package is capped in size")
    func peerImportPolicyItemCap() {
        let policy = PeerImportPolicy(primaryItemId: UUID(), maximumItems: 2)
        #expect(policy.admit(itemId: UUID(), existsLocally: false))
        #expect(policy.admit(itemId: UUID(), existsLocally: false))
        #expect(!policy.admit(itemId: UUID(), existsLocally: false))
    }

    @MainActor
    @Test("A peer's folder is admitted only for items the peer brings, and keeps just those entries")
    func peerFolderAdmission() {
        let primary = UUID()
        let newPhoto = UUID()
        let ownedPhoto = UUID()
        let outer = UUID()
        let inner = UUID()
        let policy = PeerImportPolicy(primaryItemId: primary)
        // The master already owns `ownedPhoto`: rejected, so it is not part of the peer's path.
        #expect(policy.admit(itemId: newPhoto, existsLocally: false))
        #expect(!policy.admit(itemId: ownedPhoto, existsLocally: true))

        let admitted = policy.admitFolders([
            // Listed outer first: the outer folder passes once the inner one did.
            .init(id: outer, childIds: [inner], existsLocally: false),
            .init(id: inner, childIds: [ownedPhoto, newPhoto], existsLocally: false)
        ])

        #expect(admitted == [outer: [inner], inner: [newPhoto]])
    }

    @MainActor
    @Test("A peer's folder with nothing of the peer in it, or that exists here, is not created")
    func peerFolderRejection() {
        let ownedPhoto = UUID()
        let newPhoto = UUID()
        let emptyPath = UUID()
        let knownFolder = UUID()
        let policy = PeerImportPolicy(primaryItemId: UUID())
        #expect(!policy.admit(itemId: ownedPhoto, existsLocally: true))
        #expect(policy.admit(itemId: newPhoto, existsLocally: false))

        let admitted = policy.admitFolders([
            .init(id: emptyPath, childIds: [ownedPhoto], existsLocally: false),
            .init(id: knownFolder, childIds: [newPhoto], existsLocally: true)
        ])

        #expect(admitted.isEmpty)
        #expect(!policy.introducedItemIds.contains(emptyPath))
        #expect(!policy.introducedItemIds.contains(knownFolder))
    }

    // MARK: - §5.3 clock

    @Test("Observing a far-future remote clock keeps later local writes ahead of it")
    func observedClockAdvancesLocalWrites() {
        // Based on the real clock, not `MonotonicWallClock.now()`: the process-wide clock may
        // already run up to the allowed skew ahead after another test's merge, and a value
        // derived from it could exceed the cap.
        let future = Date().timeIntervalSinceReferenceDate + 3_600
        MonotonicWallClock.observe(future)
        #expect(MonotonicWallClock.now() > future)
    }

    @Test("A finite far-future remote clock is capped instead of ratcheting the local clock")
    func hugeFiniteClockIsBounded() {
        // Pure bound check: observing it for real would raise the process-wide clock that
        // the other tests in this suite share.
        let now = 1_000.0
        #expect(MonotonicWallClock.bounded(.greatestFiniteMagnitude, now: now) == now + MonotonicWallClock.maximumObservedSkew)
        #expect(MonotonicWallClock.bounded(now + 60, now: now) == now + 60)
        #expect(MonotonicWallClock.bounded(.greatestFiniteMagnitude, now: now).nextUp.isFinite)
    }

    @Test("Non-finite remote clocks are ignored")
    func nonFiniteClockIgnored() {
        let before = MonotonicWallClock.now()
        MonotonicWallClock.observe(.nan)
        MonotonicWallClock.observe(.infinity)
        let after = MonotonicWallClock.now()
        #expect(after.isFinite)
        #expect(after > before)
    }

    @Test("A register edited after merging a future value wins over it")
    func mergeThenEditWins() {
        // Based on the live clock: it is process-wide and other tests advance it too.
        var mine = LWWRegister("old", actorID: "b")
        let attacker = LWWRegister("attacker", actorID: "a", timestamp: MonotonicWallClock.now() + 3_600)
        mine.merging(with: attacker)
        #expect(mine.value == "attacker")

        mine.value = "edited"
        let merged = attacker.merged(with: mine)
        #expect(merged.value == "edited")
    }

    /// CODE_AUDIT_18 §5.5 / CODE_AUDIT_19 §5.5: a far-future clock (here ~100 years) wins the
    /// merge it arrives in on every replica alike, but the next local edit orders after it, so
    /// it can't freeze the field.
    @Test("A far-future clock cannot freeze a field")
    func farFutureClockDoesNotFreezeField() {
        let farFuture = MonotonicWallClock.now() + 100 * 365 * 86_400
        let attacker = LWWRegister("attacker", actorID: "a", timestamp: farFuture)

        var honest = LWWRegister("old", actorID: "b")
        honest.merging(with: attacker)
        #expect(honest.value == "attacker")

        honest.value = "edited"
        var poisoned = attacker
        poisoned.merging(with: honest)
        #expect(poisoned.value == "edited")
        #expect(attacker.merged(with: honest).value == "edited")
    }

    /// CODE_AUDIT_19 §5.5: the merge result must not depend on the merging device's time. An
    /// edit from a device whose clock runs more than the allowed skew ahead used to be
    /// rejected by every other replica while its author kept it, so replicas diverged.
    @Test("Replicas converge on an edit from a device whose clock runs fast")
    func fastClockEditConverges() {
        let fastClock = MonotonicWallClock.now() + 3 * 86_400
        let fastDevice = LWWRegister("fast", actorID: "a", timestamp: fastClock)
        let slowDevice = LWWRegister("slow", actorID: "b")

        #expect(fastDevice.merged(with: slowDevice).value == "fast")
        #expect(slowDevice.merged(with: fastDevice).value == "fast")
    }

    @Test("Merging is commutative for atoms with equal clocks")
    func equalClocksOrderByActor() {
        let clock = MonotonicWallClock.now()
        let first = LWWRegister("first", actorID: "a", timestamp: clock)
        let second = LWWRegister("second", actorID: "b", timestamp: clock)
        #expect(first.merged(with: second).value == second.merged(with: first).value)
    }

    @Test("A local write orders after the value it overwrites")
    func localWriteOrdersAfterStoredValue() {
        let aheadWithinSkew = MonotonicWallClock.now() + 3_600
        var register = LWWRegister("remote", actorID: "a", timestamp: aheadWithinSkew)
        register.value = "local"
        let stale = LWWRegister("remote", actorID: "a", timestamp: aheadWithinSkew)
        #expect(register.merged(with: stale).value == "local")
    }
}

// @copyright André Trettin

import AudioRPG
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import Testing
import UniformTypeIdentifiers

@testable import RolePlayGameKit

@MainActor
@Suite("Foundry VTT media projection")
struct FoundryVTTDomainMapperMediaTests {
    @Test("Packaged raster and audio resources are normalized while SVG remains unsupported")
    func normalizesPackagedMediaAttachments() async throws {
        // Given
        let imageResource = resource(path: "art/portrait.apng")
        let vectorResource = resource(path: "art/token.svg")
        let audioResource = resource(path: "audio/intro.wav")
        let sourceData = [
            imageResource.logicalPath: try #require(Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+R0YdWQAAAABJRU5ErkJggg=="
            )),
            vectorResource.logicalPath: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8),
            audioResource.logicalPath: makeSilentPCMWave(),
        ]
        let package = makePackage(resources: [imageResource, vectorResource, audioResource])
        let sourceScopeId = try #require(
            UUID(uuidString: "02AB1D8D-4DAB-4A9D-8DD2-A52633255AB4")
        )

        // When
        let mapped = try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-media-test.zip"),
            sourceScopeId: sourceScopeId,
            selectedCategories: [.assets],
            resourceLoader: { resource in
                guard let data = sourceData[resource.logicalPath] else {
                    throw FixtureError.missingResource(resource.logicalPath)
                }
                return data
            }
        )
        let photoItem = try #require(mapped.batch.items.first { $0.module == .photo })
        let audioItem = try #require(mapped.batch.items.first { $0.module == .audio })
        let photoAttachment = try #require(photoItem.attachment)
        let audioAttachment = try #require(audioItem.attachment)
        let jpegData = try await photoAttachment.load()
        let mpeg4AudioData = try await audioAttachment.load()

        // Then
        #expect(photoItem.model is PhotoModel)
        #expect(photoItem.name == "portrait.jpg")
        #expect(photoAttachment.suggestedFilename == "portrait.jpg")
        #expect(photoAttachment.contentTypeIdentifier == UTType.jpeg.identifier)
        #expect(photoAttachment.expectedByteCount == nil)
        #expect(photoAttachment.contentHash == nil)
        #expect(jpegData.starts(with: [0xff, 0xd8, 0xff]))
        #expect(jpegData.suffix(2).elementsEqual([0xff, 0xd9]))

        #expect(audioItem.model is AudioModel)
        #expect(audioItem.name == "intro.m4a")
        #expect(audioAttachment.suggestedFilename == "intro.m4a")
        #expect(audioAttachment.contentTypeIdentifier == UTType.mpeg4Audio.identifier)
        #expect(audioAttachment.expectedByteCount == nil)
        #expect(audioAttachment.contentHash == nil)
        #expect(String(data: mpeg4AudioData.dropFirst(4).prefix(4), encoding: .ascii) == "ftyp")

        #expect(mapped.batch.items.filter { $0.module == .photo }.count == 1)
        #expect(!mapped.batch.items.contains { $0.name == "token.svg" })
        #expect(mapped.unsupportedResources == [vectorResource])
    }

    // CODE_AUDIT_26 §5.40: the path of a packaged file is a zip entry, not a URL. Cut at `#`,
    // `Token #1.webp` and `Token #2.webp` shared one key and the second file was never imported.
    @Test("Packaged files with # and ? in their names are all imported")
    func filesWithFragmentCharactersStayDistinct() async throws {
        // Given
        let first = resource(path: "tokens/Token #1.webp")
        let second = resource(path: "tokens/Token #2.webp")
        let third = resource(path: "tokens/Who?.png")
        let sourceData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+R0YdWQAAAABJRU5ErkJggg=="
        ))
        let package = makePackage(resources: [first, second, third])

        // When
        let mapped = try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-token-names-test.zip"),
            sourceScopeId: UUID(),
            selectedCategories: [.assets],
            resourceLoader: { _ in sourceData }
        )
        let photoNames = mapped.batch.items.filter { $0.module == .photo }.map(\.name).sorted()

        // Then
        #expect(photoNames == ["Token #1.jpg", "Token #2.jpg", "Who?.jpg"])
        #expect(mapped.batch.items.filter { $0.module == .photo }.count == 3)
    }

    @Test("Playlist and ambient audio contexts import WebM and MP4 without unsupported warnings")
    func importsContextDependentAudio() async throws {
        // Given
        let playlistResource = resource(path: "audio/playlist.webm")
        let ambientResource = resource(path: "audio/ambient.mp4")
        let playlistSound = document(
            id: "Playlist.playlist.Sound.theme",
            type: .playlistSound,
            name: "Theme",
            parentId: "Playlist.playlist",
            rawData: .object(["path": .string(playlistResource.logicalPath)])
        )
        let playlist = document(
            id: "Playlist.playlist",
            type: .playlist,
            name: "Playlist",
            embeddedDocuments: [playlistSound]
        )
        let ambientSound = document(
            id: "Scene.scene.AmbientSound.room",
            type: .ambientSound,
            name: "Room ambience",
            parentId: "Scene.scene",
            rawData: .object(["path": .string(ambientResource.logicalPath)])
        )
        let scene = document(
            id: "Scene.scene",
            type: .scene,
            name: "Scene",
            embeddedDocuments: [ambientSound],
            rawData: .object([
                "width": .integer(1_200),
                "height": .integer(800),
                "grid": .object(["size": .integer(100)]),
            ])
        )
        let package = makePackage(
            resources: [playlistResource, ambientResource],
            collections: [
                FoundryDocumentCollection(
                    id: "playlists",
                    name: "playlists",
                    label: "Playlists",
                    sourcePath: "data/playlists",
                    declaredDocumentType: .playlist,
                    documents: [playlist],
                    folders: []
                ),
                FoundryDocumentCollection(
                    id: "scenes",
                    name: "scenes",
                    label: "Scenes",
                    sourcePath: "data/scenes",
                    declaredDocumentType: .scene,
                    documents: [scene],
                    folders: []
                ),
            ]
        )
        let sourceScopeId = try #require(
            UUID(uuidString: "1713B637-1702-4B95-AB71-6FA8BF55458D")
        )

        // When
        let mapped = try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-contextual-audio-test.zip"),
            sourceScopeId: sourceScopeId,
            selectedCategories: [.assets, .playlists, .scenes],
            resourceLoader: { _ in Data() }
        )

        // Then
        let attachmentNames = Set(mapped.batch.items.compactMap {
            $0.attachment == nil ? nil : $0.name
        })
        #expect(attachmentNames == ["ambient.m4a", "playlist.m4a"])
        #expect(mapped.unsupportedResources.isEmpty)
        #expect(mapped.rawOnlyDocumentCount == 0)

        let map = try #require(
            mapped.batch.items.compactMap { $0.model as? MapModel }.first
        )
        #expect(map.description.contains("Ambient audio"))
        #expect(map.description.contains("Room ambience"))
        #expect(mapped.mappings.contains { mapping in
            mapping.foundryIdentifier == ambientSound.id
                && mapping.references.contains { $0.module == .audio }
        })
        #expect(mapped.mappings.contains { mapping in
            mapping.foundryIdentifier == playlistSound.id
                && mapping.references.contains { $0.module == .audio }
        })
    }
}

private extension FoundryVTTDomainMapperMediaTests {
    enum FixtureError: Error {
        case missingResource(String)
    }

    func resource(path: String) -> FoundryPackageResource {
        FoundryPackageResource(
            logicalPath: path,
            packagePath: path,
            location: .packaged,
            byteCount: nil,
            sha256: nil
        )
    }

    func makePackage(
        resources: [FoundryPackageResource],
        collections: [FoundryDocumentCollection] = []
    ) -> FoundryVTTImportPackage {
        FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: collections,
            resources: resources,
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: collections.count,
                topLevelDocumentCount: collections.reduce(0) { $0 + $1.documents.count },
                embeddedDocumentCount: collections
                    .flatMap(\.documents)
                    .reduce(0) { $0 + $1.embeddedDocuments.count },
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )
    }

    func document(
        id: String,
        type: FoundryDocumentType,
        name: String,
        parentId: String? = nil,
        embeddedDocuments: [FoundryDocument] = [],
        rawData: FoundryJSONValue = .object([:])
    ) -> FoundryDocument {
        FoundryDocument(
            id: id,
            documentId: id,
            documentType: type,
            subtype: nil,
            name: name,
            folderId: nil,
            sort: nil,
            imagePath: nil,
            descriptionHTML: nil,
            parentId: parentId,
            embeddedDocuments: embeddedDocuments,
            references: [],
            unknownFieldNames: [],
            rawData: rawData
        )
    }

    func makeSilentPCMWave(sampleRate: UInt32 = 8_000, sampleCount: UInt32 = 2_000) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataByteCount = sampleCount * UInt32(channelCount) * bytesPerSample
        var result = Data()
        result.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(UInt32(36) + dataByteCount, to: &result)
        result.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &result)
        appendLittleEndian(UInt16(1), to: &result)
        appendLittleEndian(channelCount, to: &result)
        appendLittleEndian(sampleRate, to: &result)
        appendLittleEndian(sampleRate * UInt32(channelCount) * bytesPerSample, to: &result)
        appendLittleEndian(channelCount * UInt16(bytesPerSample), to: &result)
        appendLittleEndian(bitsPerSample, to: &result)
        result.append(contentsOf: "data".utf8)
        appendLittleEndian(dataByteCount, to: &result)
        result.append(Data(repeating: 0, count: Int(dataByteCount)))
        return result
    }

    func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

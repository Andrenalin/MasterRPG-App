// @copyright André Trettin

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_26 §10.21: what the share extension accepts as an image, and the content widget
/// snapshot the app publishes.
@Suite("Shared image downsampling")
struct SharedImageDownsamplingTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for x in stride(from: 0, to: width, by: 7) {
            context.setFillColor(red: CGFloat(x % 255) / 255, green: 0.4, blue: CGFloat((x * 3) % 255) / 255, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 7, height: height))
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func longestSide(of data: Data) throws -> Int {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height)
    }

    @Test("Empty data is not an image")
    func zeroLengthDataIsRefused() {
        #expect(throws: SharedImageDownsampling.Failure.notUsableAsImage) {
            _ = try SharedImageDownsampling.downsampledIfNeeded(Data())
        }
    }

    @Test("Bytes that are not an image are refused, however small", arguments: [
        Data("plain text".utf8),
        Data(repeating: 0, count: 4_096),
        Data([0xFF, 0xD8, 0xFF])
    ])
    func undecodableDataIsRefused(data: Data) {
        #expect(throws: SharedImageDownsampling.Failure.notUsableAsImage) {
            _ = try SharedImageDownsampling.downsampledIfNeeded(data)
        }
    }

    @Test("A small image passes through untouched")
    func smallImageIsKept() throws {
        let data = try pngData(width: 64, height: 32)

        #expect(try SharedImageDownsampling.downsampledIfNeeded(data) == data)
    }

    @Test("An image over the raw byte limit is downsampled to the pixel limit")
    func oversizedImageIsDownsampled() throws {
        let data = try pngData(width: 400, height: 200)

        let result = try SharedImageDownsampling.downsampledIfNeeded(data, maximumRawByteSize: 16, maximumPixelDimension: 64)

        #expect(result != data)
        #expect(try longestSide(of: result) <= 64)
    }
}

#if !os(tvOS)
@Suite("Content widget snapshot", .serialized)
struct ContentWidgetSnapshotTests {
    @Test("The snapshot survives an encode and decode")
    func snapshotRoundTrips() throws {
        let snapshot = ContentWidgetSnapshot(
            module: .value,
            totalCount: 2,
            items: [ContentWidgetItem(id: UUID(), name: "Aria"), ContentWidgetItem(id: UUID(), name: "Bran")]
        )

        let decoded = try JSONCoding.decoder.decode(ContentWidgetSnapshot.self, from: JSONCoding.encoder.encode(snapshot))

        #expect(decoded == snapshot)
    }

    @Test("The widget links open the module and the item")
    func linksTargetTheModuleAndItem() throws {
        let item = ContentWidgetItem(id: UUID(), name: "Aria")
        let snapshot = ContentWidgetSnapshot(module: .adventure, totalCount: 1, items: [item])

        let root = try #require(snapshot.rootURL)
        let itemUrl = try #require(snapshot.itemURL(for: item))

        #expect(root.absoluteString.hasSuffix("://\(NetworkModules.adventure.token)"))
        #expect(itemUrl.absoluteString.hasSuffix("/\(NetworkModules.adventure.token)/1/\(item.id)"))
    }

    @MainActor
    @Test("Publishing keeps four visible, named, ordinary items and counts them all",
          .enabled(if: UserDefaults.appGroupDefaults != nil))
    func publishFiltersAndCaps() {
        let module = NetworkModules.map
        defer { UserDefaults.appGroupDefaults?.removeObject(forKey: "contentWidgetSnapshot.\(module.token)") }
        let dataModel = ItemDataModel()
        var ids: [UUID] = []
        for index in 0..<6 {
            let model = SimpleModel(id: UUID(), name: "Visible \(index)")
            dataModel.itemData[model.id] = model
            ids.append(model.id)
        }
        let unnamed = SimpleModel(id: UUID(), name: "")
        dataModel.itemData[unnamed.id] = unnamed
        ids.append(unnamed.id)
        let hidden = SimpleModel(id: UUID(), name: "Hidden", displayState: DisplayStateMask.fullVisible.rawValue + 1)
        dataModel.itemData[hidden.id] = hidden
        ids.append(hidden.id)
        dataModel.resetItems(ids)

        ContentWidgetSnapshot.publish(module: module, from: dataModel)
        let loaded = ContentWidgetSnapshot.load(for: module)

        #expect(loaded.module == module)
        #expect(loaded.items.count == 4)
        #expect(loaded.totalCount == 6)
        #expect(loaded.items.map(\.name) == ["Visible 0", "Visible 1", "Visible 2", "Visible 3"])
    }

    @Test("A module that never published loads an empty snapshot")
    func neverPublishedIsEmpty() {
        let loaded = ContentWidgetSnapshot.load(for: .space)

        #expect(loaded.module == .space)
    }
}
#endif

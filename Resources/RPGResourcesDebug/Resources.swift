import Foundation

#if os(macOS)
import AppKit

public typealias RPGResourcesDebugImage = NSImage
#else
import UIKit

public typealias RPGResourcesDebugImage = UIImage
#endif

public final class ResourcesDebug {
    
    public static let bundle = Bundle.module
    
    public static let adventureTestData = "Adventure-1-TestData"
    public static let audioTestData = "Audio-2-TestData"
    public static let diceTestData = "Dice-5-TestData"
    public static let mapTestData = "Map-1-TestData"
    public static let pdfTestData = "Pdf-1-TestData"
    public static let photoTestData = "Photo-3-TestData"
    public static let spaceTestData = "Space-1-TestData"
    public static let tableTestData = "Table-16-TestData"
    public static let valueTestData = "Value-15-TestData"
    public static let valueGeneratorTestData = "Value-Generator-TestData"
    public static let weatherTestData = "Weather-4-TestData"
    
    public static let adventurePhoto = "Adventure"
    public static let paladinPhoto = "Paladin"
    public static let wizardPhoto = "Zauberer"

    public static let audioExample = "AudioExample"
    public static let pdfExample = "PdfExample"
    public static let spaceExample = "SpaceExample"

    public static let vttExample = "ds4"
    
    public static let photoPreviewNames = [
        adventurePhoto,
        paladinPhoto,
        wizardPhoto,
    ]

    @MainActor
    public static func previewImage(named name: String) -> RPGResourcesDebugImage? {
#if os(macOS)
        bundle.image(forResource: name)
#else
        RPGResourcesDebugImage(named: name, in: bundle, with: nil)
#endif
    }

    @MainActor
    public static func cachePhotoPreviewImage(named name: String) -> RPGResourcesDebugImage? {
        previewImage(named: name)
    }

    public static var audioExampleURL: URL? {
        bundle.url(forResource: audioExample, withExtension: "mp3")
    }

    public static var pdfExampleURL: URL? {
        bundle.url(forResource: pdfExample, withExtension: "pdf")
    }

    /// The PDFs in the `TestPdfs` resource folder. Folder structure is kept when the bundle keeps it,
    /// otherwise the PDFs are looked up next to the other resources, minus `PdfExample`.
    public static var testPdfUrls: [URL] {
        let nested = bundle.urls(forResourcesWithExtension: "pdf", subdirectory: "TestPdfs") ?? []
        if !nested.isEmpty {
            return nested
        }
        return (bundle.urls(forResourcesWithExtension: "pdf", subdirectory: nil) ?? [])
            .filter { $0.deletingPathExtension().lastPathComponent != pdfExample }
    }

    public static var spaceExampleURL: URL? {
        bundle.url(forResource: spaceExample, withExtension: "usdz")
    }
    
    public static var vttExampleURL: URL? {
        bundle.url(forResource: vttExample, withExtension: "zip")
    }
}

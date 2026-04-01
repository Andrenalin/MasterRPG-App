// @copyright André Trettin

import CoreRPG
import SwiftUI

enum PdfDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
#if !os(tvOS)
    case pdfExtraction(UUID)
    case pdfBlockExtraction(UUID)
#endif
}

extension PdfDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
#if !os(tvOS)
        case .pdfExtraction(let id): "pdfExtraction/\(id.uuidString)"
        case .pdfBlockExtraction(let id): "pdfBlockExtraction/\(id.uuidString)"
#endif
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
#if !os(tvOS)
        case "pdfExtraction": self = .pdfExtraction(uuid)
        case "pdfBlockExtraction": self = .pdfBlockExtraction(uuid)
#endif
        default: return nil
        }
    }
}

extension PdfDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            PdfDetailRouteDestinationView(itemId: itemId)
#if !os(tvOS)
        case .pdfExtraction(let itemId):
            SummaryAnalysisView(itemId: itemId)
        case .pdfBlockExtraction(let itemId):
            ContentExtractionView(itemId: itemId)
#endif
        }
    }
}

extension PdfDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        PdfDetailRoute.folder(detail)
    }

    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
#if !os(tvOS)
            case .pdfExtraction(let id): return id
            case .pdfBlockExtraction(let id): return id
#endif
        }
    }
}

struct PdfDetailRouteDestinationView: View {
    let itemId: UUID

    @Environment(PdfRootModel.self) private var root

    var body: some View {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.folderListController.detailInspectorModel)
            .environment(root.rootController)
    }
}

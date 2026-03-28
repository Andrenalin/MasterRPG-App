// @copyright André Trettin

import CoreRPG
import SwiftUI

enum PdfDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case pdfExtraction(UUID)
    case pdfBlockExtraction(UUID)
}

extension PdfDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .pdfExtraction(let id): "pdfExtraction/\(id.uuidString)"
        case .pdfBlockExtraction(let id): "pdfBlockExtraction/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        case "pdfExtraction": self = .pdfExtraction(uuid)
        case "pdfBlockExtraction": self = .pdfBlockExtraction(uuid)
        default: return nil
        }
    }
}

extension PdfDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            PdfDetailRouteDestinationView(itemId: itemId)
        case .pdfExtraction(let itemId):
            PdfExtractionView(itemId: itemId)
        case .pdfBlockExtraction(let itemId):
            PdfBlockExtractionView(itemId: itemId)
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
            case .pdfExtraction(let id): return id
            case .pdfBlockExtraction(let id): return id
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

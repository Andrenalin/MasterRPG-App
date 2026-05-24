// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG
import AdventureRPG
import AudioRPG
import PdfRPG
import MapRPG
import CharacterRPG
import DiceRPG
import TableRPG
import SpaceRPG
import WeatherRPG

struct AppExportController {
    let appModel: AppModel
    @MainActor let model: ValidateRepairModel

//    ExportDataModels(exportController: exportController) {
//        let url = URL.cachesDirectory.appending(path: "Export.gmz")
//        let exportedIds = exportController.exportingAll()
//        return exportController.createExport(itemIds: exportedIds, into: url)
//    }

    
    func start() async {
    }
}

struct AppExportView: View {
    let controller: AppExportController
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var converterTask: Task<Void, Never>?
    
    var body: some View {
//        VStack {
//            Text("\(controller.model.current) / \(controller.model.total)")
//                .fontDesign(.monospaced)
//                .font(.title)
//                .padding()
//            Text(controller.model.currentPhase.title)
//                .font(.subheadline)
//                .foregroundStyle(.tertiary)
//            Text("\(controller.model.currentModule == .none ? "Module not selected" : controller.model.currentModule.localizedTitle)")
//                .font(.headline)
//            Text("\(controller.model.currentSection.isEmpty ? "Section not started" : controller.model.currentSection)")
//                .foregroundStyle(.secondary)
//        }
        ExportProgressPanelView(exportController: controller.appModel.adventureRoot.exportControllable) {
            let exportIds = controller.appModel.adventureRoot.exportControllable.exportingAll()
            return controller.appModel.adventureRoot.exportControllable.export(ids: exportIds)
        }
        .presentationDetents([.height(160)])

        
//        .onAppear {
//            converterTask = Task(priority: .userInitiated) {
//                await controller.start()
//            }
//            Task {
//                _ = await converterTask?.result
//                dismiss()
//            }
//        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    converterTask?.cancel()
                    converterTask = nil
                    dismiss()
                } label: {
                    Label {
                        Text("Cancel", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

#Preview {
    AppExportView(controller: AppExportController(appModel: .preview, model: ValidateRepairModel()))
}

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

struct ValidateRepairController {
    let appModel: AppModel
    @MainActor let model: ValidateRepairModel

    func start() async {
        var counter = 0
        await counter += appModel.adventureRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.audioRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.characterRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.diceRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.mapRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.pdfRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.photoRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.spaceRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.tableRoot.itemControllable.itemDataModel.items.count
        await counter += appModel.weatherRoot.itemControllable.itemDataModel.items.count

        // Each item is visited twice: once in repairFolders, once in validateLinks
        await model.update(total: counter * 2)

        // Phase 1: repair folder/hidden state for each module
        await model.update(phase: .repairFolders)

        guard !Task.isCancelled else { return }
        await model.update(module: .photo)
        await appModel.photoRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .audio)
        await appModel.audioRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .space)
        await appModel.spaceRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .pdf)
        await appModel.pdfRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .dice)
        await appModel.diceRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .weather)
        await appModel.weatherRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .table)
        await appModel.tableRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .value)
        await appModel.characterRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .map)
        await appModel.mapRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .adventure)
        await appModel.adventureRoot.checkFolders(reportModel: model)

        // Phase 2: validate and repair cross-module links for each module
        await model.update(phase: .validateLinks)

        guard !Task.isCancelled else { return }
        await model.update(module: .photo)
        await appModel.photoRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .audio)
        await appModel.audioRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .space)
        await appModel.spaceRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .pdf)
        await appModel.pdfRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .dice)
        await appModel.diceRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .weather)
        await appModel.weatherRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .table)
        await appModel.tableRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .value)
        await appModel.characterRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .map)
        await appModel.mapRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        await model.update(module: .adventure)
        await appModel.adventureRoot.validateLinks(reportModel: model)
    }
}

struct ValidateRepairView: View {
    let controller: ValidateRepairController
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var converterTask: Task<Void, Never>?
    
    var body: some View {
        VStack {
            Text("\(controller.model.current) / \(controller.model.total)")
                .fontDesign(.monospaced)
                .font(.title)
                .padding()
            Text(controller.model.currentPhase.title)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("\(controller.model.currentModule == .none ? "Module not selected" : controller.model.currentModule.localizedTitle)")
                .font(.headline)
            Text("\(controller.model.currentSection.isEmpty ? "Section not started" : controller.model.currentSection)")
                .foregroundStyle(.secondary)
        }
        .onAppear {
            converterTask = Task(priority: .userInitiated) {
                await controller.start()
            }
            Task {
                _ = await converterTask?.result
                dismiss()
            }
        }
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
    ValidateRepairView(controller: ValidateRepairController(appModel: .preview, model: ValidateRepairModel()))
}

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
    
    @Environment(\.navigator) private var navigator
    
    @State private var converterTask: Task<Void, Never>?
    
    var body: some View {
        VStack {
            ProgressView(
                value: Double(controller.model.current),
                total: max(Double(controller.model.total), 1)
            )
            .accessibilityLabel(Text("Validation progress", bundle: .module))

            Text(
                "\(controller.model.current) / \(controller.model.total)",
                bundle: .module
            )
                .fontDesign(.monospaced)
                .font(.title)
                .padding()
            switch controller.model.currentPhase {
            case .repairFolders:
                Text("Repair Folders", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            case .validateLinks:
                Text("Validate Links", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            if controller.model.currentModule == .none {
                Text("Module not selected", bundle: .module)
                    .font(.headline)
            } else {
                Text(controller.model.currentModule.localizedTitle)
                    .font(.headline)
            }
            if controller.model.currentSection.isEmpty {
                Text("Section not started", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: controller.model.currentSection)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            converterTask = Task(priority: .userInitiated) {
                await controller.start()
            }
            Task {
                controller.appModel.saveIsDeferred = true
                defer { controller.appModel.saveIsDeferred = false }
                
                _ = await converterTask?.result
                navigator.dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    converterTask?.cancel()
                    converterTask = nil
                    navigator.dismiss()
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

// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG
import AdventureRPG
import AudioRPG
import PdfRPG
import MapRPG
import RuleRPG
import CharacterRPG
import DiceRPG
import TableRPG
import SpaceRPG
import WeatherRPG

struct ValidateRepairController {
    let appModel: AppModel
    @MainActor let model: ValidateRepairModel

    @MainActor
    func start() async {
        var counter = 0
        counter += appModel.adventureRoot.itemControllable.itemDataModel.items.count
        counter += appModel.audioRoot.itemControllable.itemDataModel.items.count
        counter += appModel.characterRoot.itemControllable.itemDataModel.items.count
        counter += appModel.diceRoot.itemControllable.itemDataModel.items.count
        counter += appModel.mapRoot.itemControllable.itemDataModel.items.count
        counter += appModel.pdfRoot.itemControllable.itemDataModel.items.count
        counter += appModel.photoRoot.itemControllable.itemDataModel.items.count
        counter += appModel.ruleRoot.itemControllable.itemDataModel.items.count
        counter += appModel.spaceRoot.itemControllable.itemDataModel.items.count
        counter += appModel.tableRoot.itemControllable.itemDataModel.items.count
        counter += appModel.weatherRoot.itemControllable.itemDataModel.items.count

        // Each item is visited twice: once in repairFolders, once in validateLinks
        model.update(total: counter * 2)

        // Phase 1: repair folder/hidden state for each module
        model.update(phase: .repairFolders)

        guard !Task.isCancelled else { return }
        model.update(module: .photo)
        await appModel.photoRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .rule)
        await appModel.ruleRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .audio)
        await appModel.audioRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .space)
        await appModel.spaceRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .pdf)
        await appModel.pdfRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .dice)
        await appModel.diceRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .weather)
        await appModel.weatherRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .table)
        await appModel.tableRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .value)
        await appModel.characterRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .map)
        await appModel.mapRoot.checkFolders(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .adventure)
        await appModel.adventureRoot.checkFolders(reportModel: model)

        // Phase 2: validate and repair cross-module links for each module
        model.update(phase: .validateLinks)

        guard !Task.isCancelled else { return }
        model.update(module: .photo)
        await appModel.photoRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .rule)
        await appModel.ruleRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .audio)
        await appModel.audioRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .space)
        await appModel.spaceRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .pdf)
        await appModel.pdfRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .dice)
        await appModel.diceRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .weather)
        await appModel.weatherRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .table)
        await appModel.tableRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .value)
        await appModel.characterRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .map)
        await appModel.mapRoot.validateLinks(reportModel: model)

        guard !Task.isCancelled else { return }
        model.update(module: .adventure)
        await appModel.adventureRoot.validateLinks(reportModel: model)
    }

    @MainActor
    func startWithExclusiveDataAccess() async -> ValidateRepairRunOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard let mutationToken = appModel.beginExclusiveDataMutation() else { return .busy }

        let saveDeferral = appModel.beginSaveDeferral()
        await start()

        // Repairs mutate the in-memory controller graph while opportunistic saves are deferred.
        // Release only this operation's deferral, then persist the complete (or cancelled partial)
        // repair once while the exclusive mutation token is still held.
        appModel.endSaveDeferral(saveDeferral)
        await appModel.save()
        appModel.endExclusiveDataMutation(mutationToken)

        return Task.isCancelled ? .cancelled : .completed
    }
}

enum ValidateRepairRunOutcome: Sendable {
    case completed
    case cancelled
    case busy
}

struct ValidateRepairView: View {
    let controller: ValidateRepairController
    
    @Environment(\.navigator) private var navigator
    
    @State private var converterTask: Task<Void, Never>?
    @State private var showBusyAlert = false
    
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
            startValidation()
        }
        .onDisappear {
            converterTask?.cancel()
        }
        .interactiveDismissDisabled(converterTask != nil)
        .alert(Text("Validation Unavailable", bundle: .module), isPresented: $showBusyAlert) {
            Button {
                startValidation()
            } label: {
                Text("Retry", bundle: .module)
            }
            Button(role: .cancel) {
                navigator.dismiss()
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("Another import or repair operation is currently changing RPG data.", bundle: .module)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    cancelAndDismiss()
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

    private func startValidation() {
        guard converterTask == nil else { return }

        converterTask = Task(priority: .userInitiated) {
            let result = await controller.startWithExclusiveDataAccess()
            converterTask = nil

            switch result {
            case .completed:
                navigator.dismiss()
            case .cancelled:
                break
            case .busy:
                showBusyAlert = true
            }
        }
    }

    private func cancelAndDismiss() {
        guard let task = converterTask else {
            navigator.dismiss()
            return
        }

        task.cancel()
        Task { @MainActor in
            await task.value
            navigator.dismiss()
        }
    }
}

#Preview {
    ValidateRepairView(controller: ValidateRepairController(appModel: .preview, model: ValidateRepairModel()))
}

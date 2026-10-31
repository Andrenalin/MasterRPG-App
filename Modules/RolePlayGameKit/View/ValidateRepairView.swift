// @copyright André Trettin

import CoreRPG
import os.log
import SwiftUI

struct ValidateRepairController {
    let appModel: AppModel
    @MainActor let model: ValidateRepairModel

    @MainActor
    func start() async {
        let steps = appModel.moduleFolderRepairSteps
        let counter = steps.reduce(into: 0) { total, step in
            total += step.root.itemControllable.itemDataModel.items.count
        }

        // Each item is visited twice: once in repairFolders, once in validateLinks
        model.update(total: counter * 2)

        let clock = ContinuousClock()

        // Phase 1: repair folder/hidden state for each module
        model.update(phase: .repairFolders)
        for step in steps {
            guard !Task.isCancelled else { return }
            model.update(module: step.module)
            let started = clock.now
            await step.root.checkFolders(reportModel: model)
            Logger.validateRepair.info("repair folders \(String(describing: step.module), privacy: .public) took \(started.duration(to: clock.now).formatted(), privacy: .public)")
        }

        // Phase 2: validate and repair cross-module links for each module
        model.update(phase: .validateLinks)
        for step in steps {
            guard !Task.isCancelled else { return }
            model.update(module: step.module)
            let started = clock.now
            await step.root.validateLinks(reportModel: model)
            Logger.validateRepair.info("validate links \(String(describing: step.module), privacy: .public) took \(started.duration(to: clock.now).formatted(), privacy: .public)")
        }
    }

    @MainActor
    func startWithExclusiveDataAccess() async -> ValidateRepairRunOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard let mutationToken = appModel.beginExclusiveDataMutation() else { return .busy }

        let saveDeferral = appModel.beginSaveDeferral()
        let clock = ContinuousClock()
        let started = clock.now
        await start()
        Logger.validateRepair.info("repair finished after \(started.duration(to: clock.now).formatted(), privacy: .public), cancelled \(Task.isCancelled, privacy: .public)")

        // Repairs mutate the in-memory controller graph while opportunistic saves are deferred.
        // Release only this operation's deferral, then persist the complete (or cancelled partial)
        // repair once while the exclusive mutation token is still held.
        model.update(phase: .saveChanges)
        let saveStarted = clock.now
        appModel.endSaveDeferral(saveDeferral)
        await appModel.save()
        Logger.validateRepair.info("consolidated save took \(saveStarted.duration(to: clock.now).formatted(), privacy: .public)")
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
    @Environment(\.dismiss) private var dismiss
    
    @State private var converterTask: Task<Void, Never>?
    @State private var showBusyAlert = false
    @State private var isShown = false
    
    var body: some View {
        VStack {
            if controller.model.currentPhase == .saveChanges {
                ProgressView()
            } else {
                ProgressView(
                    value: Double(controller.model.current),
                    total: max(Double(controller.model.total), 1)
                )
                .accessibilityLabel(Text("Validation progress", bundle: .module))
            }

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
            case .saveChanges:
                Text("Saving Changes", bundle: .module)
                    .font(.headline)
            }
            if controller.model.currentPhase != .saveChanges {
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
        }
        .scenePadding()
#if os(macOS)
        // A macOS sheet is as small as its content: without a size the progress hugs the edges.
        .frame(minWidth: 420, minHeight: 240)
#endif
        .onAppear {
            isShown = true
            startValidation()
        }
        .onDisappear {
            isShown = false
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
                close()
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
            Logger.validateRepair.info("validation ended: \(String(describing: result), privacy: .public)")

            switch result {
            case .completed:
                close()
            case .cancelled:
                break
            case .busy:
                showBusyAlert = true
            }
        }
    }

    /// Cancel closes the sheet right away. The run notices the cancellation at its next step, then
    /// saves what it repaired so far and releases the data lock on its own; waiting for that here
    /// kept the sheet open for as long as the current module (and the final save) took.
    private func cancelAndDismiss() {
        Logger.validateRepair.info("cancel tapped, running: \(converterTask != nil, privacy: .public)")
        converterTask?.cancel()
        close()
    }

    private func close() {
        let dismissed = navigator.dismiss()
        Logger.validateRepair.info("close: navigator.dismiss() returned \(dismissed, privacy: .public)")
        guard dismissed else {
            dismiss()
            return
        }
        // The navigator only hands the request on to SwiftUI. If the sheet is still up well after
        // its dismiss animation, close it through the environment as well.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard isShown else { return }
            Logger.validateRepair.warning("close: sheet still shown after navigator.dismiss(), dismissing through the environment")
            dismiss()
        }
    }
}

#Preview {
    ValidateRepairView(controller: ValidateRepairController(appModel: .preview, model: ValidateRepairModel()))
}

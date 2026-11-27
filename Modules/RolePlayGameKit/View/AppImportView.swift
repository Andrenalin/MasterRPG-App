// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct AppImportView: View {
    private enum ImportSection: Hashable {
        case masterRPG
        case foundry
    }

    let appModel: AppModel
    @State private var selectedSection = ImportSection.masterRPG
    @State private var foundryModel = FoundryImportModel()
        
    var body: some View {
        VStack {
            Picker(
                selection: Binding(
                    get: { selectedSection },
                    set: { newValue in
                        guard !appModel.isExclusiveDataMutationActive
                                || newValue == selectedSection else { return }
                        selectedSection = newValue
                    }
                )
            ) {
                Label {
                    Text("MasterRPG", bundle: .module)
                } icon: {
                    Image(systemName: "archivebox")
                }
                .tag(ImportSection.masterRPG)

                Label {
                    Text("Foundry VTT", bundle: .module)
                } icon: {
                    Image(systemName: "square.grid.3x3.square")
                }
                .tag(ImportSection.foundry)
            } label: {
                Text("Import Source", bundle: .module)
            }
            .pickerStyle(.segmented)
            .disabled(appModel.isExclusiveDataMutationActive || foundryModel.isWorking)
            .padding()

            switch selectedSection {
            case .masterRPG:
                ImportProgressPanelView(
                    rootManager: appModel.root,
                    urlProvider: appModel,
                    importController: importController,
                    initialURL: appModel.pendingImportUrl,
                    endDataMutationHandler: { [appModel] in
                        await appModel.save()
                    },
                    // Capture only the app model: the import session keeps the token and can
                    // release it after this view is gone. See CODE_AUDIT_Folder §3.16.
                    beginSaveDeferral: { [appModel] in
                        appModel.beginSaveDeferral()
                    },
                    endSaveDeferral: { [appModel] token in
                        appModel.endSaveDeferral(token)
                    }
                )
            case .foundry:
                FoundryImportView(
                    appModel: appModel,
                    isSelected: true,
                    model: foundryModel
                )
            }
        }
        .onAppear {
            selectPendingImportWhenAvailable()
        }
        .onChange(of: appModel.pendingImportUrl) { _, newValue in
            guard newValue != nil else { return }
            selectPendingImportWhenAvailable()
        }
        .onChange(of: appModel.pendingVTTImportUrl) { _, newValue in
            guard newValue != nil else { return }
            selectPendingImportWhenAvailable()
        }
        .onChange(of: appModel.isExclusiveDataMutationActive) { _, isActive in
            guard !isActive else { return }
            appModel.refreshTipEligibility()
            selectPendingImportWhenAvailable()
        }
        .onDisappear {
            appModel.finishImportPresentation()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .moduleTint(.setting)
        .themedSurface()
    }
    
    var importController: ImportControllable {
        appModel.adventureRoot.importControllable
    }

    private func selectPendingImportWhenAvailable() {
        guard !appModel.isExclusiveDataMutationActive else { return }

        if appModel.pendingVTTImportUrl != nil {
            selectedSection = .foundry
        } else if appModel.pendingImportUrl != nil {
            selectedSection = .masterRPG
        }
    }
}

#Preview("Midnight theme") {
    AppImportView(appModel: .preview)
        .appTheme(
            AppThemeCatalog.resolve(
                .midnight,
                colorScheme: .dark,
                contrast: .standard
            )
        )
        .preferredColorScheme(.dark)
}

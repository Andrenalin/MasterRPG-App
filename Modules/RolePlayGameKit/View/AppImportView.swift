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
    @State private var nativeImportSaveDeferral: UUID?
    @State private var selectedSection = ImportSection.masterRPG
        
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
            .disabled(appModel.isExclusiveDataMutationActive)
            .padding()

            switch selectedSection {
            case .masterRPG:
                ImportProgressPanelView(
                    rootManager: appModel.root,
                    urlProvider: appModel,
                    importController: importController,
                    initialURL: appModel.pendingImportURL,
                    endDataMutationHandler: {
                        await appModel.save()
                    },
                    saveDeferredHandler: { value in
                        if value, nativeImportSaveDeferral == nil {
                            nativeImportSaveDeferral = appModel.beginSaveDeferral()
                        } else if !value, let token = nativeImportSaveDeferral {
                            appModel.endSaveDeferral(token)
                            nativeImportSaveDeferral = nil
                        }
                    }
                )
            case .foundry:
                FoundryImportView(
                    appModel: appModel,
                    isSelected: true
                )
            }
        }
        .onAppear {
            selectPendingImportWhenAvailable()
        }
        .onChange(of: appModel.pendingImportURL) { _, newValue in
            guard newValue != nil else { return }
            selectPendingImportWhenAvailable()
        }
        .onChange(of: appModel.pendingVTTImportURL) { _, newValue in
            guard newValue != nil else { return }
            selectPendingImportWhenAvailable()
        }
        .onChange(of: appModel.isExclusiveDataMutationActive) { _, isActive in
            guard !isActive else { return }
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

        if appModel.pendingVTTImportURL != nil {
            selectedSection = .foundry
        } else if appModel.pendingImportURL != nil {
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

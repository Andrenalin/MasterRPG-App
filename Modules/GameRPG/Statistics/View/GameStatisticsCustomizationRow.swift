// @copyright André Trettin

import SwiftUI

struct GameStatisticsCustomizationRow: View {
    let section: GameStatisticsSection
    @Bindable var model: GameStatisticsModel

    var body: some View {
        LabeledContent {
            HStack {
                Toggle(section.title, isOn: sectionVisibilityBinding)
                    .labelsHidden()
#if os(macOS)
                    .controlSize(.mini)
#endif

#if os(tvOS)
                Menu {
                    Button {
                        model.moveSection(section, offset: -1)
                    } label: {
                        Label {
                            Text("Move Up", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.up")
                        }
                    }
                    .disabled(model.configuration.sectionOrder.first == section)

                    Button {
                        model.moveSection(section, offset: 1)
                    } label: {
                        Label {
                            Text("Move Down", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.down")
                        }
                    }
                    .disabled(model.configuration.sectionOrder.last == section)
                } label: {
                    Label {
                        Text("Reorder", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
#endif
            }
        } label: {
            Label(section.title, systemImage: section.systemImage)
        }
    }

    private var sectionVisibilityBinding: Binding<Bool> {
        Binding(
            get: { !model.configuration.hiddenSections.contains(section) },
            set: { model.setSection(section, isVisible: $0) }
        )
    }
}

#Preview {
    List {
        GameStatisticsCustomizationRow(section: .activity, model: .previewFixture())
    }
}

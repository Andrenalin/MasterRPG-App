// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct WeatherEditor: View {
    let model: WeatherDataModel

    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        Section {
            root.viewController.photoSelection(root: root, selectionModel: root.editController.selectionPhoto)
                .onChange(of: root.editController.selectionPhoto.selection) {
                    withAnimation { root.editController.add(photoId: root.editController.selectionPhoto.itemId, model: model) }
                }
                .onChange(of: model.photoId, initial: true) {
                    withAnimation { root.editController.selectionPhoto.resetSelection(itemId: model.photoId) }
                }
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Photo", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        Section {
            timeEditorView
            
            cloudsEditorView
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Weather", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        
        Section {
            precipitationEditorView
            rainIntensityEditorView
            rainAngleEditorView
            rainDirectionEditorView
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Storm", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        
        Section {
            lightningFrequencyEditorView
            lightningMaxBoltsEditorView
            lightningForkEditorView
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Thunder", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private extension WeatherEditor {
    @ViewBuilder
    var dropItemView: some View {
        DropItemArea {
            VStack {
                Text("Drop \(root.module.title)", bundle: .module)

                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
            .padding(.horizontal, 12)
            .frame(height: 128)
        } dropAction: { links in
            //addLinks(links: links)
            return true
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.accentColor.tertiary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.secondary, lineWidth: 2)
        }
        .padding(1)
    }

    @ViewBuilder
    var timeEditorView: some View {
        @Bindable var model = model

        LabeledContent {
#if os(tvOS)
            Text(formattedTime)
#else
            Slider(value: $model.time)
#endif
        } label: {
            Text("Time", bundle: .module)
        }
    }

    @ViewBuilder
    var cloudsEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
            Picker("Thickness", selection: $model.cloudThickness) {
                ForEach(Cloud.Thickness.allCases, id: \.self) { thickness in
                    Text(thickness.localizedTitle, bundle: .module)
                }
            }
            .pickerStyle(.automatic)
            .labelsHidden()
        } label: {
            Text("Clouds", bundle: .module)
        }
    }

    @ViewBuilder
    var precipitationEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
            Picker("Precipitation", selection: $model.stormType) {
                ForEach(Storm.Contents.allCases, id: \.self) { stormType in
                    Text(stormType.localizedTitle, bundle: .module)
                }
            }
            .pickerStyle(.automatic)
            .labelsHidden()
        } label: {
            Text("Precipitation", bundle: .module)
        }
    }

    @ViewBuilder
    var rainIntensityEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.rainIntensity)")
#else
            Slider(value: $model.rainIntensity, in: 0 ... 1000)
#endif
        } label: {
            Text("Intensity", bundle: .module)
        }
    }

    @ViewBuilder
    var rainAngleEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.rainAngle)")
#else
            Slider(value: $model.rainAngle, in: -90 ... 90)
#endif
        } label: {
            Text("Angle", bundle: .module)
        }
    }

    @ViewBuilder
    var rainDirectionEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
            Toggle(isOn: $model.rainDirection) {
                Label("", systemImage: model.rainDirection ? "chevron.right" : "chevron.left")
            }
            .tint(Color.accentColor)
        } label: {
            Text("Direction", bundle: .module)
        }
    }

    @ViewBuilder
    var lightningFrequencyEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningFrequency)")
#else
            Slider(value: $model.lightningFrequency, in: 0 ... 100)
#endif
        } label: {
            Text("Frequency", bundle: .module)
        }
    }

    @ViewBuilder
    var lightningMaxBoltsEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningMaxBolts)")
#else
            Slider(value: $model.lightningMaxBolts, in: 0 ... 10)
#endif
        } label: {
            Text("Max Bolts", bundle: .module)
        }
    }

    @ViewBuilder
    var lightningForkEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningForkProbability)")
#else
            Slider(value: $model.lightningForkProbability, in: 0 ... 100)
#endif
        } label: {
            Text("Fork %", bundle: .module)
        }
    }

    private var formattedTime: String {
        let start = Calendar.current.startOfDay(for: Date.now)
        let advanced = start.addingTimeInterval(model.time * 24 * 60 * 60)
        return advanced.formatted(date: .omitted, time: .shortened)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [WeatherDataModel]

    WeatherEditor(model: models.first(where: { $0.itemId == MockData.previewId })!)
}

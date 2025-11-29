// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GeneratorEditor: View {
    init(generatorController: GeneratorController, dismiss: @escaping (Bool) -> Void) {
        _name = State(initialValue: generatorController.tableName)
        _value = State(initialValue: generatorController.entryValue)
        _values = State(initialValue: generatorController.values)
        self.generatorController = generatorController
        self.dismiss = dismiss
    }

    let generatorController: GeneratorController
    let dismiss: (Bool) -> Void

    enum FocusedField {
        case name
        case value
        case cancel
        case create
    }

    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.valueActions) private var valueActions

    @FocusState private var inputFocus: FocusedField?

    @State private var name: String
    @State private var isEntryName = false

    @State private var value: String
    @State private var isEntryOnly = true
    @State private var values: [ActivatedValue]

    var body: some View {
        VStack {
            nameView

            Divider()

            valueView

            Divider()

            actionButtonView
                .padding(.bottom)
        }
        .animation(.bouncy, value: isEntryOnly)
        .padding()
        .frame(minWidth: 200, maxWidth: 400, minHeight: 150, alignment: .center)
        .background(color)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 4)
#if os(macOS)
        .defaultFocus($inputFocus, .name)
#else
        .onAppear {
            name = generatorController.tableName
            value = generatorController.entryValue
            values = generatorController.values
            isEntryOnly = values.count < 2
            Task { @MainActor in
                try await Task.sleep(for: .seconds(0.5))
                withAnimation {
                    inputFocus = .name
                }
            }
        }
#endif
    }

    private var color: Color {
#if os(macOS)
        Color(nsColor: NSColor.windowBackgroundColor)
#elseif !os(tvOS)
        Color(uiColor: UIColor.systemBackground)
#else
        Color(uiColor: UIColor.black)
#endif
    }

    private var nameView: some View {
        VStack {
            HStack {
                Text("Enter a name", bundle: .module)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: $isEntryName) {
                    Text("Use Entry")
                }
            }
            .foregroundStyle(.primary)
            .font(.headline)
            .padding(.top)

            TextField(text: $name) {
                Text("New name for the item", bundle: .module)
            }
            .foregroundStyle(.primary)
#if os(iOS) || os(visionOS)
            .autocapitalization(.sentences)
            .textContentType(.name)
#endif
            .disableAutocorrection(true)
            .focused($inputFocus, equals: .name)
            .labelsHidden()
            .submitLabel(.next)
            .textFieldStyle(.plain)
            .rowEditColor(backgroundColor: .secondary)
            .onSubmit(onSubmitCheck)
            .onChange(of: isEntryName) {
                withAnimation {
                    name = isEntryName ? generatorController.entryName : generatorController.tableName
                }
            }
        }
    }

    private var valueView: some View {
        VStack {
            HStack {
                Text("Enter a value", bundle: .module)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: $isEntryOnly) {
                    Text("As Entry")
                }
            }
            .foregroundStyle(.primary)
            .font(.headline)

            Group {
                if isEntryOnly {
                    valueTextField(value: $value)
                } else {
                    ScrollView(.vertical) {
                        VStack {
                            ForEach(values) { value in
                                HStack {
                                    Toggle(isOn: activeBinding(for: value.id)) {
                                        Text("Use")
                                    }
                                    .labelsHidden()

                                    valueTextField(value: nameBinding(for: value.id))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding {
            if let index = values.firstIndex(where: { id == $0.id }) {
                return values[index].name
            } else {
                return ""
            }
        } set: {
            if let index = values.firstIndex(where: { id == $0.id }) {
                values[index].name = $0
            }
        }
    }

    private func activeBinding(for id: UUID) -> Binding<Bool> {
        Binding {
            if let index = values.firstIndex(where: { id == $0.id }) {
                return values[index].activated
            } else {
                return false
            }
        } set: {
            if let index = values.firstIndex(where: { id == $0.id }) {
                values[index].activated = $0
            }
        }
    }
    private func valueTextField(value: Binding<String>) -> some View {
        TextField(text: value) {
            Text("New value for the item", bundle: .module)
        }
        .foregroundStyle(.primary)
#if os(iOS) || os(visionOS)
        .autocapitalization(.sentences)
        .textContentType(.name)
#endif
        .disableAutocorrection(true)
        .focused($inputFocus, equals: .value)
        .labelsHidden()
        .submitLabel((name.isEmpty || value.wrappedValue.isEmpty) ? .next : .continue)
        .textFieldStyle(.plain)
        .rowEditColor(backgroundColor: .secondary)
        .onSubmit(onSubmitCheck)
    }

    private func onSubmitCheck() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputFocus = .name
        } else if inputFocus == .name || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputFocus = .value
        } else {
#if os(macOS)
            inputFocus = .create
#else
            inputFocus = nil
#endif
        }
    }

    private var actionButtonView: some View {
        HStack {
            Button {
                inputFocus = nil
                Task { @MainActor in
                    try await Task.sleep(for: .seconds(0.05))
                    withAnimation { dismiss(false) }
                }
            } label: {
                Text("Cancel", bundle: .module)
            }

            Spacer()

            Button {
                save()
                inputFocus = nil
                Task { @MainActor in
                    try await Task.sleep(for: .seconds(0.05))
                    withAnimation { dismiss(true) }
                }
            } label: {
                Text("Create", bundle: .module)
            }
            .focused($inputFocus, equals: .create)
            .disabled(name.isEmpty || value.isEmpty)
        }
        .buttonStyle(.bordered)
        .tint(Color.accentColor)
    }

    func save() {
        generatorController.save(name: name, value: value, isEntryOnly: isEntryOnly, values: values, valueActions: valueActions, networkActions: showGame ? networkActions : nil)
    }
}

#Preview {
    GeneratorEditor(generatorController: .previewWithData) { _ in
        print("")
    }
}

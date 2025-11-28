// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct GeneratorEditor: View {
    init(generatorController: GeneratorController, dismiss: @escaping (Bool) -> Void) {
        _name = State(initialValue: generatorController.name)
        self.generatorController = generatorController
        self.dismiss = dismiss
    }

    let generatorController: GeneratorController
    let dismiss: (Bool) -> Void

    enum FocusedField {
        case name
        case cancel
        case create
    }

    @FocusState private var inputFocus: FocusedField?

    @State private var name: String = ""

    var body: some View {
        VStack {
            nameView

            Divider()

            actionButtonView
                .padding(.bottom)
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 400, minHeight: 150, alignment: .center)
        .background(color)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 4)
#if os(macOS)
        .defaultFocus($inputFocus, .name)
#else
        .onAppear {
            name = generatorController.name
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
            Text("Enter a name", bundle: .module)
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
        }
    }

    private func onSubmitCheck() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputFocus = .name
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
            .disabled(name.isEmpty)
        }
        .buttonStyle(.bordered)
        .tint(Color.accentColor)
    }

    func save() {
        Task {
            await generatorController.createValue(name: name)
        }
    }
}

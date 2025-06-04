// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public class TextFieldModel {
    public init(text: String = "") {
        self.text = text
    }

    public var text: String
}

public struct TextFieldModelEditor: View {
    public init(editController: any EditControllable, model: TextFieldModel, title: LocalizedStringKey? = "Name", prompt: LocalizedStringKey = "Enter a name", bundle: Bundle?, focusListner: Bool = false, onSubmitHandler: (() -> Void)? = nil) {
        self.editController = editController
        self.model = model
        self.title = title
        self.prompt = prompt
        self.bundle = bundle
        self.focusListner = focusListner
        self.onSubmitHandler = onSubmitHandler
    }

    let editController: any EditControllable
    let model: TextFieldModel
    let title: LocalizedStringKey?
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let focusListner: Bool
    let onSubmitHandler: (() -> Void)?

    @FocusState private var focusState: Bool

    public var body: some View {
        let _ = Self._printChanges()
        LabeledContent {
            textField(with: title ?? "")
        } label: {
            Text(title ?? "", bundle: bundle)
        }
        .applyIf(title == nil) { content in
            content.labelsHidden()
        }
        .onChange(of: editController.editorModel.activateFocus, initial: true) {
            guard focusListner && editController.editorModel.activateFocus else { return }
            withAnimation { focusState = true }
            editController.editorModel.activateFocus = false
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            onSubmit()
        }
    }

    @ViewBuilder
    func textField(with name: LocalizedStringKey) -> some View {
        @Bindable var model = model
        TextField(text: $model.text, prompt: Text(prompt, bundle: bundle), axis: .vertical) {
            Text(name, bundle: bundle)
        }
        .lineLimit(5)
#if os(iOS) || os(visionOS)
        .autocapitalization(.none)
        .textContentType(.name)
#endif
        .disableAutocorrection(true)
        .labelsHidden()
        .submitLabel(.return)
        .focused($focusState)
        .onSubmit {
            onSubmit()
        }
    }

    private func onSubmit() {
        model.text <=> model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let onSubmitHandler {
            onSubmitHandler()
        } else {
            editController.save(with: String(localized: "Typing").localizedString)
        }
    }
}

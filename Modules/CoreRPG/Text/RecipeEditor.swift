// @copyright André Trettin

import SwiftUI

@available(iOS 26.0, *)
struct DescriptionLinkEditor: View {
    @State private var text = AttributedString("Hello")
    @State private var selection = AttributedTextSelection()

    var body: some View {
        VStack {
            Text(text)
            Divider()
            Text("Selected: \(text[selection])")
            Divider()
            TextEditor(text: $text, selection: $selection)
        }
    }

//    private var newIngredientSuggestion: IngredientSuggestion {
//        let name = text[selection.indices(in: text)] // build error
//
//        return IngredientSuggestion(
//            suggestedName: AttributedString())
//    }
}


    //            .preference(key: NewIngredientPreferenceKey.self, value: newIngredientSuggestion)


    //            TextEditor(text: $content.text, selection: $content.selection)
    //                .toolbar {
    //                    ToolbarItemGroup(placement: .topBarTrailing) {
    //                        Picker("Paragraph Format", selection: $content.paragraphFormat) {
    //                            Text("Section")
    //                                .tag(ParagraphFormat.section)
    //                            Text("Body")
    //                                .tag(ParagraphFormat.body)
    //                        }
    //                        .pickerStyle(.inline)
    //                        .fixedSize()
    //                    }
    //                }


//@MainActor
//@Observable
//final class EditableRecipeText: Identifiable {
//    let model: Recipe
//
//    var text: AttributedString {
//        get {
//            // SwiftData periodically saves the recipe while a person types, and
//            // checks for changes to the model from other sources, like changes
//            // from cloud storage. The editor needs to handle situations where
//            // the text in the editor and the text in the SwiftData model
//            // diverge. This code just chooses the newer version of the two. A
//            // real app might compute the difference between the two variants,
//            // attempt to merge them, and ask the user to resolve conflicts
//            // where necessary.
//            if lastModified >= model.lastModified {
//                editedText
//            } else {
//                model.content
//            }
//        }
//        set {
//            model.content = newValue
//            editedText = newValue
//        }
//    }
//
//    private var editedText: AttributedString {
//        didSet {
//            lastModified = .now
//        }
//    }
//    private var lastModified: Date
//
//    var selection: AttributedTextSelection
//
//    init(recipe: Recipe) {
//        self.model = recipe
//        self.selection = AttributedTextSelection()
//        self.editedText = model.content
//        self.lastModified = model.lastModified
//    }
//}

#Preview {
    if #available(iOS 26.0, *) {
        DescriptionLinkEditor()
    }
}

// @copyright André Trettin

import SwiftUI

struct LinkNameAttributes: CodableAttributedStringKey {
    typealias Value = LinkDataModel.ID

    static let name = "MasterRPG.LinkNameAttributes"
}

extension AttributeScopes {
    struct CustomAttributes: AttributeScope {
        let linkName: LinkNameAttributes
    }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.CustomAttributes, T>
    ) -> T {
        self[T.self]
    }
}

struct LinkFormattingDefinition: AttributedTextFormattingDefinition {
    struct Scope: AttributeScope {
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
        let adaptiveImageGlyph: AttributeScopes.SwiftUIAttributes.AdaptiveImageGlyphAttribute
        let linkName: LinkNameAttributes
    }

    var body: some AttributedTextFormattingDefinition<Scope> {
        LinksAreWhiteBlue()
    }
}

struct LinksAreWhiteBlue: AttributedTextValueConstraint {
    typealias Scope = LinkFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    func constrain(_ container: inout Attributes) {
        if container.linkName != nil {
            container.foregroundColor = .blue
//            container.backgroundColor = .blue
        }
    }
}

struct DescriptionLinkEditor: View {
    @State private var text = AttributedString("Hello")
    @State private var selection = AttributedTextSelection()

    var body: some View {
        VStack {
            Text(text)
            Divider()
            Button {

            } label: {
                Text("Selected: \(text[selection])")
            }
            Divider()
            TextEditor(text: $text, selection: $selection)
                .attributedTextFormattingDefinition(LinkFormattingDefinition())
        }
    }
}

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
    DescriptionLinkEditor()
}

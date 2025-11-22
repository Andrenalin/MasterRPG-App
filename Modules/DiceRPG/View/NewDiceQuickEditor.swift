//// @copyright André Trettin
//
//import CoreRPG
//import SwiftUI
//
//struct DiceQuickEditor: View {
//    init(itemId: UUID, action: @escaping (Int) async -> Void) {
//        self.itemId = itemId
//        self.action = action
//    }
//
//    let itemId: UUID
//    let action: (Int) async -> Void
//
//    @Environment(DiceRootModel.self) private var root
//
//    @State private var value: String = ""
//    @FocusState private var isFocused: Bool
//
//    private var valueIntBinding: Binding<Int> {
//        Binding {
//            Int(value) ?? 0
//        } set: { newValue in
//            value = String("\(newValue)")
//        }
//    }
//
//    var body: some View {
//        VStack {
//            VStack {
//                rowMinusButtonsView
//                rowPlusButtonsView
//            }
//            .rowEditColor()
//
//            HStack {
//                TextField(text: $value) {
//                    Text("Compare Value", bundle: .module)
//                }
//                .numericInput($value, includeDecimal: false)
//                .textFieldStyle(.plain)
//                .labelsHidden()
//                .padding(4)
//                .focused($isFocused)
//                .submitLabel(.done)
//                .onSubmit {
//                    Task {
//                        await action(Int(value) ?? 0)
//                    }
//                }
//
//                Button {
//                    Task {
//                        await action(Int(value) ?? 0)
//                    }
//                } label: {
//                    Image(systemName: "return")
//                }
//                .buttonStyle(.bordered)
//            }
//            .rowEditColor()
//        }
//        .rowEditColor(backgroundColor: .blue)
//        .frame(width: valueFor(iOS: 265, macOS: 265, tvOS: 265, visionOS: 325))
////        .onChange(of: root.gameController.gameItem(for: itemId)?.compareValue, initial: true) {
////            value = String("\(Int(root.gameController.gameItem(for: itemId)?.compareValue))")
////        }
//        .onAppear {
//#if !os(visionOS)
//            isFocused = true
//#endif
//        }
//    }
//
//    private var rowMinusButtonsView: some View {
//        HStack {
//            ForEach([10, 5, 2, 1], id: \.self) { value in
//                QuickEditorButtonView(number: valueIntBinding, value: value, title: "\(value)", isAddition: false)
//            }
//        }
//    }
//
//    private var rowPlusButtonsView: some View {
//        HStack {
//            ForEach([1, 2, 5, 10], id: \.self) { value in
//                QuickEditorButtonView(number: valueIntBinding, value: value, title: "\(value)", isAddition: true)
//            }
//        }
//    }
//}
//
//#Preview(traits: .mockData) {
//    DiceQuickEditor(itemId: MockData.previewId) { value in
//        print(value)
//    }
//}

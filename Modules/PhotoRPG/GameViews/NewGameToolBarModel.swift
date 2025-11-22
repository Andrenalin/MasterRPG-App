//// @copyright André Trettin
//
//import SwiftUI
//
//@Observable
//final class GameToolBarModel {
//    var degrees: Double = 0
//    var showToolBar: Bool = true
//}
//
//struct GameToolBar: View {
//    let model: GameToolBarModel
//    let hideCloseButton: Bool
//    let dismiss: (() -> Void)?
//        
//    var body: some View {
//        HStack {
//            Button {
//                withAnimation { model.degrees += 90 }
//            } label: {
//                Image(systemName: "rotate.right")
//                    .rotationEffect(Angle(degrees: model.degrees))
//                    .frame(height: 24)
//            }
//            
//            Spacer()
//
//            Button {
//                dismiss?()
//            } label: {
//                Image(systemName: "xmark.circle")
//                    .frame(height: 24)
//            }
//            .opacity(hideCloseButton ? 0 : 1)
//        }
//        .buttonStyle(.borderedProminent)
//        .opacity(model.showToolBar ? 1 : 0)
//    }
//}
//
//#Preview {
//    GameToolBar(model: GameToolBarModel(), hideCloseButton: false) {}
//}

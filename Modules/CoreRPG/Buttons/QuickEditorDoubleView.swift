// @copyright André Trettin

import SwiftUI

#Preview {
    @Previewable @State var number = 12.5
    QuickEditorDoubleView(number: $number)
        .padding()
}

struct QuickEditorDoubleView: View {
    @Binding var number: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                rowMinusButtonsView
                rowPlusButtonsView
                    .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var rowMinusButtonsView: some View {
        HStack(spacing: 12) {
            ForEach([10.0, 5.0, 2.0, 1.0], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value.formatted(.number))", isAddition: false)
            }
        }
    }

    private var rowPlusButtonsView: some View {
        HStack(spacing: 12) {
            ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value.formatted(.number))", isAddition: true)
            }
        }
    }
}

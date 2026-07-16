// @copyright André Trettin

import SwiftUI

struct LogMessageTransportView: View {
    let transport: SharePlayTransportLog

    var body: some View {
        HStack(spacing: 4) {
            Text("Message:", bundle: .module)
            if let journal = transport.journal {
                Text("Journal", bundle: .module)
                JournalTransportStateImage(state: journal.state)
                Text(Int64(journal.byteCount), format: .byteCount(style: .file))
            }
            if transport.journal != nil, transport.chunked != nil {
                Text(verbatim: "/")
            }
            if let chunked = transport.chunked {
                Text("Chunked \(chunked.count)", bundle: .module)
                Text(Int64(chunked.byteCount), format: .byteCount(style: .file))
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

#Preview {
    LogMessageTransportView(
        transport: SharePlayTransportLog(
            journal: .init(byteCount: 4_096, state: .succeeded),
            chunked: .init(count: 3, byteCount: 12_288)
        )
    )
}

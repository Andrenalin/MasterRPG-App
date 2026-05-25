// @copyright André Trettin

import Foundation
import os.log
import Observation

@MainActor @Observable
public final class ItemDataExportModel {
    public init() {}

    public var exportedItems: Int = 0
    public var totalExportingItems: Int = 0
    public var isExportRunning: Bool = false
    
    public var exportFileData: Bool = true
}

public enum ItemDataExportableError: Error {
    case openError
    case streamError
    case writeError
}

enum ExportDataToken: Int {
    case version_2024 = 1
    case counter = 8_096
    case item = 10_000
    case file = 10_001
}

struct GmzFileHeader {
    let counter: Int
    let token: Int
    let version: Int
}

struct ExportStream {
    let id: UUID
    let data: Data
}

actor ExportIndexModel {
    init(index: Int = 0) {
        self.index = index
    }
    
    var index: Int = 0
    
    func update(index: Int) {
        self.index = index
    }
}

extension OutputStream {
    func append(fileHeader: GmzFileHeader) throws {
        try append(counter: fileHeader.counter)
        try append(counter: fileHeader.token)
        try append(counter: fileHeader.version)
    }

    func append(counter: Int, token: Int) throws {
        try append(counter: counter)
        try append(counter: token)
    }

    func append(counter: Int) throws {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        for i in 0...3 {
            readBuffer[i] = UInt8((UInt32(counter) >> (i * 8)) & UInt32(0xFF))
        }
        let written = write(&readBuffer, maxLength: readBuffer.count)
        guard written == readBuffer.count else {
            throw ItemDataExportableError.writeError
        }
    }

    func write(data: Data) throws {
        var remaining = data[...]
        while !remaining.isEmpty {
            let bytesWritten = remaining.withUnsafeBytes { buf in
                write(buf.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: buf.count)
            }
            guard bytesWritten >= 0 else { throw ItemDataExportableError.streamError }
            remaining = remaining.dropFirst(bytesWritten)
        }
    }
}

// @copyright André Trettin

import Foundation

// MARK: - Binary Stream Reading

extension InputStream {
    func readHeader() throws -> GmzFileHeader {
        GmzFileHeader(counter: try readCounter(), token: try readCounter(), version: try readCounter())
    }

    /// Reads the next module header while treating a clean stream boundary as normal EOF.
    /// File-backed input streams can report `hasBytesAvailable == true` until one final read,
    /// so scanning optional trailing modules cannot use that property alone.
    func readOptionalHeader() throws -> GmzFileHeader? {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        let readCount = read(&readBuffer, maxLength: readBuffer.count)
        guard readCount != 0 else { return nil }
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }

        let counter = readBuffer.reversed().reduce(UInt32(0)) { result, byte in
            result << 8 | UInt32(byte)
        }
        return GmzFileHeader(
            counter: Int(counter),
            token: try readCounter(),
            version: try readCounter()
        )
    }

    func readItemHeader() throws -> (Int, Int) {
        (try readCounter(), try readCounter())
    }

    func readCounter() throws -> Int {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        let readCount = read(&readBuffer, maxLength: readBuffer.count)
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }

        let u32 = readBuffer.reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        return Int(u32)
    }

    /// Upper bound on a single item/file block's declared size. `size` below comes
    /// straight off the wire (a 4-byte counter, up to ~4.29 billion) with nothing else
    /// validating it first — without this cap a single corrupted or malicious header
    /// (from a bad import file, or a peer's SharePlay/Bonjour network payload) would
    /// make `readData(size:)` attempt a multi-gigabyte allocation before the
    /// subsequent `read` call ever gets a chance to fail with `.notEnoughData`. See
    /// CODE_AUDIT_Import §6.1. 512 MB comfortably covers the largest legitimate single
    /// blob this format carries (an embedded PDF or 3D object file) with headroom.
    static let maxSingleBlockSize = 512 * ByteUnit.mebibyte

    func readData(size: Int) throws -> Data {
        guard size >= 0, size <= Self.maxSingleBlockSize else {
            throw ItemDataImportableError.notEnoughData
        }
        // Read in bounded chunks instead of allocating `size` bytes up front: a truncated
        // file with a large declared size used to allocate (and zero) up to 512 MB before
        // the first read could fail, and a partial read was treated as a failure.
        // See CODE_AUDIT_15 §5.7.
        var data = Data()
        data.reserveCapacity(min(size, Self.readChunkSize))
        var chunk = [UInt8](repeating: 0, count: min(size, Self.readChunkSize))
        while data.count < size {
            let wanted = min(chunk.count, size - data.count)
            let readCount = read(&chunk, maxLength: wanted)
            guard readCount > 0 else {
                throw ItemDataImportableError.notEnoughData
            }
            data.append(chunk, count: readCount)
        }
        return data
    }

    private static let readChunkSize = ByteUnit.mebibyte
}

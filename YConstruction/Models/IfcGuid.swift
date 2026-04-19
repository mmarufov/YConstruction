import Foundation

enum IfcGuid {
    // IFC GlobalId Base64 charset — 64 chars, order matters.
    private static let charset: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"
    )
    private static let lookup: [Character: UInt8] = {
        var m: [Character: UInt8] = [:]
        for (i, c) in charset.enumerated() { m[c] = UInt8(i) }
        return m
    }()

    /// Decompress a 22-char IFC GlobalId into a dashed 36-char UUID string.
    ///
    /// Example: `2O2Fr$t4X7Zf8NOew3FNld` → `9808fd7f-dc48-478e-9217-628e833d7be7`.
    /// First char encodes 2 bits, each remaining 21 chars encode 6 bits,
    /// for a total of 2 + 21×6 = 128 bits = 16 bytes.
    static func decompress(_ ifc: String) -> String? {
        let chars = Array(ifc)
        guard chars.count == 22 else { return nil }

        var bytes: [UInt8] = Array(repeating: 0, count: 16)
        var bitBuffer: UInt64 = 0
        var bitsInBuffer = 0
        var byteIndex = 0

        for (i, c) in chars.enumerated() {
            guard let v = lookup[c] else { return nil }
            let width = (i == 0) ? 2 : 6
            bitBuffer = (bitBuffer << UInt64(width)) | UInt64(v & UInt8((1 << width) - 1))
            bitsInBuffer += width
            while bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                bytes[byteIndex] = UInt8((bitBuffer >> UInt64(bitsInBuffer)) & 0xff)
                byteIndex += 1
            }
        }
        guard byteIndex == 16 else { return nil }

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.suffix(12))"
    }
}

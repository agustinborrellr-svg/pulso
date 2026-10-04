import Foundation

/// Bounds-checked little-endian readers. Out-of-range reads return nil so a truncated
/// frame decodes to "field absent" instead of crashing.
public enum LE {
    @inlinable public static func u8(_ b: [UInt8], _ i: Int) -> UInt8? {
        (i >= 0 && i < b.count) ? b[i] : nil
    }

    @inlinable public static func u16(_ b: [UInt8], _ i: Int) -> UInt16? {
        guard i >= 0, i + 1 < b.count else { return nil }
        return UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    @inlinable public static func i16(_ b: [UInt8], _ i: Int) -> Int16? {
        u16(b, i).map { Int16(bitPattern: $0) }
    }

    @inlinable public static func u32(_ b: [UInt8], _ i: Int) -> UInt32? {
        guard i >= 0, i + 3 < b.count else { return nil }
        return UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    @inlinable public static func f32(_ b: [UInt8], _ i: Int) -> Float? {
        u32(b, i).map { Float(bitPattern: $0) }
    }

    public static func bytes(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    public static func bytes(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    /// NUL-terminated printable ASCII starting at `i` (stops at NUL, non-printable or `maxLen`).
    public static func asciiZ(_ b: [UInt8], _ i: Int, maxLen: Int = 32) -> String {
        guard i >= 0, i < b.count else { return "" }
        var out = ""
        var k = i
        while k < b.count, k < i + maxLen {
            let c = b[k]
            if c == 0 || c < 0x20 || c > 0x7E { break }
            out.append(Character(UnicodeScalar(c)))
            k += 1
        }
        return out
    }
}

public enum Hex {
    public static func encode(_ b: [UInt8]) -> String {
        b.map { String(format: "%02x", $0) }.joined()
    }

    public static func decode(_ s: String) -> [UInt8]? {
        let chars = Array(s.filter { !$0.isWhitespace })
        guard chars.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let v = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            out.append(v)
            i += 2
        }
        return out
    }
}

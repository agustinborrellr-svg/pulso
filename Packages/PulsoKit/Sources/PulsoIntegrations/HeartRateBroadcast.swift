import Foundation

/// Standard Bluetooth Heart Rate Measurement (0x2A37) encoder, used to re-broadcast the strap's
/// pulse from the iPhone as an ordinary heart-rate sensor (Zwift, Peloton, gym machines, bike
/// computers and other apps can then read it).
public enum HeartRateBroadcast {
    public static let serviceUUID = "180D"
    public static let measurementUUID = "2A37"
    public static let bodyLocationUUID = "2A38"
    /// Body sensor location: 2 = wrist.
    public static let bodyLocationWrist: UInt8 = 2

    /// Flags: bit0 = 0 (u8 HR) or 1 (u16), bits1-2 = sensor contact supported+detected, bit4 = RR present.
    public static func measurement(heartRate: Int, rrMilliseconds: [Int] = [], contact: Bool = true) -> [UInt8] {
        let hr = max(0, min(heartRate, 65535))
        var flags: UInt8 = contact ? 0x06 : 0x04
        if hr > 255 { flags |= 0x01 }
        let rr = rrMilliseconds.filter { (300...2000).contains($0) }.prefix(hr > 255 ? 8 : 9)
        if !rr.isEmpty { flags |= 0x10 }
        var out: [UInt8] = [flags]
        if hr > 255 {
            out += [UInt8(hr & 0xFF), UInt8(hr >> 8)]
        } else {
            out.append(UInt8(hr))
        }
        for ms in rr {
            let v = UInt16((Double(ms) * 1024 / 1000).rounded())
            out += [UInt8(v & 0xFF), UInt8(v >> 8)]
        }
        return out
    }
}

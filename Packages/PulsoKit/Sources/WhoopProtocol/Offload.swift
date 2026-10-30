import Foundation

/// Sans-IO driver for the historical offload. Feed it every CRC-valid frame; it accumulates the
/// per-second records of the current chunk and tells the caller when a chunk is complete.
///
/// Protocol: SEND_HISTORICAL_DATA → [HISTORY_START] → type-47 records… → HISTORY_END(token)
/// → (app persists, then writes HISTORICAL_DATA_RESULT(0x01 + token)) → … → HISTORY_COMPLETE.
/// Never acknowledge a chunk before it is stored: the ack lets the strap drop that data.
public final class OffloadSession {
    public enum Step: Equatable {
        /// A chunk ended: persist `samples` and the raw frames of records we could not decode
        /// (`undecoded`), then ack with `token`. Acking drops the data on the strap, so both must be stored.
        case chunk(samples: [HistorySample], undecoded: [Frame], token: [UInt8], strapUnix: UInt32)
        /// The strap has nothing more to send.
        case complete(pending: [HistorySample], undecoded: [Frame])
    }

    public private(set) var pending: [HistorySample] = []
    public private(set) var pendingUndecoded: [Frame] = []
    public private(set) var chunks = 0
    public private(set) var totalSamples = 0
    public private(set) var otherRecords = 0
    public private(set) var started = Date()

    public init() {}

    /// Returns a step when the frame closes a chunk or the whole drain.
    public func handle(_ frame: Frame) -> Step? {
        guard frame.crcOK else { return nil }
        switch StrapMessage.decode(frame) {
        case .history(let s):
            pending.append(s)
            totalSamples += 1
            return nil
        case .otherHistory:
            otherRecords += 1
            pendingUndecoded.append(frame)
            return nil
        case .metadata(let m):
            switch m.kind {
            case .historyEnd:
                guard let token = m.token else { return nil }
                let out = pending, raw = pendingUndecoded
                pending.removeAll(keepingCapacity: true)
                pendingUndecoded.removeAll()
                chunks += 1
                return .chunk(samples: out, undecoded: raw, token: token, strapUnix: m.unix)
            case .historyComplete:
                let out = pending, raw = pendingUndecoded
                pending.removeAll()
                pendingUndecoded.removeAll()
                return .complete(pending: out, undecoded: raw)
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

import Foundation


// --------------------------------------------------------------------------------------
// BridgeFrame
// --------------------------------------------------------------------------------------
/// One message on the wire between a host language and the bridge:
///
///     u32 BE  length of everything after this field
///     u32 BE  header length
///     header  UTF-8 JSON object
///     body    raw bytes (little-endian float32 PCM, or empty)
///
/// Header kinds (`t`):
///
/// | t     | direction | keys                                   |
/// |-------|-----------|----------------------------------------|
/// | call  | → bridge  | `id`, `m` method, `p` params           |
/// | res   | ← bridge  | `id`, `r` result                       |
/// | err   | ← bridge  | `id`, `e` {code, message}              |
/// | ev    | ← bridge  | `s` stream, `e` event name, `d` data   |
/// | end   | ← bridge  | `s` stream, optional `e` {code, message} |
///
/// Audio travels as the body, never as JSON numbers: a 32 ms frame is 2 KB of
/// bytes, not 10 KB of text, and the host language maps it without parsing.
public struct BridgeFrame: @unchecked Sendable {
    public var header: [String: Any]
    public var body: Data

    public init(header: [String: Any], body: Data = Data()) {
        self.header = header
        self.body = body
    }

    // Public Methods
    // ----------------------------------------------------------------------------------
    public func encoded() throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: header, options: [])
        var out = Data(capacity: 8 + json.count + body.count)
        out.append(Self.__u32(UInt32(4 + json.count + body.count)))
        out.append(Self.__u32(UInt32(json.count)))
        out.append(json)
        out.append(body)
        return out
    }

    /// One frame from the front of `buffer`, removing its bytes; `nil` until
    /// the whole frame has arrived.
    public static func take(from buffer: inout Data) throws -> BridgeFrame? {
        guard buffer.count >= 8 else { return nil }
        let length = Int(__read_u32(buffer, at: 0))
        guard buffer.count >= 4 + length else { return nil }
        let header_length = Int(__read_u32(buffer, at: 4))
        guard header_length <= length - 4 else {
            throw BridgeError.protocol_error("header longer than frame")
        }
        let start = buffer.startIndex
        let header_data = buffer.subdata(in: (start + 8)..<(start + 8 + header_length))
        let body = buffer.subdata(in: (start + 8 + header_length)..<(start + 4 + length))
        buffer.removeSubrange(start..<(start + 4 + length))
        guard
            let header = try JSONSerialization.jsonObject(with: header_data)
                as? [String: Any]
        else {
            throw BridgeError.protocol_error("header is not an object")
        }
        return BridgeFrame(header: header, body: body)
    }

    // Audio bodies
    // ----------------------------------------------------------------------------------
    public static func pcm_body(_ samples: [Float]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public var pcm: [Float] {
        let count = body.count / MemoryLayout<Float>.size
        return body.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }

    // Private Methods
    // ----------------------------------------------------------------------------------
    private static func __u32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func __read_u32(_ data: Data, at offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return data[i..<(i + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}


// --------------------------------------------------------------------------------------
// BridgeError
// --------------------------------------------------------------------------------------
/// Failures the bridge reports as `err` frames; SDK errors pass through with
/// their own description.
public enum BridgeError: Error, CustomStringConvertible {
    case protocol_error(String)
    case unknown_method(String)
    case missing_param(String)
    case unknown_handle(String)
    case invalid_param(String, String)
    case tools_closed

    public var code: String {
        switch self {
        case .protocol_error: return "PROTOCOL"
        case .unknown_method: return "UNKNOWN_METHOD"
        case .missing_param: return "MISSING_PARAM"
        case .unknown_handle: return "UNKNOWN_HANDLE"
        case .invalid_param: return "INVALID_PARAM"
        case .tools_closed: return "TOOLS_CLOSED"
        }
    }

    public var description: String {
        switch self {
        case .protocol_error(let m): return "protocol error: \(m)"
        case .unknown_method(let m): return "unknown method \(m)"
        case .missing_param(let p): return "missing parameter \(p)"
        case .unknown_handle(let h): return "no object with handle \(h)"
        case .invalid_param(let p, let why): return "invalid parameter \(p): \(why)"
        case .tools_closed: return "the tools' session or agent was closed"
        }
    }
}

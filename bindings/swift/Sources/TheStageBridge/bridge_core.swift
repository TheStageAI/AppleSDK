import Foundation
import TheStageSDK


// --------------------------------------------------------------------------------------
// BridgeCore
// --------------------------------------------------------------------------------------
/// The SDK behind one host-language client. A call names a method and its
/// params; objects the client holds (a loaded model, a chat session, a TTS
/// stream, an engine, an agent) live here under string handles; streams send
/// `ev` frames until their `end`. Every route calls the public SDK the way
/// its documentation shows, so a binding never reaches into SDK internals.
///
/// `send` writes one frame to the client; the transport (a socket in
/// `thestage-host`, a native module in React Native) serializes it.
public final class BridgeCore: @unchecked Sendable {

    public typealias Send = @Sendable (BridgeFrame) -> Void

    /// What a route returns: the call's result, and the work to start once
    /// that result is on the wire (a stream's pump), so no event can arrive
    /// before the client knows the stream's handle.
    public struct Reply: @unchecked Sendable {
        public var result: [String: Any]
        public var body: Data
        public var after: (@Sendable () -> Void)?

        public init(
            _ result: [String: Any] = [:], body: Data = Data(),
            after: (@Sendable () -> Void)? = nil
        ) {
            self.result = result
            self.body = body
            self.after = after
        }
    }

    public typealias Route = @Sendable (BridgeCall) async throws -> Reply

    // Private Attributes
    // ----------------------------------------------------------------------------------
    private let __send: Send
    private let __lock = NSLock()
    private var __routes: [String: Route] = [:]
    private var __objects: [String: AnyObject] = [:]
    private var __next = 0

    // Constructor
    // ----------------------------------------------------------------------------------
    public init(send: @escaping Send) {
        __send = send
        SDKRoutes.register(in: self)
        LLMRoutes.register(in: self)
        VLMRoutes.register(in: self)
        MediaRoutes.register(in: self)
        ASRRoutes.register(in: self)
        TTSRoutes.register(in: self)
        ASREngineRoutes.register(in: self)
        SpeakerIDRoutes.register(in: self)
        VoiceAgentRoutes.register(in: self)
        ToolRoutes.register(in: self)
    }

    deinit {}

    // Public Methods
    // ----------------------------------------------------------------------------------
    /// One frame from the client. Calls run concurrently; each answers with
    /// exactly one `res` or `err`.
    public func receive(_ frame: BridgeFrame) {
        guard (frame.header["t"] as? String) == "call",
            let id = frame.header["id"] as? Int,
            let method = frame.header["m"] as? String
        else {
            __send(
                BridgeFrame(header: [
                    "t": "err", "id": frame.header["id"] ?? -1,
                    "e": ["code": "PROTOCOL", "message": "not a call frame"],
                ]))
            return
        }
        let params = frame.header["p"] as? [String: Any] ?? [:]
        let call = BridgeCall(
            core: self, method: method, params: params, body: frame.body)
        let route = __lock.withLock { __routes[method] }
        Task {
            guard let route else {
                self.__fail(id, BridgeError.unknown_method(method))
                return
            }
            do {
                let reply = try await route(call)
                self.__send(
                    BridgeFrame(
                        header: ["t": "res", "id": id, "r": reply.result],
                        body: reply.body))
                reply.after?()
            } catch {
                self.__fail(id, error)
            }
        }
    }

    // Internal: routes
    // ----------------------------------------------------------------------------------
    func register(_ method: String, _ route: @escaping Route) {
        __lock.withLock { __routes[method] = route }
    }

    /// Keep `object` under a new handle (`prefix-N`).
    func keep(_ object: AnyObject, prefix: String) -> String {
        __lock.withLock {
            __next += 1
            let handle = "\(prefix)-\(__next)"
            __objects[handle] = object
            return handle
        }
    }

    /// Keep the object `make` builds for its new handle (an object that needs it).
    func keep<T: AnyObject>(prefix: String, _ make: (String) -> T) -> T {
        __lock.withLock {
            __next += 1
            let handle = "\(prefix)-\(__next)"
            let object = make(handle)
            __objects[handle] = object
            return object
        }
    }

    func object<T: AnyObject>(_ handle: String, as type: T.Type) throws -> T {
        guard let object = __lock.withLock({ __objects[handle] }) as? T else {
            throw BridgeError.unknown_handle(handle)
        }
        return object
    }

    func release(_ handle: String) {
        // Dropped after the lock: a deinit may release handles of its own (a chat
        // session closes its tool relay).
        let object = __lock.withLock { __objects.removeValue(forKey: handle) }
        withExtendedLifetime(object) {}
    }

    /// An `ev` frame on stream `stream`.
    func event(
        _ stream: String, _ name: String, _ data: [String: Any] = [:], body: Data = Data()
    ) {
        __send(
            BridgeFrame(
                header: ["t": "ev", "s": stream, "e": name, "d": data], body: body))
    }

    /// The stream is over; `error` when it failed.
    func end(_ stream: String, error: Error? = nil) {
        var header: [String: Any] = ["t": "end", "s": stream]
        if let error { header["e"] = Self.__describe(error) }
        __send(BridgeFrame(header: header))
    }

    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __fail(_ id: Int, _ error: Error) {
        __send(BridgeFrame(header: ["t": "err", "id": id, "e": Self.__describe(error)]))
    }

    private static func __describe(_ error: Error) -> [String: Any] {
        if let bridge = error as? BridgeError {
            return ["code": bridge.code, "message": bridge.description]
        }
        // A capture failure names its case as the code, so a client can tell the
        // user which permission or macOS version is missing.
        if let tap = error as? CoreAudioTapError {
            return ["code": "\(tap)", "message": String(describing: tap)]
        }
        // `delete_model` refusals: the type name is the code, the message is the
        // readable reason instead of the struct dump.
        if error is ModelInUse || error is ModelBusy {
            return [
                "code": String(describing: type(of: error)),
                "message": error.localizedDescription,
            ]
        }
        return [
            "code": String(describing: type(of: error)),
            "message": String(describing: error),
        ]
    }
}


// --------------------------------------------------------------------------------------
// BridgeCall
// --------------------------------------------------------------------------------------
/// One call's method, params and body, with typed access to the params.
public struct BridgeCall: @unchecked Sendable {
    let core: BridgeCore
    public let method: String
    public let params: [String: Any]
    public let body: Data

    func string(_ key: String) throws -> String {
        guard let value = params[key] as? String else {
            throw BridgeError.missing_param(key)
        }
        return value
    }

    func string(_ key: String, default value: String?) -> String? {
        params[key] as? String ?? value
    }
    func int(_ key: String) -> Int? { (params[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (params[key] as? NSNumber)?.doubleValue }
    func bool(_ key: String) -> Bool? { (params[key] as? NSNumber)?.boolValue }
    func dict(_ key: String) -> [String: Any] { params[key] as? [String: Any] ?? [:] }

    func object<T: AnyObject>(_ key: String, as type: T.Type) throws -> T {
        try core.object(try string(key), as: type)
    }

    var pcm: [Float] { BridgeFrame(header: [:], body: body).pcm }
}

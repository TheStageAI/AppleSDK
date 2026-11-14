import Foundation
import TheStageSDK


// --------------------------------------------------------------------------------------
// ToolRoutes
// --------------------------------------------------------------------------------------
/// `tools.result`: the client's answer to a `call` event of a ``ToolRelay``.
enum ToolRoutes {
    static func register(in core: BridgeCore) {
        core.register("tools.result") { call in
            let relay = try call.object("relay", as: ToolRelay.self)
            relay.resolve(
                id: try call.string("id"),
                content: call.string("content", default: nil) ?? "")
            return .init()
        }
    }
}


// --------------------------------------------------------------------------------------
// ToolRelay
// --------------------------------------------------------------------------------------
/// Tools whose `execute` runs in the client. Each call the SDK makes becomes a `call`
/// event (`id`, `name`, `arguments`) on the relay's stream, and the SDK waits until the
/// client answers with `tools.result`. The relay's handle is also its stream's.
final class ToolRelay: @unchecked Sendable {

    // Public Attributes
    // ----------------------------------------------------------------------------------
    let handle: String

    // Private Attributes
    // ----------------------------------------------------------------------------------
    private unowned let __core: BridgeCore
    private let __lock = NSLock()
    private var __pending: [String: CheckedContinuation<String, Error>] = [:]
    private var __next = 0
    private var __closed = false

    // Constructor
    // ----------------------------------------------------------------------------------
    private init(core: BridgeCore, handle: String) {
        __core = core
        self.handle = handle
    }

    deinit {}

    // Public Methods
    // ----------------------------------------------------------------------------------
    /// The SDK tools for `items` (`[{name, description, parameters, callback}]`) and,
    /// when any item has `callback`, the relay (kept in `core`) they call back through.
    /// An item without `callback` keeps the SDK's mock result.
    static func make(
        core: BridgeCore, items: [[String: Any]]
    ) throws -> (ToolRelay?, [Tool]) {
        let definitions = try BridgeCodec.tools(items)
        guard items.contains(where: { $0["callback"] as? Bool == true }) else {
            return (nil, definitions)
        }
        let relay = core.keep(prefix: "tools") { ToolRelay(core: core, handle: $0) }
        let tools = zip(items, definitions).map { item, tool -> Tool in
            guard item["callback"] as? Bool == true else { return tool }
            return Tool(definition: tool.definition) { call in
                try await relay.__run(call)
            }
        }
        return (relay, tools)
    }

    /// The client's result for call `id`.
    func resolve(id: String, content: String) {
        let waiter = __lock.withLock { __pending.removeValue(forKey: id) }
        waiter?.resume(returning: content)
    }

    /// End the stream, fail the calls still waiting and drop the relay's handle.
    func close() {
        let waiters = __lock.withLock { () -> [CheckedContinuation<String, Error>] in
            if __closed { return [] }
            __closed = true
            defer { __pending.removeAll() }
            return Array(__pending.values)
        }
        for waiter in waiters { waiter.resume(throwing: BridgeError.tools_closed) }
        __core.end(handle)
        __core.release(handle)
    }

    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __run(_ call: ToolCall) async throws -> String {
        try await withCheckedThrowingContinuation { waiter in
            let id: String? = __lock.withLock {
                if __closed { return nil }
                __next += 1
                __pending["\(__next)"] = waiter
                return "\(__next)"
            }
            guard let id else {
                waiter.resume(throwing: BridgeError.tools_closed)
                return
            }
            let arguments =
                JSONSerialization.isValidJSONObject(call.arguments)
                ? call.arguments : call.arguments.mapValues { "\($0)" }
            __core.event(
                handle, "call", ["id": id, "name": call.name, "arguments": arguments])
        }
    }
}

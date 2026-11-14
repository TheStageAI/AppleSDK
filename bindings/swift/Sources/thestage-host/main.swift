import Darwin
import Foundation
import TheStageBridge


// --------------------------------------------------------------------------------------
// thestage-host
// --------------------------------------------------------------------------------------
// The process a host language drives: `thestage-host --socket <path>` listens
// on a Unix socket, takes one client, and serves `BridgeCore` over
// `BridgeFrame`s until the client disconnects; then it exits. The SDK's
// `TheStageAI` is main-actor isolated, so the main queue runs here
// (`dispatchMain`), which a Python interpreter never does for it.

let arguments = CommandLine.arguments
guard let flag = arguments.firstIndex(of: "--socket"), flag + 1 < arguments.count else {
    FileHandle.standardError.write(
        "usage: thestage-host --socket <path>\n".data(using: .utf8)!)
    exit(2)
}
let socket_path = arguments[flag + 1]

/// One accepted connection: a reader thread decoding frames, and a serial
/// queue writing them, so frames never interleave on the wire.
final class Connection: @unchecked Sendable {

    // Private Attributes
    // ----------------------------------------------------------------------------------
    private let __fd: Int32
    private let __writer = DispatchQueue(label: "ai.thestage.host.writer")
    private var __core: BridgeCore!

    // Constructor
    // ----------------------------------------------------------------------------------
    init(fd: Int32) {
        self.__fd = fd
        __core = BridgeCore(send: { [weak self] frame in self?.write(frame) })
    }

    deinit {}

    // Public Methods
    // ----------------------------------------------------------------------------------
    func write(_ frame: BridgeFrame) {
        guard let data = try? frame.encoded() else { return }
        __writer.async { [fd = __fd] in
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(
                        fd, raw.baseAddress! + offset, raw.count - offset)
                    if n <= 0 { return }
                    offset += n
                }
            }
        }
    }

    func read_forever() {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = Darwin.read(__fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            do {
                while let frame = try BridgeFrame.take(from: &buffer) {
                    __core.receive(frame)
                }
            } catch {
                FileHandle.standardError.write(
                    "thestage-host: \(error)\n".data(using: .utf8)!)
                break
            }
        }
        close(__fd)
        exit(0)
    }
}

func listen_once(at path: String) -> Int32 {
    unlink(path)
    let server = socket(AF_UNIX, SOCK_STREAM, 0)
    precondition(server >= 0, "socket() failed")
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    precondition(
        bytes.count < MemoryLayout.size(ofValue: address.sun_path), "socket path too long"
    )
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, size) }
    }
    precondition(bound == 0, "bind() failed: \(String(cString: strerror(errno)))")
    precondition(listen(server, 1) == 0, "listen() failed")
    // Ready line: the client connects once it reads this.
    print("READY \(path)")
    fflush(stdout)
    let client = accept(server, nil, nil)
    close(server)
    unlink(path)
    precondition(client >= 0, "accept() failed")
    return client
}

let connection = Connection(fd: listen_once(at: socket_path))
Thread.detachNewThread { connection.read_forever() }
dispatchMain()

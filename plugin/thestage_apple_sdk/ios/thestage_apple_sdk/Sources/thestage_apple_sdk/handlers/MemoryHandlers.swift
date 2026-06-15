@preconcurrency import Flutter
import Foundation

// --------------------------------------------------------------------------------------
// Memory Handlers
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    /// Report the process memory as iOS itself accounts it.
    ///
    /// `footprint_mb` is `phys_footprint` from `task_vm_info` — the SAME ledger
    /// the jetsam (memory-pressure) killer measures against the per-app limit
    /// and what Xcode's memory gauge shows. It counts dirty private memory,
    /// COMPRESSED pages, and IOKit/wired mappings (GPU / ANE), so for a CoreML
    /// model it is meaningfully larger than `resident_size`.
    ///
    /// `resident_mb` is `resident_size` (RSS) — pages currently in physical RAM,
    /// excluding compressed/IOKit memory. It's the smaller, less meaningful
    /// number (it's what Dart's `ProcessInfo.currentRss` returns) and is kept
    /// only as a secondary diagnostic. Termination decisions track footprint,
    /// not RSS.
    func __handle_memory_footprint(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(
                to: integer_t.self, capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard kr == KERN_SUCCESS else {
            result([
                "footprint_mb": -1.0,
                "resident_mb": -1.0,
            ])
            return
        }
        result([
            "footprint_mb": Double(info.phys_footprint) / 1_048_576.0,
            "resident_mb": Double(info.resident_size) / 1_048_576.0,
        ])
    }
}

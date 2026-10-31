import Darwin
import Foundation

/// Verifica lo stato dei processi senza permessi speciali, usando `sysctl`.
enum ProcessProbe {
    /// Istante di avvio del processo, se esiste.
    static func startTime(of pid: Int32) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = mib.withUnsafeMutableBufferPointer { buffer -> Int32 in
            sysctl(buffer.baseAddress, 4, &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        guard started.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }

    /// Vivo *e* è lo stesso processo di allora: confronta l'istante di avvio per non
    /// scambiare un PID riciclato per una sessione ancora aperta.
    static func isAlive(pid: Int32, startedAt: Date?, tolerance: TimeInterval = 120) -> Bool {
        guard pid > 0, let actualStart = startTime(of: pid) else { return false }
        guard let expected = startedAt else { return true }
        return abs(actualStart.timeIntervalSince(expected)) <= tolerance
    }
}

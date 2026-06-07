import Foundation

// MARK: - HRV Time-Domain Metrics
// Ported from whoof/metrics/hrv.js
// Standard published methods (Malik 1996, ESC/NASPE Task Force)

enum HRV {
    static let minBeatsForHRV = 5
    
    /// Drop ectopic/artifact RR intervals (>20% deviation from predecessor)
    static func filterRr(_ rrMs: [Double]) -> [Double] {
        guard !rrMs.isEmpty else { return [] }
        var out = [rrMs[0]]
        for i in 1..<rrMs.count {
            let r = rrMs[i]
            let prev = out.last!
            if abs(r - prev) / max(prev, 1) <= 0.2 {
                out.append(r)
            }
        }
        return out
    }
    
    /// Root mean square of successive RR differences (ms)
    static func rmssd(_ rrMs: [Double]) -> Double? {
        let rr = filterRr(rrMs)
        guard rr.count >= minBeatsForHRV else { return nil }
        let n = rr.count - 1
        var sumSq = 0.0
        for i in 0..<n {
            let d = rr[i + 1] - rr[i]
            sumSq += d * d
        }
        return sqrt(sumSq / Double(n))
    }
    
    /// Standard deviation of NN intervals (ms)
    static func sdnn(_ rrMs: [Double]) -> Double? {
        let rr = filterRr(rrMs)
        guard rr.count >= minBeatsForHRV else { return nil }
        let mean = rr.reduce(0, +) / Double(rr.count)
        let variance = rr.reduce(0) { $0 + pow($1 - mean, 2) } / Double(rr.count)
        return sqrt(variance)
    }
    
    /// Percentage of successive RR intervals differing by >50ms
    static func pnn50(_ rrMs: [Double]) -> Double? {
        let rr = filterRr(rrMs)
        guard rr.count >= minBeatsForHRV else { return nil }
        let n = rr.count - 1
        var over = 0
        for i in 0..<n {
            if abs(rr[i + 1] - rr[i]) > 50 { over += 1 }
        }
        return (100.0 * Double(over)) / Double(n)
    }
}

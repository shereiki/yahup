import Foundation

// MARK: - Recovery Score
// Ported from whoof/metrics/recovery.js
// Whoop-style 4-component recovery: HRV, RHR, Sleep, Strain

enum Recovery {
    static let baselineDays = 14
    static let minBaselineSamples = 3
    static let strainMax = 21.0
    
    struct Weights {
        static let hrv = 0.4
        static let rhr = 0.2
        static let sleep = 0.3
        static let strain = 0.1
    }
    
    struct Breakdown {
        let hrv: Double?
        let rhr: Double?
        let sleep: Double?
        let strain: Double?
        let total: Double?
    }
    
    // MARK: - Stats helpers
    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private static func pstdev(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count)
        return sqrt(variance)
    }
    
    private static func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }
    
    // MARK: - Z-score to 0-100 scale
    /// Map a value vs. baseline onto a 0-100 score.
    /// Higher = better recovery. inverted=true means lower value is better (e.g. RHR).
    static func zToScore(_ value: Double?, history: [Double], inverted: Bool = false) -> Double? {
        let cleaned = history.filter { $0 > 0 }
        guard let value, cleaned.count >= minBaselineSamples else { return nil }
        let mu = mean(cleaned)
        let sigma = max(pstdev(cleaned), 1.0)
        var z = (value - mu) / sigma
        if inverted { z = -z }
        z = max(-3.0, min(3.0, z))
        return round1(50.0 + (z / 3.0) * 50.0)
    }
    
    /// Whoop-style 4-component recovery breakdown.
    /// Components that can't be computed are null and dropped from the weighted avg.
    static func breakdown(
        todayRmssd: Double?,
        rmssdHistory: [Double],
        todayRhr: Double?,
        rhrHistory: [Double],
        sleepPerformancePct: Double?,
        yesterdayStrain: Double?
    ) -> Breakdown {
        let hrv = zToScore(todayRmssd, history: rmssdHistory, inverted: false)
        let rhr = zToScore(todayRhr, history: rhrHistory, inverted: true)
        let sleep: Double? = sleepPerformancePct.map { round1($0) }
        let strain: Double? = {
            guard let ys = yesterdayStrain else { return nil }
            let raw = 100.0 - (ys * 100.0) / strainMax
            return round1(max(0, min(100, raw)))
        }()
        
        let components: [(Double?, Double)] = [
            (hrv, Weights.hrv),
            (rhr, Weights.rhr),
            (sleep, Weights.sleep),
            (strain, Weights.strain),
        ]
        
        var weightSum = 0.0
        var weighted = 0.0
        for (val, weight) in components {
            guard let val else { continue }
            weightSum += weight
            weighted += val * weight
        }
        
        let total: Double? = weightSum > 0 ? round1(weighted / weightSum) : nil
        
        return Breakdown(hrv: hrv, rhr: rhr, sleep: sleep, strain: strain, total: total)
    }
}

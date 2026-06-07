import Foundation

// MARK: - Strain (Cardiac Load)
// Ported from whoof/metrics/strain.js
// Whoop-like 0-21 strain scale from cardiovascular load

enum Strain {
    /// Whoop-like 0-21 daily strain score.
    /// load = sum(max(0, (hr-rest)/(max-rest))^2) * minutes_per_sample
    /// strain = 21 * (1 - exp(-load/100))
    static func score(hrBpm: [Double], age: Int = 30, restingHr: Double? = nil) -> Double {
        let samples = hrBpm.filter { $0 >= 30 && $0 <= 230 }
        guard !samples.isEmpty else { return 0 }
        
        let maxHr = Double(220 - max(1, age))
        let rest = restingHr ?? samples.min()!
        guard maxHr > rest else { return 0 }
        
        let minutes = Double(samples.count) / 60.0
        var sumSq = 0.0
        for h in samples {
            let intensity = max(0, (h - rest) / (maxHr - rest))
            sumSq += intensity * intensity
        }
        let load = sumSq * ((minutes / Double(samples.count)) * 60)
        return (21.0 * (1.0 - exp(-load / 100.0)) * 100).rounded() / 100
    }
    
    /// Acute:Chronic Workload Ratio
    /// Ratio 0.8-1.3 = sweet spot. >1.3 = injury risk. <0.6 = detraining.
    struct ACWR {
        let ratio: Double
        let acute: Double
        let chronic: Double
    }
    
    static func acwr(
        strainSeries: [Double?],
        acuteDays: Int = 7,
        chronicDays: Int = 21,
        minSamples: Int = 5
    ) -> ACWR? {
        let acute = strainSeries.prefix(acuteDays).compactMap { $0 }
        let chronic = strainSeries.dropFirst(acuteDays).prefix(chronicDays).compactMap { $0 }
        guard acute.count >= minSamples, chronic.count >= minSamples else { return nil }
        let acuteMean = acute.reduce(0, +) / Double(acute.count)
        let chronicMean = chronic.reduce(0, +) / Double(chronic.count)
        guard chronicMean > 0 else { return nil }
        return ACWR(ratio: acuteMean / chronicMean, acute: acuteMean, chronic: chronicMean)
    }
}

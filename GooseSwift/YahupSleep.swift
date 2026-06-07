import Foundation

// MARK: - Sleep Detection & Staging
// Ported from whoof/metrics/sleep.js
// Deterministic heuristic sleep staging: motion + HR + RR variability

enum SleepAlgorithm {
    static let epochSeconds = 30.0
    static let minSleepBlockMinutes = 30.0
    static let nightStartHour = 20
    static let nightEndHour = 11
    static let baseSleepMinutes = 480.0
    static let stages = ["wake", "light", "deep", "rem"]
    
    struct SleepSample {
        let tsUtc: Date
        let heartRateBpm: Double?
        let rrIntervalMs: Double?
        let accelX: Double?
        let accelY: Double?
        let accelZ: Double?
    }
    
    struct StageSegment {
        let startUtc: String
        let endUtc: String
        let stage: String
        let source: String
    }
    
    // MARK: - Helpers
    private static func motionMagnitude(_ s: SleepSample) -> Double {
        abs(s.accelX ?? 0) + abs(s.accelY ?? 0) + abs(s.accelZ ?? 0)
    }
    
    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
    
    private static func pstdev(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count)
        return sqrt(variance)
    }
    
    // MARK: - Sleep Window Detection
    
    /// Find the contiguous low-motion + low-HR block that constitutes "last night".
    /// Returns [startUtc, endUtc] or nil.
    static func detectSleepWindow(_ samples: [SleepSample]) -> (Date, Date)? {
        guard !samples.isEmpty else { return nil }
        
        let hrs = samples.compactMap { $0.heartRateBpm }
        guard !hrs.isEmpty else { return nil }
        
        let hrMin = hrs.min()!
        let hrThreshold = max(mean(hrs) * 0.95, hrMin + 25)
        let motionThreshold = 180.0
        let gapTolerance = 6
        
        var runs: [[SleepSample]] = []
        var cur: [SleepSample] = []
        var gap = 0
        
        for s in samples {
            let hr = s.heartRateBpm ?? 999
            let isSleeping = hr < hrThreshold && motionMagnitude(s) < motionThreshold
            
            if isSleeping {
                cur.append(s)
                gap = 0
            } else if !cur.isEmpty {
                gap += 1
                if gap > gapTolerance {
                    runs.append(cur)
                    cur = []
                    gap = 0
                } else {
                    cur.append(s)
                }
            }
        }
        if !cur.isEmpty { runs.append(cur) }
        
        var best: (Date, Date, Int)?
        for run in runs {
            guard let first = run.first?.tsUtc, let last = run.last?.tsUtc else { continue }
            let durationMin = last.timeIntervalSince(first) / 60
            guard durationMin >= minSleepBlockMinutes else { continue }
            
            let mid = Date(timeIntervalSince1970: first.timeIntervalSince1970 + last.timeIntervalSince(first) / 2)
            let h = Calendar.current.component(.hour, from: mid)
            let inWindow = h >= nightStartHour || h < nightEndHour
            guard inWindow else { continue }
            
            let score = Int(durationMin)
            if best == nil || score > best!.2 {
                best = (first, last, score)
            }
        }
        
        guard let b = best else { return nil }
        return (b.0, b.1)
    }
    
    // MARK: - Stage Classification
    
    static func classifyStages(samples: [SleepSample], window: (Date, Date)) -> [StageSegment] {
        let (start, end) = window
        let startMs = start.timeIntervalSince1970 * 1000
        let endMs = end.timeIntervalSince1970 * 1000
        let epochMs = epochSeconds * 1000
        
        // Bucket into 30s epochs
        var epochs: [[SleepSample]] = []
        var curEpoch: [SleepSample] = []
        var bucketEndMs = startMs + epochMs
        
        for s in samples {
            let t = s.tsUtc.timeIntervalSince1970 * 1000
            guard t >= startMs && t < endMs else { continue }
            while t >= bucketEndMs {
                epochs.append(curEpoch)
                curEpoch = []
                bucketEndMs += epochMs
            }
            curEpoch.append(s)
        }
        if !curEpoch.isEmpty { epochs.append(curEpoch) }
        guard !epochs.isEmpty else { return [] }
        
        // Per-epoch stats
        struct EpochStats {
            let hr: Double?
            let motion: Double?
            let rmssd: Double?
        }
        
        let epochStats: [EpochStats] = epochs.map { ep in
            guard !ep.isEmpty else { return EpochStats(hr: nil, motion: nil, rmssd: nil) }
            let hrs = ep.compactMap { $0.heartRateBpm }
            let rrs = ep.compactMap { $0.rrIntervalMs }.filter { $0 > 250 && $0 < 2000 }
            let motions = ep.map { motionMagnitude($0) }
            
            let rmssdVal: Double? = {
                guard rrs.count >= 3 else { return nil }
                let n = rrs.count - 1
                var sumSq = 0.0
                for i in 0..<n {
                    let d = rrs[i + 1] - rrs[i]
                    sumSq += d * d
                }
                return sqrt(sumSq / Double(n))
            }()
            
            return EpochStats(
                hr: hrs.isEmpty ? nil : mean(hrs),
                motion: motions.isEmpty ? nil : mean(motions),
                rmssd: rmssdVal
            )
        }
        
        let hrVals = epochStats.compactMap { $0.hr }
        let rmssdVals = epochStats.compactMap { $0.rmssd }
        guard !hrVals.isEmpty else { return [] }
        
        let hrMin = hrVals.min()!
        let hrBaseline = median(hrVals)
        let rmssdBaseline = rmssdVals.isEmpty ? 30.0 : median(rmssdVals)
        
        // Classify each epoch
        var rawStages: [String] = []
        for e in epochStats {
            guard let hr = e.hr else { rawStages.append("wake"); continue }
            
            if (e.motion ?? 0) > 200 || hr > hrBaseline + 12 {
                rawStages.append("wake")
            } else if (e.motion ?? 999) < 30 && hr <= hrMin + 5 && (e.rmssd ?? 0) <= rmssdBaseline {
                rawStages.append("deep")
            } else if (e.motion ?? 999) < 60 && hr >= hrMin + 6 && (e.rmssd ?? 0) > rmssdBaseline * 1.1 {
                rawStages.append("rem")
            } else {
                rawStages.append("light")
            }
        }
        
        // Smooth: isolated wake surrounded by sleep → light
        var smoothed = rawStages
        for i in 1..<(smoothed.count - 1) {
            if smoothed[i] == "wake" && smoothed[i - 1] != "wake" && smoothed[i + 1] != "wake" {
                smoothed[i] = "light"
            }
        }
        
        // Consolidate runs
        var segments: [StageSegment] = []
        var curStage = smoothed[0]
        var curStartMs = startMs
        
        for i in 1..<smoothed.count {
            if smoothed[i] != curStage {
                let segEndMs = startMs + epochMs * Double(i)
                segments.append(StageSegment(
                    startUtc: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: curStartMs / 1000)),
                    endUtc: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: segEndMs / 1000)),
                    stage: curStage,
                    source: "heuristic-v1"
                ))
                curStage = smoothed[i]
                curStartMs = segEndMs
            }
        }
        segments.append(StageSegment(
            startUtc: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: curStartMs / 1000)),
            endUtc: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: endMs / 1000)),
            stage: curStage,
            source: "heuristic-v1"
        ))
        
        return segments
    }
    
    struct StageTotals {
        let wake: Int
        let light: Int
        let deep: Int
        let rem: Int
        var asleep: Int { light + deep + rem }
        var total: Int { wake + asleep }
    }
    
    static func stageTotals(_ stages: [StageSegment]) -> StageTotals {
        var totals: [String: Double] = ["wake": 0, "light": 0, "deep": 0, "rem": 0]
        let fmt = ISO8601DateFormatter()
        for seg in stages {
            guard let start = fmt.date(from: seg.startUtc),
                  let end = fmt.date(from: seg.endUtc) else { continue }
            totals[seg.stage, default: 0] += end.timeIntervalSince(start) / 60
        }
        return StageTotals(
            wake: Int(totals["wake"]!.rounded()),
            light: Int(totals["light"]!.rounded()),
            deep: Int(totals["deep"]!.rounded()),
            rem: Int(totals["rem"]!.rounded())
        )
    }
    
    // MARK: - Sleep Need / Performance
    
    static func sleepNeedMinutes(priorDebtMinutes: Double, strainYesterday: Double) -> Int {
        let debtBump = min(120, max(0, priorDebtMinutes) / 2)
        let strainBump = min(60, max(0, strainYesterday) * 3)
        return Int((baseSleepMinutes + debtBump + strainBump).rounded())
    }
    
    static func sleepPerformance(asleepMinutes: Int, needMinutes: Int) -> Double {
        guard needMinutes > 0 else { return 0 }
        let raw = min(100, (100.0 * Double(asleepMinutes)) / Double(needMinutes))
        return (raw * 10).rounded() / 10
    }
    
    static func sleepConsistencyPct(bedtimes: [Date], waketimes: [Date]) -> Double? {
        guard bedtimes.count >= 3, waketimes.count >= 3 else { return nil }
        
        let bedMinutes: [Double] = bedtimes.map { dt in
            var m = Double(Calendar.current.component(.hour, from: dt) * 60
                + Calendar.current.component(.minute, from: dt))
            if m < 720 { m += 1440 }
            return m
        }
        let wakeMinutes: [Double] = waketimes.map { dt in
            Double(Calendar.current.component(.hour, from: dt) * 60
                + Calendar.current.component(.minute, from: dt))
        }
        
        let sigma = (pstdev(bedMinutes) + pstdev(wakeMinutes)) / 2
        let raw = max(0, min(100, 100 - sigma / 1.2))
        return (raw * 10).rounded() / 10
    }
}

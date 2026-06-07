import SwiftUI
import UIKit

enum GooseTheme {
  static let deviceBackground = Color(red: 0.06, green: 0.09, blue: 0.11)

  static let appBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  })

  static let plainBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemBackground
  })

  static func configureAppearance() {
    UIWindow.appearance().backgroundColor = appBackgroundUIColor
    UITableView.appearance().backgroundColor = appBackgroundUIColor
    UICollectionView.appearance().backgroundColor = appBackgroundUIColor

    let navigationAppearance = UINavigationBarAppearance()
    navigationAppearance.configureWithTransparentBackground()
    navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    navigationAppearance.backgroundColor = navigationBarBackgroundUIColor
    navigationAppearance.shadowColor = .clear
    UINavigationBar.appearance().standardAppearance = navigationAppearance
    UINavigationBar.appearance().compactAppearance = navigationAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = appBackgroundUIColor
    tabAppearance.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
  }

  private static let deviceBackgroundUIColor = UIColor(
    red: 0.06,
    green: 0.09,
    blue: 0.11,
    alpha: 1
  )

  private static let appBackgroundUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  }

  private static let navigationBarBackgroundUIColor = UIColor { traits in
    let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.58 : 0.46
    return appBackgroundUIColor.resolvedColor(with: traits).withAlphaComponent(alpha)
  }
}

extension View {
  func gooseScreenBackground() -> some View {
    background(GooseTheme.appBackground.ignoresSafeArea())
  }

  func goosePlainBackground() -> some View {
    background(GooseTheme.plainBackground.ignoresSafeArea())
  }

  func gooseListBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(GooseTheme.appBackground.ignoresSafeArea())
  }
}

// MARK: - Yahup Algorithms (ported from whoof)

// HRV Time-Domain Metrics
enum HRV {
    static let minBeatsForHRV = 5
    
    static func filterRr(_ rrMs: [Double]) -> [Double] {
        guard !rrMs.isEmpty else { return [] }
        var out = [rrMs[0]]
        for i in 1..<rrMs.count {
            let r = rrMs[i], prev = out.last!
            if abs(r - prev) / max(prev, 1) <= 0.2 { out.append(r) }
        }
        return out
    }
    
    static func rmssd(_ rrMs: [Double]) -> Double? {
        let rr = filterRr(rrMs)
        guard rr.count >= minBeatsForHRV else { return nil }
        let n = rr.count - 1
        var sumSq = 0.0
        for i in 0..<n { let d = rr[i+1] - rr[i]; sumSq += d * d }
        return sqrt(sumSq / Double(n))
    }
    
    static func sdnn(_ rrMs: [Double]) -> Double? {
        let rr = filterRr(rrMs)
        guard rr.count >= minBeatsForHRV else { return nil }
        let mean = rr.reduce(0,+) / Double(rr.count)
        let variance = rr.reduce(0) { $0 + pow($1 - mean, 2) } / Double(rr.count)
        return sqrt(variance)
    }
    
    static func pnn50(_ rrMs: [Double]) -> Double? {
        let rr = filterRr(rrMs)
        guard rr.count >= minBeatsForHRV else { return nil }
        let n = rr.count - 1
        var over = 0
        for i in 0..<n { if abs(rr[i+1] - rr[i]) > 50 { over += 1 } }
        return (100.0 * Double(over)) / Double(n)
    }
}

// Recovery Score
enum Recovery {
    static let baselineDays = 14, minBaselineSamples = 3, strainMax = 21.0
    
    struct Breakdown { let hrv, rhr, sleep, strain, total: Double? }
    
    private static func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0,+)/Double(v.count) }
    private static func pstdev(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let m = mean(v)
        return sqrt(v.reduce(0){$0+pow($1-m,2)}/Double(v.count))
    }
    private static func round1(_ v: Double) -> Double { (v*10).rounded()/10 }
    
    static func zToScore(_ value: Double?, history: [Double], inverted: Bool = false) -> Double? {
        let cleaned = history.filter { $0 > 0 }
        guard let v = value, cleaned.count >= minBaselineSamples else { return nil }
        let mu = mean(cleaned), sigma = max(pstdev(cleaned), 1.0)
        var z = (v - mu) / sigma; if inverted { z = -z }
        z = max(-3, min(3, z))
        return round1(50 + (z/3)*50)
    }
    
    static func breakdown(todayRmssd: Double?, rmssdHistory: [Double], todayRhr: Double?, rhrHistory: [Double], sleepPerformancePct: Double?, yesterdayStrain: Double?) -> Breakdown {
        let h = zToScore(todayRmssd, history: rmssdHistory)
        let r = zToScore(todayRhr, history: rhrHistory, inverted: true)
        let s = sleepPerformancePct.map(round1)
        let st: Double? = yesterdayStrain.map { round1(max(0, min(100, 100 - ($0*100)/strainMax))) }
        let comps: [(Double?, Double)] = [(h, 0.4), (r, 0.2), (s, 0.3), (st, 0.1)]
        var ws = 0.0, wv = 0.0
        for (v, w) in comps { if let v { ws += w; wv += v*w } }
        return Breakdown(hrv: h, rhr: r, sleep: s, strain: st, total: ws > 0 ? round1(wv/ws) : nil)
    }
}

// Strain
enum Strain {
    static func score(hrBpm: [Double], age: Int = 30, restingHr: Double? = nil) -> Double {
        let samples = hrBpm.filter { $0 >= 30 && $0 <= 230 }
        guard !samples.isEmpty else { return 0 }
        let maxHr = Double(220 - max(1, age)), rest = restingHr ?? samples.min()!
        guard maxHr > rest else { return 0 }
        let minutes = Double(samples.count) / 60
        var sumSq = 0.0
        for h in samples { let i = max(0, (h-rest)/(maxHr-rest)); sumSq += i*i }
        let load = sumSq * ((minutes / Double(samples.count)) * 60)
        return (21 * (1 - exp(-load/100)) * 100).rounded() / 100
    }
}

// Sleep Detection & Staging
enum SleepAlgorithm {
    static let epochSeconds = 30.0, minSleepBlockMin = 30.0, nightStartH = 20, nightEndH = 11
    
    struct SleepSample {
        let tsUtc: Date; let heartRateBpm, rrIntervalMs, accelX, accelY, accelZ: Double?
    }
    struct StageSegment { let startUtc, endUtc, stage, source: String }
    struct StageTotals { let wake, light, deep, rem: Int; var asleep: Int { light+deep+rem }; var total: Int { wake+asleep } }
    
    private static func motionMag(_ s: SleepSample) -> Double { abs(s.accelX ?? 0)+abs(s.accelY ?? 0)+abs(s.accelZ ?? 0) }
    private static func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0,+)/Double(v.count) }
    private static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted(), mid = s.count/2
        return s.count%2==0 ? (s[mid-1]+s[mid])/2 : s[mid]
    }
    
    static func detectSleepWindow(_ samples: [SleepSample]) -> (Date, Date)? {
        guard !samples.isEmpty else { return nil }
        let hrs = samples.compactMap{$0.heartRateBpm}; guard !hrs.isEmpty else { return nil }
        let hrMin = hrs.min()!, hrThresh = max(mean(hrs)*0.95, hrMin+25), motThresh = 180.0, gapTol = 6
        var runs: [[SleepSample]] = [], cur: [SleepSample] = [], gap = 0
        for s in samples {
            let hr = s.heartRateBpm ?? 999
            if hr < hrThresh && motionMag(s) < motThresh { cur.append(s); gap = 0 }
            else if !cur.isEmpty { gap += 1; if gap > gapTol { runs.append(cur); cur = []; gap = 0 } else { cur.append(s) } }
        }
        if !cur.isEmpty { runs.append(cur) }
        var best: (Date, Date, Int)?
        for run in runs {
            guard let f = run.first?.tsUtc, let l = run.last?.tsUtc else { continue }
            let dur = l.timeIntervalSince(f)/60; guard dur >= minSleepBlockMin else { continue }
            let mid = Date(timeIntervalSince1970: f.timeIntervalSince1970 + l.timeIntervalSince(f)/2)
            let h = Calendar.current.component(.hour, from: mid)
            guard h >= nightStartH || h < nightEndH else { continue }
            let sc = Int(dur); if best == nil || sc > best!.2 { best = (f, l, sc) }
        }
        return best.map { ($0.0, $0.1) }
    }
    
    static func classifyStages(samples: [SleepSample], window: (Date, Date)) -> [StageSegment] {
        let (start, end) = window
        let startMs = start.timeIntervalSince1970*1000, endMs = end.timeIntervalSince1970*1000, epochMs = epochSeconds*1000
        var epochs: [[SleepSample]] = [], curEpoch: [SleepSample] = [], bucketEnd = startMs + epochMs
        for s in samples {
            let t = s.tsUtc.timeIntervalSince1970*1000
            guard t >= startMs && t < endMs else { continue }
            while t >= bucketEnd { epochs.append(curEpoch); curEpoch = []; bucketEnd += epochMs }
            curEpoch.append(s)
        }
        if !curEpoch.isEmpty { epochs.append(curEpoch) }
        guard !epochs.isEmpty else { return [] }
        
        let epochStats: [(hr: Double?, mot: Double?, rmssd: Double?)] = epochs.map { ep in
            guard !ep.isEmpty else { return (nil, nil, nil) }
            let hrs = ep.compactMap{$0.heartRateBpm}, rrs = ep.compactMap{$0.rrIntervalMs}.filter{$0>250&&$0<2000}
            let mots = ep.map{motionMag($0)}
            let r: Double? = {
                guard rrs.count >= 3 else { return nil }
                let n = rrs.count-1; var ss = 0.0
                for i in 0..<n { let d = rrs[i+1]-rrs[i]; ss += d*d }
                return sqrt(ss/Double(n))
            }()
            return (hrs.isEmpty ? nil : mean(hrs), mots.isEmpty ? nil : mean(mots), r)
        }
        let hrVals = epochStats.compactMap{$0.hr}, rmssdVals = epochStats.compactMap{$0.rmssd}
        guard !hrVals.isEmpty else { return [] }
        let hrMin = hrVals.min()!, hrBase = median(hrVals), rmssdBase = rmssdVals.isEmpty ? 30 : median(rmssdVals)
        var rawStages: [String] = []
        for e in epochStats {
            guard let hr = e.hr else { rawStages.append("wake"); continue }
            if (e.mot ?? 0) > 200 || hr > hrBase+12 { rawStages.append("wake") }
            else if (e.mot ?? 999) < 30 && hr <= hrMin+5 && (e.rmssd ?? 0) <= rmssdBase { rawStages.append("deep") }
            else if (e.mot ?? 999) < 60 && hr >= hrMin+6 && (e.rmssd ?? 0) > rmssdBase*1.1 { rawStages.append("rem") }
            else { rawStages.append("light") }
        }
        var smoothed = rawStages
        for i in 1..<(smoothed.count-1) {
            if smoothed[i] == "wake" && smoothed[i-1] != "wake" && smoothed[i+1] != "wake" {
                smoothed[i] = "light"
            }
        }
        var segs: [StageSegment] = [], curStage = smoothed[0], curStart = startMs
        for i in 1..<smoothed.count where smoothed[i] != curStage {
            let segEnd = startMs + epochMs*Double(i)
            segs.append(StageSegment(startUtc: ISO8601DateFormatter().string(from: Date(ms: curStart)), endUtc: ISO8601DateFormatter().string(from: Date(ms: segEnd)), stage: curStage, source: "heuristic-v1"))
            curStage = smoothed[i]; curStart = segEnd
        }
        segs.append(StageSegment(startUtc: ISO8601DateFormatter().string(from: Date(ms: curStart)), endUtc: ISO8601DateFormatter().string(from: Date(ms: endMs)), stage: curStage, source: "heuristic-v1"))
        return segs
    }
    
    static func stageTotals(_ stages: [StageSegment]) -> StageTotals {
        var t: [String: Double] = ["wake":0,"light":0,"deep":0,"rem":0]
        let fmt = ISO8601DateFormatter()
        for seg in stages {
            guard let s = fmt.date(from: seg.startUtc), let e = fmt.date(from: seg.endUtc) else { continue }
            t[seg.stage, default: 0] += e.timeIntervalSince(s)/60
        }
        return StageTotals(wake: Int(t["wake"]!.rounded()), light: Int(t["light"]!.rounded()), deep: Int(t["deep"]!.rounded()), rem: Int(t["rem"]!.rounded()))
    }
    
    static func sleepNeedMin(priorDebt: Double, strainYest: Double) -> Int {
        Int((480 + min(120, max(0, priorDebt)/2) + min(60, max(0, strainYest)*3)).rounded())
    }
    static func sleepPerf(asleep: Int, need: Int) -> Double {
        guard need > 0 else { return 0 }; return (min(100, (100*Double(asleep))/Double(need))*10).rounded()/10
    }
}

extension Date {
    init(ms: Double) { self.init(timeIntervalSince1970: ms/1000) }
}

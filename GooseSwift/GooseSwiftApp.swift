import SwiftUI
import Foundation

// MARK: - Yahup App Entry
@main
struct YahupApp: App {
    @StateObject private var model = YahupModel()
    
    init() { GooseTheme.configureAppearance() }
    
    var body: some Scene {
        WindowGroup {
            YahupDashboardView()
                .environmentObject(model)
        }
    }
}

// MARK: - Yahup Data Model
@MainActor
final class YahupModel: ObservableObject {
    let bleClient = GooseBLEClient()
    private let rust = GooseRustBridge()
    
    @Published var connectionState = "disconnected"
    @Published var isSyncing = false; @Published var syncPacketCount = 0
    @Published var liveHeartRate: Double?; @Published var liveHRV: Double?
    @Published var restingHeartRate: Double?; @Published var recoveryScore: Double?
    @Published var strainScore: Double?; @Published var sleepMinutes: Int?
    @Published var sleepStages: SleepAlgorithm.StageTotals?
    @Published var sleepPerformance: Double?; @Published var respiratoryRate: Double?
    @Published var stressAvg: Double?; @Published var calories: Double?
    @Published var skinTemp: Double?; @Published var spo2: Double?
    @Published var statusMessage = "Ready to connect"
    
    init() {
        bleClient.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in self?.connectionState = state }
        }
        bleClient.onHistoricalSyncProgress = { [weak self] p in
            Task { @MainActor in
                self?.isSyncing = !p.isTerminal; self?.syncPacketCount = p.packetCount
                if p.isTerminal && !p.failed && p.packetCount > 0 {
                    self?.statusMessage = "Sync complete — computing..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Task { await self?.compute() } }
                } else if p.failed { self?.statusMessage = "Sync failed: \(p.detail)" }
                else { self?.statusMessage = "Syncing: \(p.packetCount) pkts" }
            }
        }
    }
    
    func connect() { bleClient.scanAndConnect() }
    func disconnect() { bleClient.disconnect() }
    func startSync() { guard connectionState == "ready" else { return }; bleClient.beginHistoricalSync(trigger: "user", automatic: false) }
    
    func compute() async {
        statusMessage = "Running metrics..."
        let dbPath = HealthDataStore.defaultDatabasePath()
        var samples: [(Date, Double?, Double?, Double?, Double?, Double?)] = []
        do {
            let r = try rust.request(method: "metrics.recent_samples", args: ["database_path": dbPath, "limit": 10000])
            if let rows = r["samples"] as? [[String: Any]] {
                for row in rows {
                    guard let ts = (row["ts_utc"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }) else { continue }
                    samples.append((ts, row["heart_rate_bpm"] as? Double, row["rr_interval_ms"] as? Double, row["accel_x"] as? Double, row["accel_y"] as? Double, row["accel_z"] as? Double))
                }
            }
        } catch { statusMessage = "DB read failed"; return }
        guard !samples.isEmpty else { statusMessage = "No data. Sync first."; return }
        
        let hrs = samples.compactMap{$0.1}; let rrs = samples.compactMap{$0.2}
        liveHeartRate = hrs.last; liveHRV = HRV.rmssd(rrs)
        let sorted = hrs.sorted(); restingHeartRate = sorted[max(0, Int(Double(sorted.count)*0.05)-1)]
        strainScore = Strain.score(hrBpm: hrs, restingHr: restingHeartRate)
        
        let sleepSamples = samples.map { SleepAlgorithm.SleepSample(tsUtc: $0.0, heartRateBpm: $0.1, rrIntervalMs: $0.2, accelX: $0.3, accelY: $0.4, accelZ: $0.5) }
        if let win = SleepAlgorithm.detectSleepWindow(sleepSamples) {
            let stages = SleepAlgorithm.classifyStages(samples: sleepSamples, window: win)
            sleepStages = SleepAlgorithm.stageTotals(stages)
            sleepMinutes = sleepStages?.asleep
            let sleepRrs = sleepSamples.filter { $0.rrIntervalMs != nil && $0.tsUtc >= win.0 && $0.tsUtc < win.1 }.compactMap{$0.rrIntervalMs}
            let todayRmssd = HRV.rmssd(sleepRrs)
            let bd = Recovery.breakdown(todayRmssd: todayRmssd, rmssdHistory: [], todayRhr: restingHeartRate, rhrHistory: [], sleepPerformancePct: sleepPerformance, yesterdayStrain: nil)
            recoveryScore = bd.total
            if let sl = sleepMinutes { sleepPerformance = SleepAlgorithm.sleepPerf(asleep: sl, need: SleepAlgorithm.sleepNeedMin(priorDebt: 0, strainYest: 0)) }
        }
        statusMessage = "Metrics ready"
    }
}

// MARK: - Yahup Dashboard UI
struct YahupDashboardView: View {
    @EnvironmentObject var model: YahupModel
    
    var body: some View {
        ZStack {
            Color(hex: "0A0A0C").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("yahup").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                            Text(model.connectionState == "ready" ? "Connected" : model.connectionState).font(.caption).foregroundColor(model.connectionState == "ready" ? .green : .gray)
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            if model.connectionState == "ready" {
                                Button("Sync", action: model.startSync).buttonStyle(.bordered).tint(.blue).disabled(model.isSyncing).font(.caption.weight(.semibold))
                            }
                            Button(model.connectionState == "ready" ? "Disconnect" : "Connect", action: model.connectionState == "ready" ? model.disconnect : model.connect).buttonStyle(.borderedProminent).tint(model.connectionState == "ready" ? .red : .green).font(.caption.weight(.semibold))
                        }
                    }
                    
                    HStack {
                        Circle().fill(model.connectionState == "ready" ? Color.green : Color.gray).frame(width: 8, height: 8)
                        Text(model.statusMessage).font(.caption).foregroundColor(.gray)
                        if model.isSyncing { ProgressView().scaleEffect(0.7) }
                        Spacer()
                        if model.syncPacketCount > 0 { Text("\(model.syncPacketCount) pkts").font(.caption2).foregroundColor(.gray) }
                    }.padding(.horizontal, 12).padding(.vertical, 8).background(Color(hex: "141418")).cornerRadius(8)
                    
                    if let rec = model.recoveryScore {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle().stroke(recColor(Int(rec)).opacity(0.2), lineWidth: 8).frame(width: 80, height: 80)
                                Circle().trim(from: 0, to: CGFloat(rec)/100).stroke(recColor(Int(rec)), style: StrokeStyle(lineWidth: 8, lineCap: .round)).frame(width: 80, height: 80).rotationEffect(.degrees(-90))
                                VStack(spacing: 0) { Text("\(Int(rec))").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(.white); Text("%").font(.caption2).foregroundColor(.gray) }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recovery").font(.headline).foregroundColor(.white)
                                Text(recLabel(Int(rec))).font(.subheadline).foregroundColor(recColor(Int(rec)))
                            }
                            Spacer()
                        }.padding(14).background(Color(hex: "141418")).cornerRadius(14)
                    }
                    
                    HStack(spacing: 12) {
                        if let st = model.strainScore {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "flame.fill").foregroundColor(.orange)
                                Text(String(format: "%.1f", st)).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                                Text("Strain").font(.caption).foregroundColor(.gray)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color(hex: "141418")).cornerRadius(12)
                        }
                        if let sl = model.sleepMinutes {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "moon.fill").foregroundColor(.purple)
                                Text("\(sl/60)h \(sl%60)m").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                                Text("Sleep").font(.caption).foregroundColor(.gray)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color(hex: "141418")).cornerRadius(12)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let hr = model.liveHeartRate { vitals("HR", "\(Int(hr))", "bpm", .red) }
                        if let hrv = model.liveHRV { vitals("HRV", String(format: "%.0f", hrv), "ms", .green) }
                        if let rhr = model.restingHeartRate { vitals("RHR", "\(Int(rhr))", "bpm", .blue) }
                    }
                    
                    if let stages = model.sleepStages {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sleep Stages").font(.subheadline.weight(.semibold)).foregroundColor(.white)
                            GeometryReader { geo in
                                HStack(spacing: 0) {
                                    Rectangle().fill(.orange).frame(width: barW(stages.wake, stages.total, geo.size.width))
                                    Rectangle().fill(.purple).frame(width: barW(stages.rem, stages.total, geo.size.width))
                                    Rectangle().fill(.blue).frame(width: barW(stages.light, stages.total, geo.size.width))
                                    Rectangle().fill(.green).frame(width: barW(stages.deep, stages.total, geo.size.width))
                                }
                            }.frame(height: 20).cornerRadius(6)
                            HStack(spacing: 12) {
                                dot("Awake", stages.wake, .orange); dot("REM", stages.rem, .purple)
                                dot("Light", stages.light, .blue); dot("Deep", stages.deep, .green)
                            }
                        }.padding(12).background(Color(hex: "141418")).cornerRadius(12)
                    }
                }.padding(16)
            }
        }.preferredColorScheme(.dark)
    }
    
    func vitals(_ t: String, _ v: String, _ u: String, _ c: Color) -> some View {
        VStack(spacing: 2) { Text(v).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(c); Text(u).font(.caption2).foregroundColor(.gray); Text(t).font(.caption2).foregroundColor(.gray) }.frame(maxWidth: .infinity).padding(.vertical, 8).background(Color(hex: "141418")).cornerRadius(8)
    }
    func dot(_ l: String, _ m: Int, _ c: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 6, height: 6); Text("\(l) \(m)m").font(.caption2).foregroundColor(.gray) }
    }
    func barW(_ m: Int, _ t: Int, _ w: CGFloat) -> CGFloat { max(2, CGFloat(m)/CGFloat(max(1,t))*w) }
    func recColor(_ s: Int) -> Color { s < 34 ? .red : s < 67 ? .yellow : .green }
    func recLabel(_ s: Int) -> String { s < 34 ? "Low" : s < 67 ? "Medium" : "High" }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var i: UInt64 = 0; Scanner(string: h).scanHexInt64(&i)
        let r = Double((i>>16)&0xFF)/255, g = Double((i>>8)&0xFF)/255, b = Double(i&0xFF)/255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

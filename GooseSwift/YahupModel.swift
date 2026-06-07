import Foundation
import SwiftUI
import Combine

// MARK: - Yahup Data Model
// Clean orchestration: BLE → SQLite → Algorithms → UI
// Bypasses goose's complex AppModel, uses only its BLE client + Rust bridge

@MainActor
final class YahupModel: ObservableObject {
    // BLE
    let bleClient = GooseBLEClient()
    
    // Published metrics
    @Published var connectionState = "disconnected"
    @Published var isSyncing = false
    @Published var syncPacketCount = 0
    
    @Published var liveHeartRate: Double?
    @Published var liveHRV: Double?
    @Published var restingHeartRate: Double?
    
    @Published var recoveryScore: Double?
    @Published var recoveryHrvComponent: Double?
    @Published var recoveryRhrComponent: Double?
    @Published var recoverySleepComponent: Double?
    
    @Published var strainScore: Double?
    @Published var sleepMinutes: Int?
    @Published var sleepStages: SleepAlgorithm.StageTotals?
    @Published var sleepPerformance: Double?
    @Published var respiratoryRate: Double?
    @Published var stressAvg: Double?
    @Published var calories: Double?
    
    @Published var skinTemp: Double?
    @Published var spo2: Double?
    
    // History
    @Published var dailyMetrics: [String: [String: Any]] = [:]
    
    // Status
    @Published var statusMessage = "Ready to connect"
    
    private let rust = GooseRustBridge()
    private var syncObserver: NSObjectProtocol?
    
    init() {
        setupBLE()
    }
    
    private func setupBLE() {
        bleClient.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
                if state == "ready" {
                    self?.statusMessage = "Connected — tap Sync to pull data"
                }
            }
        }
        
        bleClient.onHistoricalSyncProgress = { [weak self] progress in
            Task { @MainActor in
                self?.isSyncing = !progress.isTerminal
                self?.syncPacketCount = progress.packetCount
                
                if progress.isTerminal && !progress.failed && progress.packetCount > 0 {
                    self?.statusMessage = "Sync complete — computing metrics..."
                    // Delay to let DB writes flush
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        Task { await self?.computeAllMetrics() }
                    }
                } else if progress.failed {
                    self?.statusMessage = "Sync failed: \(progress.detail)"
                } else {
                    self?.statusMessage = "Syncing: \(progress.packetCount) packets"
                }
            }
        }
    }
    
    // MARK: - Actions
    
    func connect() {
        statusMessage = "Scanning for WHOOP..."
        bleClient.scanAndConnect()
    }
    
    func disconnect() {
        bleClient.disconnect()
        statusMessage = "Disconnected"
    }
    
    func startSync() {
        guard connectionState == "ready" else {
            statusMessage = "Connect first"
            return
        }
        statusMessage = "Starting historical sync..."
        bleClient.beginHistoricalSync(trigger: "user", automatic: false)
    }
    
    // MARK: - Metric Computation
    
    func computeAllMetrics() async {
        statusMessage = "Running recovery & strain..."
        
        let dbPath = HealthDataStore.defaultDatabasePath()
        
        // Read samples from Rust bridge
        let samples = readSamplesFromDB(dbPath)
        guard !samples.isEmpty else {
            statusMessage = "No data in database. Try syncing first."
            return
        }
        
        let hrs = samples.compactMap { $0.heartRateBpm }
        let rrs = samples.compactMap { $0.rrIntervalMs }
        
        // Live metrics
        liveHeartRate = hrs.last
        liveHRV = HRV.rmssd(rrs)
        restingHeartRate = restingHrFromSamples(hrs)
        
        // Strain
        strainScore = Strain.score(hrBpm: hrs, restingHr: restingHeartRate)
        
        // Sleep
        let sleepSamples = samples.map { sample in
            SleepAlgorithm.SleepSample(
                tsUtc: sample.timestamp,
                heartRateBpm: sample.heartRateBpm,
                rrIntervalMs: sample.rrIntervalMs,
                accelX: sample.accelX,
                accelY: sample.accelY,
                accelZ: sample.accelZ
            )
        }
        
        if let window = SleepAlgorithm.detectSleepWindow(sleepSamples) {
            let stages = SleepAlgorithm.classifyStages(samples: sleepSamples, window: window)
            sleepStages = SleepAlgorithm.stageTotals(stages)
            sleepMinutes = sleepStages?.asleep
            
            // Sleep RR intervals for HRV
            let sleepRrs = sleepSamples
                .filter { s in
                    s.rrIntervalMs != nil
                        && s.tsUtc >= window.0
                        && s.tsUtc < window.1
                }
                .compactMap { $0.rrIntervalMs }
            
            let todayRmssd = HRV.rmssd(sleepRrs)
            liveHRV = todayRmssd ?? liveHRV
            
            // Recovery
            let breakdown = Recovery.breakdown(
                todayRmssd: todayRmssd,
                rmssdHistory: [], // TODO: populate from history
                todayRhr: restingHeartRate,
                rhrHistory: [],
                sleepPerformancePct: sleepPerformance,
                yesterdayStrain: nil
            )
            
            recoveryScore = breakdown.total
            recoveryHrvComponent = breakdown.hrv
            recoveryRhrComponent = breakdown.rhr
            recoverySleepComponent = breakdown.sleep
            
            // Sleep performance
            let need = SleepAlgorithm.sleepNeedMinutes(priorDebtMinutes: 0, strainYesterday: 0)
            if let asleep = sleepMinutes {
                sleepPerformance = SleepAlgorithm.sleepPerformance(asleepMinutes: asleep, needMinutes: need)
            }
        }
        
        statusMessage = "Metrics ready"
    }
    
    // MARK: - DB Helpers
    
    struct RawSample {
        let timestamp: Date
        let heartRateBpm: Double?
        let rrIntervalMs: Double?
        let accelX: Double?
        let accelY: Double?
        let accelZ: Double?
        let spo2Pct: Double?
        let skinTempC: Double?
    }
    
    private func readSamplesFromDB(_ path: String) -> [RawSample] {
        // Use the Rust bridge to read decoded samples from SQLite
        // The bridge's metrics endpoints can extract sample data
        do {
            let result = try rust.request(method: "metrics.recent_samples", args: [
                "database_path": path,
                "limit": 10000,
            ])
            
            guard let rows = result["samples"] as? [[String: Any]] else { return [] }
            
            return rows.compactMap { row in
                guard let tsStr = row["ts_utc"] as? String else { return nil }
                let fmt = ISO8601DateFormatter()
                guard let ts = fmt.date(from: tsStr) else { return nil }
                
                return RawSample(
                    timestamp: ts,
                    heartRateBpm: row["heart_rate_bpm"] as? Double,
                    rrIntervalMs: row["rr_interval_ms"] as? Double,
                    accelX: row["accel_x"] as? Double,
                    accelY: row["accel_y"] as? Double,
                    accelZ: row["accel_z"] as? Double,
                    spo2Pct: row["spo2_pct"] as? Double,
                    skinTempC: row["skin_temp_c"] as? Double
                )
            }
        } catch {
            print("Yahup: DB read failed: \(error)")
            return []
        }
    }
    
    private func restingHrFromSamples(_ hrs: [Double]) -> Double? {
        guard !hrs.isEmpty else { return nil }
        let sorted = hrs.sorted()
        let idx = max(0, Int(Double(sorted.count) * 0.05) - 1)
        return sorted[idx]
    }
}

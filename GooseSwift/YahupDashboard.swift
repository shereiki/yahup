import SwiftUI

// MARK: - Yahup Dashboard
// Clean, dark, Bevel-inspired WHOOP alternative UI

struct YahupDashboard: View {
    @StateObject private var model = YahupModel()
    
    var body: some View {
        ZStack {
            Color(hex: "0A0A0C").ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerView
                    
                    // Status
                    statusBar
                    
                    // Main rings
                    metricsGrid
                    
                    // Detail cards
                    detailSection
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("yahup")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(model.connectionState == "ready" ? "Connected" : model.connectionState)
                    .font(.caption)
                    .foregroundColor(model.connectionState == "ready" ? Color.green : Color.gray)
            }
            Spacer()
            
            HStack(spacing: 12) {
                if model.connectionState == "ready" {
                    Button(action: model.startSync) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(model.isSyncing)
                }
                
                Button(action: model.connectionState == "ready" ? model.disconnect : model.connect) {
                    Text(model.connectionState == "ready" ? "Disconnect" : "Connect")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(model.connectionState == "ready" ? .red : .green)
            }
        }
    }
    
    // MARK: - Status
    private var statusBar: some View {
        HStack {
            Circle()
                .fill(model.connectionState == "ready" ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundColor(.gray)
            if model.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Spacer()
            if model.syncPacketCount > 0 {
                Text("\(model.syncPacketCount) pkts")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "141418"))
        .cornerRadius(8)
    }
    
    // MARK: - Main Metrics Grid
    private var metricsGrid: some View {
        VStack(spacing: 12) {
            // Recovery ring
            if let recovery = model.recoveryScore {
                MetricRingCard(
                    title: "Recovery",
                    value: Int(recovery.rounded()),
                    color: recoveryColor(Int(recovery.rounded())),
                    subtitle: recoveryLabel(Int(recovery.rounded())),
                    detail: recoveryDetail
                )
            }
            
            // Strain + Sleep row
            HStack(spacing: 12) {
                if let strain = model.strainScore {
                    MetricCard(
                        title: "Strain",
                        value: String(format: "%.1f", strain),
                        color: .orange,
                        icon: "flame.fill"
                    )
                }
                
                if let sleep = model.sleepMinutes {
                    MetricCard(
                        title: "Sleep",
                        value: "\(sleep / 60)h \(sleep % 60)m",
                        color: .purple,
                        icon: "moon.fill"
                    )
                }
            }
            
            // Vitals row
            HStack(spacing: 12) {
                if let hr = model.liveHeartRate {
                    VitalsCard(title: "HR", value: "\(Int(hr))", unit: "bpm", color: .red)
                }
                if let hrv = model.liveHRV {
                    VitalsCard(title: "HRV", value: String(format: "%.0f", hrv), unit: "ms", color: .green)
                }
                if let rhr = model.restingHeartRate {
                    VitalsCard(title: "RHR", value: "\(Int(rhr))", unit: "bpm", color: .blue)
                }
                if let rr = model.respiratoryRate {
                    VitalsCard(title: "Resp", value: String(format: "%.1f", rr), unit: "/min", color: .teal)
                }
            }
        }
    }
    
    // MARK: - Detail section
    private var detailSection: some View {
        VStack(spacing: 12) {
            if let stages = model.sleepStages {
                SleepBreakdownCard(stages: stages)
            }
            
            if let stress = model.stressAvg {
                DetailRow(title: "Avg Stress", value: String(format: "%.0f", stress), color: .orange)
            }
            if let cal = model.calories {
                DetailRow(title: "Calories", value: "\(Int(cal)) kcal", color: .yellow)
            }
            if let spo2 = model.spo2 {
                DetailRow(title: "SpO₂", value: String(format: "%.0f%%", spo2), color: .blue)
            }
            if let temp = model.skinTemp {
                DetailRow(title: "Skin Temp", value: String(format: "%.2f°C", temp), color: .orange)
            }
        }
    }
    
    // MARK: - Recovery helpers
    private var recoveryDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hrv = model.recoveryHrvComponent {
                Text("HRV: \(Int(hrv))").font(.caption2).foregroundColor(.gray)
            }
            if let rhr = model.recoveryRhrComponent {
                Text("RHR: \(Int(rhr))").font(.caption2).foregroundColor(.gray)
            }
            if let sleep = model.recoverySleepComponent {
                Text("Sleep: \(Int(sleep))").font(.caption2).foregroundColor(.gray)
            }
        }
    }
    
    private func recoveryColor(_ score: Int) -> Color {
        switch score {
        case 0..<34: return .red
        case 34..<67: return .yellow
        default: return .green
        }
    }
    
    private func recoveryLabel(_ score: Int) -> String {
        switch score {
        case 0..<34: return "Low"
        case 34..<67: return "Medium"
        default: return "High"
        }
    }
}

// MARK: - Metric Ring Card
struct MetricRingCard: View {
    let title: String
    let value: Int
    let color: Color
    let subtitle: String
    let detail: AnyView
    
    init(title: String, value: Int, color: Color, subtitle: String, @ViewBuilder detail: () -> some View) {
        self.title = title
        self.value = value
        self.color = color
        self.subtitle = subtitle
        self.detail = AnyView(detail())
    }
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: CGFloat(value) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: value)
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(color)
                detail
            }
            Spacer()
        }
        .padding(16)
        .background(Color(hex: "141418"))
        .cornerRadius(16)
    }
}

// MARK: - Metric Card
struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(hex: "141418"))
        .cornerRadius(14)
    }
}

// MARK: - Vitals Card
struct VitalsCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(hex: "141418"))
        .cornerRadius(10)
    }
}

// MARK: - Sleep Breakdown
struct SleepBreakdownCard: View {
    let stages: SleepAlgorithm.StageTotals
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Stages")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            
            HStack(spacing: 0) {
                StageBar(label: "Awake", minutes: stages.wake, total: stages.total, color: .orange)
                StageBar(label: "REM", minutes: stages.rem, total: stages.total, color: .purple)
                StageBar(label: "Light", minutes: stages.light, total: stages.total, color: .blue)
                StageBar(label: "Deep", minutes: stages.deep, total: stages.total, color: .green)
            }
            .frame(height: 24)
            .cornerRadius(6)
            
            HStack {
                ForEach([
                    ("Awake", stages.wake, Color.orange),
                    ("REM", stages.rem, Color.purple),
                    ("Light", stages.light, Color.blue),
                    ("Deep", stages.deep, Color.green),
                ], id: \.0) { label, min, color in
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text("\(label) \(min)m")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "141418"))
        .cornerRadius(14)
    }
}

struct StageBar: View {
    let label: String
    let minutes: Int
    let total: Int
    let color: Color
    
    var body: some View {
        color
            .frame(width: max(4, CGFloat(minutes) / CGFloat(max(1, total)) * 300))
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
        .padding(14)
        .background(Color(hex: "141418"))
        .cornerRadius(10)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

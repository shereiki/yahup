import SwiftUI

@main
struct YahupApp: App {
    @StateObject private var model = YahupModel()
    
    init() {
        GooseTheme.configureAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            YahupDashboard()
                .environmentObject(model)
        }
    }
}

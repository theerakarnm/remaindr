import SwiftUI

@main
struct AIUsageBarApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("AIUsageBar")
                .padding()
        } label: {
            Image(systemName: "gauge.with.needle")
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

@main
struct TransposerApp: App {
    init() {
        // Force the icon probe to sample the AU registry before ContentView
        // registers an in-process copy of our component.
        _ = IconDiagnostics.snapshot
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

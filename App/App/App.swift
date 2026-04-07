import SwiftUI

@main
struct BrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif
    }
}

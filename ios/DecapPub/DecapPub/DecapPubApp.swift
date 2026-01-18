import SwiftUI

@main
struct DecapPubApp: App {
    
    var body: some Scene {
        WindowGroup {
            if #available(iOS 26.0, *) {
                ContentView()
            } else {
                Text("This app requires iOS 26.0 or later")
                    .font(.title2)
                    .padding()
            }
        }
    }
}

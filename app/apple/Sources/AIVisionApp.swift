import SwiftUI

@main
struct AIVisionApp: App {
    @StateObject private var models = ModelStore()
    @StateObject private var profiles = GameProfileStore()
    var body: some Scene {
        WindowGroup { HomeView().environmentObject(models).environmentObject(profiles).task { await models.restore() } }
    }
}

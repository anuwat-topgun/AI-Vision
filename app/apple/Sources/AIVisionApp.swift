import SwiftUI

@main
struct AIVisionApp: App {
    @StateObject private var models = ModelStore()
    var body: some Scene {
        WindowGroup { HomeView().environmentObject(models).task { await models.restore() } }
    }
}

import SwiftUI
import SwiftData
import AppIntents
import DDPersistence
import DDIntents

@main
struct DungeonsAndDeadlinesApp: App {
    @State private var environment: AppEnvironment

    init() {
        LaunchOptions.applyBeforeLaunch()
        let environment = AppEnvironment()
        _environment = State(initialValue: environment)
        environment.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.announcer)
                .environment(environment.sync)
        }
        .modelContainer(DDStore.shared.container)
    }
}

/// Lets the app find the intents defined in the DDKit package.
struct AppIntentsPackages: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [DDIntentsPackage.self] }
}

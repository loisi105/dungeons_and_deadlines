import AppIntents
import SwiftUI
import WidgetKit
import DDIntents

@main
struct DDWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
        FocusControl()
    }
}

/// Lets the extension find the intents defined in the DDKit package.
struct WidgetIntentsPackages: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [DDIntentsPackage.self] }
}

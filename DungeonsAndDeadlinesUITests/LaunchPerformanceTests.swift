import XCTest

/// Measures cold launch to first frame. Run on demand:
/// ./build.sh test -only-testing:DungeonsAndDeadlinesUITests/LaunchPerformanceTests
@MainActor
final class LaunchPerformanceTests: XCTestCase {
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-seedDemo"]
            app.launch()
        }
    }
}

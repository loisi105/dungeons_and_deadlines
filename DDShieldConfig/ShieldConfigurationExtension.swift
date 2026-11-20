import ManagedSettings
import ManagedSettingsUI
import UIKit
import DDScreenTime

/// The screen shown instead of a blocked app while the focus timer runs, in the game's
/// pixel palette: the boss being fought and a way back to the fight.
/// Without a shield action extension, the button closes the blocked app.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(blocked: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(blocked: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(blocked: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(blocked: webDomain.domain)
    }

    // Night purple, cream and gold from the icon art.
    private static let night = UIColor(red: 0x23 / 255, green: 0x17 / 255, blue: 0x36 / 255, alpha: 1)
    private static let cream = UIColor(red: 0xFF / 255, green: 0xF6 / 255, blue: 0xD6 / 255, alpha: 1)
    private static let lavender = UIColor(red: 0xD6 / 255, green: 0xCB / 255, blue: 0xEE / 255, alpha: 1)
    private static let gold = UIColor(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x4A / 255, alpha: 1)
    private static let ink = UIColor(red: 0x1A / 255, green: 0x0D / 255, blue: 0x1F / 255, alpha: 1)

    private func make(blocked name: String?) -> ShieldConfiguration {
        let boss = ScreenTimeShield.bossName.flatMap { $0.isEmpty ? nil : $0 }
        let title = boss.map { String(localized: "\($0) is still standing") } ?? String(localized: "You're in a fight")
        let subtitle = name.map { String(localized: "\($0) is blocked while your focus timer runs.") }
            ?? String(localized: "This is blocked while your focus timer runs.")
        let icon = ScreenTimeShield.bossIconURL.flatMap { UIImage(contentsOfFile: $0.path) }
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: Self.night,
            icon: icon,
            title: .init(text: title, color: Self.cream),
            subtitle: .init(text: subtitle, color: Self.lavender),
            primaryButtonLabel: .init(text: String(localized: "Back to the fight"), color: Self.ink),
            primaryButtonBackgroundColor: Self.gold,
            secondaryButtonLabel: nil
        )
    }
}

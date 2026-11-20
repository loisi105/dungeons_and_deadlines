import SwiftUI
import GameCore
import DDPersistence
import DDDesign

/// Class selection as a navigation row + list. Unlike the system picker row,
/// every label here scales with Dynamic Type.
struct RolePickerRow: View {
    @Binding var role: Role?

    var body: some View {
        NavigationLink {
            RoleList(role: $role)
        } label: {
            HStack {
                Text("Class")
                Spacer()
                Group {
                    if let role { Text(role.title) } else { Text("None") }
                }
                .foregroundStyle(.readableSecondary)
                .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct RoleList: View {
    @Binding var role: Role?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true
    @State private var picks = 0

    var body: some View {
        List {
            Group {
                option(nil)
                ForEach(Role.allCases) { option($0) }
            }
            .dungeonRow()
        }
        .dungeonScreen()
        .navigationTitle("Class")
        .sensoryFeedback(.selection, trigger: picks) { _, _ in hapticsOn }
    }

    private func option(_ value: Role?) -> some View {
        Button {
            role = value
            picks += 1
            dismiss()
        } label: {
            HStack {
                Label {
                    if let value { Text(value.title) } else { Text("None") }
                } icon: {
                    Image(systemName: value?.symbol ?? "person")
                }
                Spacer()
                if role == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityAddTraits(role == value ? .isSelected : [])
    }
}

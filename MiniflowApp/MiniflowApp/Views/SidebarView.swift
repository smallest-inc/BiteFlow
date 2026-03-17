import SwiftUI

struct SidebarView: View {
    @ObservedObject var vm: AgentViewModel
    @Binding var selectedTab: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Brand
            VStack(alignment: .leading, spacing: 5) {
                Text("Miniflow ™")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("Turn your voice into polished text. Works in any site or app.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 18)

            // Primary nav
            VStack(spacing: 2) {
                navItem(tab: "home",       label: "Home",       icon: "house")
                navItem(tab: "dictionary", label: "Dictionary", icon: "book")
                navItem(tab: "shortcuts",  label: "Shortcuts",  icon: "scissors")
            }
            .padding(.horizontal, 6)

            Spacer()

            // Bottom nav
            VStack(spacing: 2) {
                navItem(tab: "settings", label: "Settings", icon: "gearshape")
            }
            .padding(.horizontal, 6)

            // User row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 26, height: 26)
                    Text(vm.userName.prefix(1).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(vm.userName.isEmpty ? "You" : vm.userName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: 210)
        .background(Color.bgWarm)
    }

    // MARK: - Nav Item

    private func navItem(tab: String, label: String, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selectedTab == tab ? Color.navActive : .clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
    }
}

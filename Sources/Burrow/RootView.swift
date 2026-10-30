import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            // A ZStack, so the old and new page overlap while they cross-fade instead of
            // sharing the width side by side.
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeader(page: model.page)
                        content
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 1400, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
                .overlayPreferenceValue(BottomBarKey.self, alignment: .bottom) { bar in
                    ZStack {
                        if let bar {
                            bar.view
                                .frame(maxWidth: 1000)
                                .padding(.horizontal, 36)
                                .padding(.bottom, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(Motion.spring, value: bar != nil)
                }
                .id(model.page)
                .transition(.blurFade)
            }
            .animation(Motion.page, value: model.page)
        }
        .background(AmbientBackground(tint: model.page.glow))
        .sheet(item: $model.session, onDismiss: model.sessionDismissed) { session in
            RunSheet(session: session)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .overview: OverviewPage(monitor: model.status)
        case .clean: CleanPage(scan: model.clean)
        case .uninstall: UninstallPage(catalog: model.apps, leftovers: model.leftovers)
        case .optimize: OptimizePage(scan: model.optimize)
        case .analyze: AnalyzePage(map: model.diskMap)
        case .projects: ProjectsPage(scan: model.purge)
        case .installers: InstallersPage(store: model.installers)
        case .slim: SlimPage(scan: model.slim)
        case .history: HistoryPage()
        case .settings: SettingsPage()
        }
    }
}

struct PageHeader: View {
    let page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
            Text(page.subtitle).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                BurrowMark().frame(width: 28, height: 28)
                Text("Burrow").font(.system(size: 17, weight: .semibold))
            }
            .padding(.leading, 10)
            .padding(.top, 44)
            .padding(.bottom, 22)

            ForEach(Page.allCases) { page in
                if page == .history { Spacer(minLength: 18) }
                SidebarItem(page: page, selected: model.page == page, busy: model.busy.contains(page),
                            namespace: selection) {
                    model.page = page
                }
            }
            Spacer()
            Text("Engine: Mole \(Mole.version)")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                .padding(.leading, 12).padding(.bottom, 18)
        }
        .padding(.horizontal, 12)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.35))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }
}

private struct SidebarItem: View {
    let page: Page
    let selected: Bool
    let busy: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: page.symbol).font(.system(size: 14, weight: .medium)).frame(width: 20)
                    .symbolEffect(.bounce, value: selected)
                Text(page.title).font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer()
                if busy {
                    PulseDot(color: selected ? page.glow.color : Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .foregroundStyle(selected ? Color.black : Color.white.opacity(hover ? 0.95 : 0.7))
            .background {
                if selected {
                    Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: namespace)
                } else if hover {
                    Capsule().fill(.white.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.spring, value: selected)
        .animation(Motion.quick, value: busy)
        .help(page.title + "  ⌘" + String(page.shortcut.character))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(busy ? "Scanning" : "")
    }
}

/// The app mark: a glowing orb with a dotted burrow below.
struct BurrowMark: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Glow.magenta.color, Glow.violet.color, Glow.blue.color.opacity(0.4)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 18))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
        }
    }
}

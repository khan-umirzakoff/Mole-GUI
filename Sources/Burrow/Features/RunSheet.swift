import SwiftUI

/// The live view of a running Mole command: progress, Mole's own log, and native
/// answers to its prompts (admin password, confirmations).
struct RunSheet: View {
    @ObservedObject var session: MoleSession
    @EnvironmentObject private var model: AppModel
    @ViewState private var password = ""
    @ViewState private var showLog = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.system(size: 22, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(statusText)
                        if !session.isFinished { Text("·"); Elapsed(since: session.started) }
                    }
                    .caption()
                    .contentTransition(.opacity)
                }
                Spacer()
                Orb(state: orbState).frame(width: 54, height: 54)
            }

            GlowCard(glow: glowForState, style: .core, padding: 18) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(session.lines.enumerated()), id: \.offset) { _, line in
                            LogLine(text: line)
                        }
                        if !session.live.isEmpty, !session.isFinished {
                            LogLine(text: session.live).opacity(0.75)
                        }
                        if session.lines.isEmpty, session.live.isEmpty {
                            Text("Starting Mole…").caption()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(showLog ? .automatic : .never)
            }
            .frame(height: showLog ? 420 : 240)
            .animation(Motion.spring, value: showLog)

            prompt
                .transition(.blurFade)

            HStack {
                Button(showLog ? "Smaller log" : "Larger log") { showLog.toggle() }
                    .buttonStyle(.pillSecondary)
                Spacer()
                if session.isFinished {
                    Button("Done") { model.closeSession() }
                        .buttonStyle(.pill)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Stop") { session.cancel() }.buttonStyle(.pillSecondary)
                        .help("Stops Mole the way Ctrl-C would, so Mole cleans up after itself")
                }
            }
        }
        .padding(28)
        .frame(width: 680)
        .background(Theme.background)
        .animation(Motion.spring, value: session.phase)
        .interactiveDismissDisabled(!session.isFinished)
    }

    @ViewBuilder private var prompt: some View {
        switch session.phase {
        case .needsPassword:
            GlowCard(glow: .violet, style: .rim, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Mole needs your administrator password for this step", systemImage: "lock.fill").cardTitle()
                    HStack {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Capsule().fill(.black.opacity(0.45)))
                            .focused($passwordFocused)
                            .onSubmit(sendPassword)
                        Button("Continue", action: sendPassword).buttonStyle(.pill)
                    }
                    Text("The password goes straight to macOS sudo and is never stored.").caption()
                }
            }
            .frame(height: 150)
            .onAppear { passwordFocused = true }
        case .needsAnswer(let question):
            GlowCard(glow: .ember, style: .rim, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(question.trimmingCharacters(in: CharacterSet(charactersIn: "➤→◎⊙ "))).cardTitle().lineLimit(3)
                    HStack(spacing: 10) {
                        ForEach(QuickReply.options(for: question), id: \.label) { option in
                            Button(option.label) { session.reply(option.keys) }
                                .buttonStyle(option.primary ? .pill : .pillSecondary)
                                .keyboardShortcut(option.primary ? .defaultAction : option.keys == "\u{1B}" ? .cancelAction : nil)
                        }
                    }
                }
            }
            .frame(height: 130)
        default:
            EmptyView()
        }
    }

    private func sendPassword() {
        guard !password.isEmpty else { return }
        session.submitPassword(password)
        password = ""
    }

    private var statusText: String {
        switch session.phase {
        case .running: "Working…"
        case .needsPassword: "Waiting for your password"
        case .needsAnswer: "Mole is asking you something"
        case .finished(let code): code == 0 ? "Finished" : code == 130 || code == 143 ? "Stopped" : "Mole stopped with code \(code)"
        }
    }

    private var orbState: Orb.State {
        switch session.phase {
        case .finished(let code): code == 0 ? .done : .failed
        case .running: .working
        default: .waiting
        }
    }

    private var glowForState: Glow {
        switch orbState {
        case .done: .sage
        case .failed: .ember
        case .waiting: .violet
        case .working: .blue
        }
    }
}

/// Buttons for a prompt Mole is showing, based on the keys it names.
struct QuickReply {
    let label: String
    let keys: String
    var primary = false

    static func options(for prompt: String) -> [QuickReply] {
        let p = prompt.lowercased()
        var options: [QuickReply] = []
        if p.contains("enter") {
            let verb = p.contains("confirm") ? "Confirm" : p.contains("continue") ? "Continue" : "Enter"
            options.append(.init(label: verb, keys: "\r", primary: true))
        }
        if p.contains("space") {
            options.append(.init(label: p.contains("skip") ? "Skip" : "Space", keys: " "))
        }
        if p.contains("y/n") {
            options.append(.init(label: "Yes", keys: "y\r", primary: options.isEmpty))
            options.append(.init(label: "No", keys: "n\r"))
        }
        if p.contains("esc") || p.contains("cancel") || p.contains("quit") {
            options.append(.init(label: "Cancel", keys: "\u{1B}"))
        }
        if options.isEmpty {
            options = [.init(label: "Enter", keys: "\r", primary: true), .init(label: "Cancel", keys: "\u{1B}")]
        }
        return options
    }
}

private struct LogLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(icon).foregroundStyle(iconColor).frame(width: 12)
            Text(body(of: text))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(text.hasPrefix("➤") ? .white : Theme.secondaryText)
                .fontWeight(text.hasPrefix("➤") ? .semibold : .regular)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var icon: String {
        guard let f = text.first, "→✓✗◎⊙➤⚙".contains(f) else { return "" }
        return String(f)
    }

    private var iconColor: Color {
        switch text.first {
        case "✓": Theme.accent
        case "✗": Theme.danger
        case "→": .white.opacity(0.7)
        default: Theme.tertiaryText
        }
    }

    private func body(of s: String) -> String {
        icon.isEmpty ? s : String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

/// A breathing orb that shows the state of the run.
struct Orb: View {
    enum State { case working, waiting, done, failed }
    let state: State
    @ViewState private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).blur(radius: 12).scaleEffect(pulse ? 1.15 : 0.85)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.9), color, color.opacity(0.3)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 30))
                .overlay(Circle().strokeBorder(.white.opacity(0.4)))
            if state == .done { Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.black) }
            if state == .failed { Image(systemName: "exclamationmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.black) }
        }
        .animation(Motion.spring, value: state)
        .onAppear {
            guard !Motion.reduced else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .done: "Finished"
        case .failed: "Stopped"
        }
    }

    private var color: Color {
        switch state {
        case .working: Glow.blue.color
        case .waiting: Glow.violet.color
        case .done: Theme.accent
        case .failed: Theme.danger
        }
    }
}

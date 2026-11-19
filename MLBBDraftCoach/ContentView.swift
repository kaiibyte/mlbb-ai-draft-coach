
import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var selectedTab = "Draft"
    @State private var speaking = false
    @State private var showInfo = false
    @StateObject private var heroAPI = HeroAPI()

    private let tabs = ["Draft", "Heroes", "Meta", "Settings"]
    private let synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.055, blue: 0.12),
                    Color(red: 0.10, green: 0.10, blue: 0.22),
                    Color(red: 0.04, green: 0.16, blue: 0.19)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 280)
                .blur(radius: 90)
                .offset(x: 150, y: -280)

            Circle()
                .fill(Color.purple.opacity(0.20))
                .frame(width: 260)
                .blur(radius: 100)
                .offset(x: -150, y: 100)

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        switch selectedTab {
                        case "Draft":
                            draftScreen
                        case "Heroes":
                            heroesScreen
                        case "Meta":
                            placeholderScreen("Meta", description: "Ranked statistics and current hero rankings will appear here.")
                        default:
                            placeholderScreen("Settings", description: "Voice and app preferences will appear here.")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 30)
                }

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selectedTab)
        .task {
            await heroAPI.loadHeroes()
        }
        .alert("Draft Coach", isPresented: $showInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Your voice-first MLBB draft assistant is being built. Hero data is loaded from the community hero database.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DRAFT COACH")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.cyan)

                Text("MLBB Assistant")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
            }

            Spacer()

            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var draftScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR DRAFT")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.55))

                    Text("Make the winning pick.")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 27))
                    .foregroundStyle(.cyan)
            }

            HStack(spacing: 10) {
                statusPill("HERO API", heroAPI.heroes.isEmpty ? "Loading" : "Connected")
                statusPill("AI", "Local mode")
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("TEAM COMPOSITION")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))

                HStack(spacing: 10) {
                    teamCard("YOUR TEAM", color: .cyan)
                    teamCard("ENEMY TEAM", color: .pink)
                }
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("VOICE COACH")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))

                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 27))
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your draft assistant")
                            .font(.system(size: 16, weight: .bold))

                        Text("Hear announcements and hero information.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Button {
                    speak("Welcome to MLBB Draft Coach. Your voice assistant is ready. Open the Heroes tab to hear hero names and roles.")
                } label: {
                    Label(
                        speaking ? "Stop voice" : "Test voice coach",
                        systemImage: speaking ? "stop.fill" : "speaker.wave.2.fill"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [.cyan, Color(red: 0.25, green: 0.48, blue: 0.95)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .glassCard()

            Text("LIVE DRAFT TOOLS")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 10) {
                toolCard("Hero database", "person.3.fill")
                toolCard("Patch updates", "arrow.trianglehead.2.clockwise")
                toolCard("Voice coach", "waveform")
            }
        }
    }

    private var heroesScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HERO DATABASE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.cyan)

                Text("Meet the heroes.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))

                Text("Tap a speaker to hear the hero's name and role.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                Label("\(heroAPI.heroes.count) heroes", systemImage: "person.3.fill")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button {
                    Task {
                        await heroAPI.loadHeroes()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(heroAPI.isLoading)
            }
            .foregroundStyle(.cyan)
            .glassCard()

            if heroAPI.isLoading && heroAPI.heroes.isEmpty {
                ProgressView("Loading heroes...")
                    .tint(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(30)
                    .glassCard()
            } else if let error = heroAPI.errorMessage,
                      heroAPI.heroes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)

                    Text("Couldn't load heroes")
                        .font(.system(size: 17, weight: .bold))

                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

                    Button("Try again") {
                        Task {
                            await heroAPI.loadHeroes()
                        }
                    }
                    .foregroundStyle(.cyan)
                }
                .frame(maxWidth: .infinity)
                .glassCard()
            } else {
                VStack(spacing: 9) {
                    ForEach(heroAPI.heroes) { hero in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(hero.name)
                                    .font(.system(size: 15, weight: .bold))

                                Text([
                                    hero.role,
                                    hero.lane
                                ].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.55))
                            }

                            Spacer()

                            Button {
                                speak("\(hero.name). Role: \(hero.role.isEmpty ? "Unknown" : hero.role). Lane: \(hero.lane.isEmpty ? "Unknown" : hero.lane).")
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 42, height: 42)
                                    .background(.white.opacity(0.07), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(13)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                    }
                }
                .glassCard()

                Button {
                    let announcement = heroAPI.heroes.prefix(40).map {
                        "\($0.name), role \($0.role.isEmpty ? "unknown" : $0.role)"
                    }.joined(separator: ". ")

                    speak("Here are the heroes. \(announcement)")
                } label: {
                    Label("Read hero list aloud", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.cyan, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }

            if let updated = heroAPI.lastUpdated {
                Text("Last updated: \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func placeholderScreen(_ title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(description)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
        .glassCard()
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: iconFor(tab))
                            .font(.system(size: 18, weight: .semibold))

                        Text(tab)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(
                        selectedTab == tab ? .cyan : .white.opacity(0.48)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
    }

    private func statusPill(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.orange)
                .frame(width: 6, height: 6)

            Text(title)
                .fontWeight(.bold)

            Text(value)
                .foregroundStyle(.white.opacity(0.65))
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10)))
    }

    private func teamCard(_ title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(color)

            ForEach(0..<5) { index in
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Empty slot \(index + 1)")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.48))
                .padding(9)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolCard(_ title: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.cyan)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 85, alignment: .leading)
        .glassCard()
    }

    private func iconFor(_ tab: String) -> String {
        switch tab {
        case "Draft": return "rectangle.stack.fill"
        case "Heroes": return "person.3"
        case "Meta": return "chart.bar.fill"
        default: return "gearshape.fill"
        }
    }

    private func speak(_ message: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            speaking = false

            if message == "STOP" {
                return
            }
        }

        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.48
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        speaking = true
        synthesizer.speak(utterance)
    }
}

extension View {
    func glassCard() -> some View {
        self
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

#Preview {
    ContentView()
}

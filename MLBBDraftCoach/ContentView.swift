
import SwiftUI

struct ContentView: View {
    @StateObject private var heroAPI = HeroAPI()
    @StateObject private var screenCapture = ScreenCaptureManager()
    @StateObject private var recognition = DraftRecognitionManager()
    @StateObject private var draftAPI = DraftAPI()
    @StateObject private var voiceCoach = VoiceCoach()

    @State private var allied: [String] = []
    @State private var enemy: [String] = []
    @State private var selectedLane = "Gold"
    @State private var selectedRank = "glory"
    @State private var isYourTurn = false
    @State private var selectedTab = "Draft"

    private let lanes = ["Gold", "EXP", "Mid", "Jungle", "Roam"]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.10),
                    Color(red: 0.10, green: 0.07, blue: 0.19),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                draftScreen
                    .tabItem {
                        Label("Draft", systemImage: "gamecontroller")
                    }
                    .tag("Draft")

                heroesScreen
                    .tabItem {
                        Label("Heroes", systemImage: "person.3")
                    }
                    .tag("Heroes")

                settingsScreen
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag("Settings")
            }
            .tint(.purple)
        }
        .preferredColorScheme(.dark)
        .task {
            await heroAPI.loadHeroes()
        }
        .onChange(of: screenCapture.recognizedText) { _, lines in
            recognition.process(
                recognizedLines: lines,
                heroes: heroAPI.heroes
            )
        }
    }

    private var draftScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    captureCard

                    recognizedHeroesCard

                    laneCard

                    teamCard(
                        title: "Your Team",
                        heroes: allied,
                        color: .cyan
                    )

                    teamCard(
                        title: "Enemy Team",
                        heroes: enemy,
                        color: .red
                    )

                    turnCard

                    analysisCard

                    voiceCard
                }
                .padding()
            }
            .background(Color.clear)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MLBB DRAFT COACH")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(.purple)

            Text("Draft Assistant")
                .font(.system(size: 30, weight: .bold))

            Text("Live recognition • AI recommendations")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("LIVE SCREEN RECOGNITION")

                HStack {
                    Circle()
                        .fill(screenCapture.isCapturing ? .green : .gray)
                        .frame(width: 9, height: 9)

                    Text(screenCapture.status)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                HStack {
                    Button {
                        screenCapture.startScreenCapture()
                    } label: {
                        Label("Start Capture", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(screenCapture.isCapturing)

                    Button {
                        screenCapture.stopScreenCapture()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!screenCapture.isCapturing)
                }

                Text("OCR scans visible text on your selected screen.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text("OCR scans: \(screenCapture.framesReceived)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var recognizedHeroesCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("RECOGNIZED HEROES")

                if recognition.detectedHeroes.isEmpty {
                    Text("No confirmed hero names yet.")
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(recognition.detectedHeroes, id: \.self) { hero in
                        HStack {
                            Text(hero)
                                .fontWeight(.medium)

                            Spacer()

                            Button("Your Team") {
                                addHero(hero, to: .ally)
                            }
                            .buttonStyle(.bordered)
                            .tint(.cyan)

                            Button("Enemy") {
                                addHero(hero, to: .enemy)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .font(.caption)
                    }
                }

                Text("Assign recognized heroes to the correct team. OCR does not determine team or ban slots.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var laneCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("YOUR LANE")

                Picker("Lane", selection: $selectedLane) {
                    ForEach(lanes, id: \.self) { lane in
                        Text(lane).tag(lane)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Rank", selection: $selectedRank) {
                    Text("Epic").tag("epic")
                    Text("Legend").tag("legend")
                    Text("Mythic").tag("mythic")
                    Text("Honor").tag("honor")
                    Text("Glory").tag("glory")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private enum Team {
        case ally
        case enemy
    }

    private func teamCard(
        title: String,
        heroes: [String],
        color: Color
    ) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(title)

                if heroes.isEmpty {
                    Text("No heroes added.")
                        .foregroundStyle(.white.opacity(0.5))
                }

                ForEach(heroes, id: \.self) { hero in
                    HStack {
                        Text(hero)
                        Spacer()
                        Button {
                            removeHero(hero, from: title == "Your Team" ? .ally : .enemy)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            .foregroundStyle(color)
        }
    }

    private var turnCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("DRAFT TURN")

                Toggle("It's my turn to pick", isOn: $isYourTurn)
                    .tint(.purple)
                    .onChange(of: isYourTurn) { _, newValue in
                        if !newValue {
                            voiceCoach.stop()
                        }
                    }

                Text("Turn detection is manual until the game screen layout is validated.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var analysisCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("AI DRAFT ANALYSIS")

                Button {
                    Task {
                        await analyzeDraft()
                    }
                } label: {
                    HStack {
                        if draftAPI.isLoading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(draftAPI.isLoading ? "Analyzing..." : "Analyze Draft")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(draftAPI.isLoading)

                if let error = draftAPI.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if !draftAPI.recommendation.isEmpty {
                    Text(draftAPI.recommendation)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .padding(.top, 5)
                }
            }
        }
    }

    private var voiceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("VOICE COACH")

                HStack {
                    Button {
                        announceRecommendation()
                    } label: {
                        Label("Announce Pick", systemImage: "speaker.wave.2")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    Button {
                        voiceCoach.replay()
                    } label: {
                        Label("Replay", systemImage: "repeat")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        voiceCoach.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }
        }
    }

    private var heroesScreen: some View {
        NavigationStack {
            List {
                if heroAPI.isLoading {
                    ProgressView("Loading heroes...")
                }

                if let error = heroAPI.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }

                ForEach(heroAPI.heroes.filter {
                    $0.name.lowercased() != "wanwan"
                }) { hero in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hero.name)
                            .fontWeight(.semibold)

                        Text("\(hero.role) • \(hero.lane)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Hero Catalogue")
            .toolbar {
                Button {
                    Task {
                        await heroAPI.loadHeroes()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private var settingsScreen: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    LabeledContent("Hero source", value: "MLBBDex")
                    LabeledContent("AI provider", value: "Groq")
                    LabeledContent("Excluded hero", value: "Wanwan")
                }

                Section("Recognition") {
                    Text("Screen capture requires your permission.")
                    Text("Hero names are recognized locally using Apple Vision.")
                    Text("Team assignment and turn detection are not automatic yet.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func card<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(1.3)
            .foregroundStyle(.purple)
    }

    private func addHero(_ hero: String, to team: Team) {
        switch team {
        case .ally:
            enemy.removeAll { $0 == hero }
            if !allied.contains(hero) {
                allied.append(hero)
            }
        case .enemy:
            allied.removeAll { $0 == hero }
            if !enemy.contains(hero) {
                enemy.append(hero)
            }
        }
    }

    private func removeHero(_ hero: String, from team: Team) {
        switch team {
        case .ally:
            allied.removeAll { $0 == hero }
        case .enemy:
            enemy.removeAll { $0 == hero }
        }
    }

    private func analyzeDraft() async {
        await draftAPI.analyze(
            allied: allied,
            enemy: enemy,
            lane: selectedLane,
            rank: selectedRank
        )

        if isYourTurn {
            announceRecommendation()
        }
    }

    private func announceRecommendation() {
        let availableNames = heroAPI.heroes
            .map(\.name)
            .filter { $0.lowercased() != "wanwan" }

        let recommendation = draftAPI.recommendation.lowercased()

        let matches = availableNames.filter {
            recommendation.contains($0.lowercased())
        }

        guard let bestPick = matches.first else { return }

        let alternatives = matches
            .filter { $0 != bestPick }

        voiceCoach.announce(
            bestPick: bestPick,
            alternatives: alternatives,
            isYourTurn: isYourTurn
        )
    }
}

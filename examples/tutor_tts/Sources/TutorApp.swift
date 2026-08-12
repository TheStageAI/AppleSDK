import SwiftUI

// --------------------------------------------------------------------------------------
// TutorApp — SwiftUI shell for the mixed-language streaming TTS demo
// --------------------------------------------------------------------------------------
@main
struct TutorApp: App {
    @StateObject private var model = TutorModel()

    var body: some Scene {
        WindowGroup {
            TutorRootView()
                .environmentObject(model)
        }
    }
}

// --------------------------------------------------------------------------------------
// TutorRootView
// --------------------------------------------------------------------------------------
struct TutorRootView: View {
    @EnvironmentObject private var model: TutorModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Picker("Phrase", selection: __phrase_binding) {
                            ForEach(model.phrases) { phrase in
                                Text(phrase.title).tag(phrase)
                            }
                        }
                        .disabled(model.running)
                    }

                    Section("Tagged script") {
                        TextEditor(text: $model.taggedPreview)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 280)
                            .disabled(model.running)
                            .accessibilityLabel("Tagged script")
                    }

                    Section("Status") {
                        Text(model.status)
                            .font(.subheadline)
                        if !model.stats.isEmpty {
                            Text(model.stats)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if model.loading {
                            ProgressView(value: model.loadFraction) {
                                Text(model.loadPhase ?? "loading")
                                    .font(.caption)
                            }
                        }
                    }
                }
                __controls
            }
            .navigationTitle("Tutor TTS")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ----------------------------------------------------------------------------------
    // Private Methods / Views
    // ----------------------------------------------------------------------------------
    private var __phrase_binding: Binding<TutorPhrase> {
        Binding(
            get: { model.selected },
            set: { model.select($0) }
        )
    }

    private var __controls: some View {
        HStack(spacing: 12) {
            Button {
                model.load()
            } label: {
                Label(
                    model.loaded ? "Loaded" : "Load model",
                    systemImage: "arrow.down.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.loading || model.running || model.loaded)

            Button {
                if model.running { model.stop() } else { model.play() }
            } label: {
                Label(
                    model.running ? "Stop" : "Play stream",
                    systemImage: model.running ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.loading || (!model.loaded && !model.running))
        }
        .padding(16)
        .background(.bar)
    }
}

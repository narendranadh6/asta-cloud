import SwiftUI

@MainActor
@Observable
final class RadioViewModel {
    var genre = "All"
    private(set) var stations: [RadioStation] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    static let genres = ["All", "Telugu", "Hindi", "Tamil", "Bollywood", "Lofi", "Jazz", "Pop",
                         "Classical", "Rock", "Devotional", "News"]

    func load(api: MusicAPI, language: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let languages = ["Telugu", "Hindi", "Tamil"]
        let tag: String? = genre == "All" ? language?.lowercased() : genre.lowercased()
        let useLanguage = languages.contains(genre) ? genre.lowercased() : nil
        do {
            stations = try await api.radioStations(
                tag: useLanguage == nil ? tag : nil, language: useLanguage, query: nil, limit: 40)
        } catch {
            self.error = error
        }
    }
}

struct RadioView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var model = RadioViewModel()

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                ChipBar(options: RadioViewModel.genres, selection: $model.genre) { $0 }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if model.isLoading && model.stations.isEmpty {
                LoadingStateView(message: "Finding live stations…").listRowBackground(Color.clear)
            } else if let error = model.error, model.stations.isEmpty {
                ErrorStateView(error: error) {
                    Task { await model.load(api: app.api, language: settings.preferredLanguage) }
                }
                .listRowBackground(Color.clear)
            } else if model.stations.isEmpty {
                ContentUnavailableView("No live stations", systemImage: "antenna.radiowaves.left.and.right",
                                       description: Text("Try another genre."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.stations) { station in
                        stationRow(station)
                    }
                } footer: {
                    Text("Live stations from the community Radio Browser directory. Streams are broadcast by each station.")
                        .font(.caption2)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .haloScreen()
        .navigationTitle("Live Radio")
        .task(id: model.genre) { await model.load(api: app.api, language: settings.preferredLanguage) }
        .refreshable { await model.load(api: app.api, language: settings.preferredLanguage) }
        .safeAreaInset(edge: .bottom) {
            if let station = app.radio.station {
                RadioNowPlayingBar(station: station)
            }
        }
    }

    private func stationRow(_ station: RadioStation) -> some View {
        let isCurrent = app.radio.station?.id == station.id
        return Button {
            app.radio.toggle(station)
            Haptics.tap(enabled: settings.hapticsEnabled)
        } label: {
            HStack(spacing: Spacing.sm) {
                AsyncImage(url: station.favicon.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(HaloColor.cool)
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).font(HaloFont.headline).foregroundStyle(HaloColor.text).lineLimit(1)
                    Text([station.tags.prefix(3).joined(separator: " · "), station.countryCode]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.caption).foregroundStyle(HaloColor.mutedText).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: isCurrent && app.radio.status != .idle ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(isCurrent ? HaloColor.primary : HaloColor.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(station.name), live radio")
        .accessibilityHint(isCurrent ? "Stops the station" : "Plays the station")
    }
}

struct RadioNowPlayingBar: View {
    @Environment(AppModel.self) private var app
    var station: RadioStation

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(HaloColor.primary)
                .symbolEffect(.variableColor.iterative, isActive: app.radio.status == .playing)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(statusText).font(.caption).foregroundStyle(HaloColor.mutedText)
            }
            Spacer()
            Button { app.radio.stop() } label: {
                Image(systemName: "stop.fill").font(.title3)
            }
            .accessibilityLabel("Stop radio")
        }
        .padding(Spacing.sm)
        .haloCard()
        .padding(.horizontal, Spacing.sm)
    }

    private var statusText: String {
        switch app.radio.status {
        case .idle: "Stopped"
        case .connecting: "Connecting…"
        case .playing: "Live now"
        case let .failed(message): message
        }
    }
}

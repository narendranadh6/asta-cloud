#if canImport(SwiftData)
import Foundation

extension Track {
    /// Rebuilds a playable Track from a stored reference.
    init(storedID: String, title: String, artist: String, album: String?, artwork: String?,
         duration: Int?, sourceRaw: String, stream: String?, isPreview: Bool, external: String?) {
        let source = TrackSource(rawValue: sourceRaw) ?? .unknown
        let sourceID = storedID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? storedID
        self.init(
            id: storedID, source: source, sourceId: sourceID, title: title, artist: artist,
            album: album, artworkUrl: artwork, durationSeconds: duration, streamUrl: stream,
            isPreview: isPreview, externalUrl: external,
            attribution: Attribution(
                provider: source,
                label: source == .itunes ? "Preview courtesy of Apple Music" : source.label,
                url: external))
    }

    init(entity: TrackEntity) {
        self.init(
            storedID: entity.trackID, title: entity.title, artist: entity.artist,
            album: entity.album, artwork: entity.artworkURLString,
            duration: entity.durationSeconds, sourceRaw: entity.sourceRaw,
            stream: entity.streamURLString, isPreview: entity.isPreview,
            external: entity.externalURLString)
    }

    init(item: PlaylistItemEntity) {
        self.init(
            storedID: item.trackID, title: item.title, artist: item.artist, album: item.album,
            artwork: item.artworkURLString, duration: item.durationSeconds,
            sourceRaw: item.sourceRaw, stream: item.streamURLString, isPreview: item.isPreview,
            external: nil)
    }

    /// Any displayable item as a playable Track (used where lists mix stored and live rows).
    init(displayable: any TrackDisplayable) {
        if let track = displayable as? Track {
            self = track
        } else if let entity = displayable as? TrackEntity {
            self.init(entity: entity)
        } else if let item = displayable as? PlaylistItemEntity {
            self.init(item: item)
        } else {
            self.init(
                storedID: displayable.trackID, title: displayable.title,
                artist: displayable.artist, album: nil,
                artwork: displayable.artworkURL?.absoluteString,
                duration: displayable.durationSeconds, sourceRaw: "unknown", stream: nil,
                isPreview: displayable.isPreview, external: nil)
        }
    }
}

#endif

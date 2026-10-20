#if canImport(SwiftData)
import Foundation

extension Track {
    /// Rebuilds a displayable Track from a stored reference. The watch URL is derived
    /// from the validated id, never from stored text.
    init(reference: any TrackDisplayable, provider: MetadataProvider) {
        let watch = YouTubeIdentifier.watchURL(videoID: reference.videoId)?.absoluteString ?? ""
        var thumbnails: [String: Thumbnail] = [:]
        if let url = reference.artworkURL {
            thumbnails["high"] = Thumbnail(url: url.absoluteString)
        }
        self.init(
            videoId: reference.videoId, title: reference.title,
            channelTitle: reference.channelTitle, thumbnails: thumbnails,
            durationSeconds: reference.durationSeconds, watchUrl: watch,
            attribution: Attribution(
                provider: provider,
                label: "YouTube",
                url: watch))
    }

    init(entity: TrackEntity) {
        self.init(reference: entity, provider: MetadataProvider(rawValue: entity.providerRaw) ?? .youtube)
    }

    init(item: PlaylistItemEntity) {
        self.init(reference: item, provider: MetadataProvider(rawValue: item.providerRaw) ?? .youtube)
    }
}
#endif

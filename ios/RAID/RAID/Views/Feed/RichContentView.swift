// RichContentView.swift
// RAID Golf
//
// Renders Nostr text content with tappable links, inline images, and @mentions.

import SwiftUI
import AVKit
import NostrSDK

struct RichContentView: View {
    let content: String
    var profiles: [String: NostrProfile] = [:]
    var font: Font = .subheadline
    var imageMaxHeight: CGFloat = 300

    var body: some View {
        let parsed = Self.parse(content, profiles: profiles)
        VStack(alignment: .leading, spacing: 8) {
            if !parsed.text.characters.isEmpty {
                Text(parsed.text)
                    .font(font)
                    .tint(.accentColor)
            }

            ForEach(parsed.media) { item in
                switch item {
                case .image(let url):
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            EmptyView()
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                                .frame(height: 200)
                                .overlay(ProgressView())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: imageMaxHeight, alignment: .leading)

                case .gif(let url):
                    AnimatedGIFView(url: url)
                        .frame(maxWidth: .infinity, maxHeight: imageMaxHeight, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                case .video(let url):
                    InlineVideoPlayer(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(height: imageMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Parsing

    enum MediaItem: Identifiable {
        case image(URL)
        case gif(URL)
        case video(URL)

        var id: String {
            switch self {
            case .image(let url), .gif(let url), .video(let url):
                return url.absoluteString
            }
        }
    }

    struct ParsedContent {
        let text: AttributedString
        let media: [MediaItem]
    }

    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"(https?://[^\s]+)|(nostr:(?:npub|note|nevent|nprofile|naddr)1[a-z0-9]+)"#,
        options: .caseInsensitive
    )

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "svg"]
    private static let gifExtensions: Set<String> = ["gif"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]

    /// Extracts hex pubkeys from all nostr:npub mentions in the content.
    nonisolated static func mentionedPubkeys(in content: String) -> [String] {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        let pattern = try! NSRegularExpression(
            pattern: #"nostr:npub1[a-z0-9]+"#, options: .caseInsensitive
        )
        return pattern.matches(in: content, range: range).compactMap { match in
            let bech32 = String(nsContent.substring(with: match.range).dropFirst(6))
            return (try? PublicKey.parse(publicKey: bech32))?.toHex()
        }
    }

    static func parse(_ content: String, profiles: [String: NostrProfile]) -> ParsedContent {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = tokenPattern.matches(in: content, range: fullRange)

        var attributed = AttributedString()
        var media: [MediaItem] = []
        var lastEnd = 0

        for match in matches {
            let matchRange = match.range

            // Append text before this match
            if matchRange.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                attributed.append(AttributedString(nsContent.substring(with: beforeRange)))
            }

            let matched = nsContent.substring(with: matchRange)

            if matched.lowercased().hasPrefix("nostr:") {
                handleNostrURI(matched, profiles: profiles, attributed: &attributed)
            } else {
                handleURL(matched, attributed: &attributed, media: &media)
            }

            lastEnd = matchRange.location + matchRange.length
        }

        // Append remaining text
        if lastEnd < nsContent.length {
            attributed.append(AttributedString(nsContent.substring(from: lastEnd)))
        }

        return ParsedContent(text: attributed, media: media)
    }

    private static func handleNostrURI(
        _ matched: String,
        profiles: [String: NostrProfile],
        attributed: inout AttributedString
    ) {
        let bech32 = String(matched.dropFirst(6)) // remove "nostr:"

        if bech32.lowercased().hasPrefix("npub") {
            if let pubkey = try? PublicKey.parse(publicKey: bech32) {
                let hex = pubkey.toHex()
                let displayName = profiles[hex]?.displayLabel
                    ?? String(bech32.prefix(12)) + "..."
                var segment = AttributedString("@\(displayName)")
                segment.link = URL(string: "raid://profile/\(hex)")
                attributed.append(segment)
            } else {
                attributed.append(AttributedString(matched))
            }
        } else if bech32.lowercased().hasPrefix("note")
                    || bech32.lowercased().hasPrefix("nevent") {
            var segment = AttributedString(String(bech32.prefix(16)) + "...")
            segment.foregroundColor = .accentColor
            attributed.append(segment)
        } else {
            attributed.append(AttributedString(matched))
        }
    }

    private static func handleURL(
        _ matched: String,
        attributed: inout AttributedString,
        media: inout [MediaItem]
    ) {
        // Clean trailing punctuation that's not part of the URL
        var urlString = matched
        let hasOpenParen = urlString.contains("(")
        while let last = urlString.last {
            let char = String(last)
            if char == ")" && hasOpenParen { break }
            if [".", ",", ")", "]", ";", ":", "!", "?"].contains(char) {
                urlString = String(urlString.dropLast())
            } else {
                break
            }
        }

        // Trailing chars that were stripped
        let trailing = matched.count > urlString.count
            ? String(matched.suffix(matched.count - urlString.count))
            : ""

        if let url = URL(string: urlString) {
            let pathExt = url.pathExtension.lowercased()
            if imageExtensions.contains(pathExt) {
                media.append(.image(url))
            } else if gifExtensions.contains(pathExt) {
                media.append(.gif(url))
            } else if videoExtensions.contains(pathExt) {
                media.append(.video(url))
            } else {
                let displayText = url.host ?? urlString
                var segment = AttributedString(displayText)
                segment.link = url
                attributed.append(segment)
            }
        } else {
            attributed.append(AttributedString(matched))
        }

        if !trailing.isEmpty {
            attributed.append(AttributedString(trailing))
        }
    }
}

// MARK: - Animated GIF View

/// Loads a GIF from a URL and plays it with full animation via UIImageView.
private struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        imageView.image = nil

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }
            let source = CGImageSourceCreateWithData(data as CFData, nil)
            guard let source else { return }

            let count = CGImageSourceGetCount(source)
            var images: [UIImage] = []
            var duration: Double = 0

            for i in 0..<count {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                    images.append(UIImage(cgImage: cgImage))
                }
                if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    let delay = gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                        ?? gif[kCGImagePropertyGIFDelayTime as String] as? Double
                        ?? 0.1
                    duration += delay
                }
            }

            DispatchQueue.main.async {
                imageView.animationImages = images
                imageView.animationDuration = duration
                imageView.startAnimating()
                // Also set static image as fallback
                imageView.image = images.first
            }
        }
        task.resume()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }
}

// MARK: - Inline Video Player

/// Plays a video URL inline with standard AVKit controls (muted autoplay, tap to unmute).
private struct InlineVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.isMuted = true
            p.play()
            player = p
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

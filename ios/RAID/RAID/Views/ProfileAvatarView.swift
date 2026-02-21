// ProfileAvatarView.swift
// RAID Golf
//
// Reusable circular profile avatar with in-memory NSCache backing.
// Unlike AsyncImage, cached images survive LazyVStack cell recycling
// with zero flicker — the NSCache lookup is synchronous in the body.

import SwiftUI

struct ProfileAvatarView: View {
    let pictureURL: String?
    var size: CGFloat = 40

    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFill()
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: pictureURL) {
            guard resolvedImage == nil else { return }
            await downloadImage()
        }
    }

    /// Check @State first (current lifecycle), then NSCache (survives recycling).
    private var resolvedImage: UIImage? {
        if let img = loadedImage { return img }
        guard let key = pictureURL else { return nil }
        return AvatarImageCache.shared.image(for: key)
    }

    private func downloadImage() async {
        guard let urlString = pictureURL,
              let url = URL(string: urlString) else { return }

        // NSCache hit (race: another cell may have loaded it)
        if let cached = AvatarImageCache.shared.image(for: urlString) {
            loadedImage = cached
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            AvatarImageCache.shared.setImage(image, for: urlString)
            loadedImage = image
        } catch {
            // Keep placeholder on failure
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }
}

/// In-memory image cache that survives view recycling.
/// NSCache auto-evicts under memory pressure; URLCache (200MB disk) backs the re-download.
final class AvatarImageCache: @unchecked Sendable {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

// CourseImageCache.swift
// RAID Golf
//
// NSCache-backed image loader for course thumbnails.
// Mirrors AvatarImageCache pattern: synchronous cache lookup in view body
// eliminates AsyncImage flicker on LazyHStack cell recycling.

import UIKit

final class CourseImageCache: @unchecked Sendable {
    static let shared = CourseImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
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

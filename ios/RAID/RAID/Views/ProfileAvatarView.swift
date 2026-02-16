// ProfileAvatarView.swift
// RAID Golf
//
// Reusable circular profile avatar with AsyncImage and placeholder fallback.

import SwiftUI

struct ProfileAvatarView: View {
    let pictureURL: String?
    var size: CGFloat = 40

    var body: some View {
        if let urlString = pictureURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().renderingMode(.original).scaledToFill()
                default:
                    placeholderIcon
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

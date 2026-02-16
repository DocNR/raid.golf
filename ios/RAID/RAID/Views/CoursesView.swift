// CoursesView.swift
// RAID Golf
//
// Course discovery and browsing.
// Placeholder for future kind 33501 course discovery, geo-clustering, and verified badges.

import SwiftUI

struct CoursesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Courses", systemImage: "mappin.and.ellipse")
            } description: {
                Text("Browse courses, check tee sets, and see who's playing. Coming soon.")
            }
            .navigationTitle("Courses")
            .avatarToolbar()
        }
    }
}

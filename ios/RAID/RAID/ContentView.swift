// ContentView.swift
// RAID Golf - iOS Port
//
// Placeholder main view (Phase 1)
// Real UI implementation in Phase 4

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.golf")
                .imageScale(.large)
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            
            Text("RAID Golf")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("iOS Port - Phase 1 Setup Complete")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Next: Phase 2 - Kernel Implementation")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
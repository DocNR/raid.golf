// ContentView.swift
// RAID Golf - iOS Port
//
// Placeholder main view (Phase 1)
// Real UI implementation in Phase 4

import SwiftUI
import GRDB

struct ContentView: View {
    let dbQueue: DatabaseQueue

    var body: some View {
        TrendsView(dbQueue: dbQueue)
    }
}

#Preview {
    let dbQueue = try! DatabaseQueue.createRAIDDatabase(at: ":memory:")
    return ContentView(dbQueue: dbQueue)
}
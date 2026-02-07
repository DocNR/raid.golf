// ContentView.swift
// RAID Golf - iOS Port
//
// Phase 4C: TabView navigation (Trends + Sessions)

import SwiftUI
import GRDB

struct ContentView: View {
    let dbQueue: DatabaseQueue

    var body: some View {
        TabView {
            TrendsView(dbQueue: dbQueue)
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }

            SessionsView(dbQueue: dbQueue)
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet")
                }
        }
    }
}

#Preview {
    let dbQueue = try! DatabaseQueue.createRAIDDatabase(at: ":memory:")
    return ContentView(dbQueue: dbQueue)
}

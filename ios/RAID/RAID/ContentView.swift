// ContentView.swift
// RAID Golf
//
// TabView navigation (Trends + Sessions + Rounds)

import SwiftUI
import GRDB

struct ContentView: View {
    let dbQueue: DatabaseQueue

    @AppStorage("hasSeenFirstRun") private var hasSeenFirstRun = false
    @State private var showFirstRun = false

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

            RoundsView(dbQueue: dbQueue)
                .tabItem {
                    Label("Rounds", systemImage: "flag.fill")
                }

            TemplateListView(dbQueue: dbQueue)
                .tabItem {
                    Label("Templates", systemImage: "list.clipboard")
                }
        }
        .sheet(isPresented: $showFirstRun, onDismiss: {
            hasSeenFirstRun = true
        }) {
            FirstRunSheetView()
        }
        .onAppear {
            if !hasSeenFirstRun {
                showFirstRun = true
            }
        }
    }
}

#Preview {
    let dbQueue = try! DatabaseQueue.createRAIDDatabase(at: ":memory:")
    return ContentView(dbQueue: dbQueue)
}

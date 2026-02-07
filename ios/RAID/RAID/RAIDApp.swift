// RAIDApp.swift
// RAID Golf - iOS Port
//
// Main app entry point (Phase 1 placeholder)

import SwiftUI
import GRDB

@main
struct RAIDApp: App {
    private let dbQueue: DatabaseQueue = {
        do {
            let supportDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = supportDir.appendingPathComponent("raid_ios.sqlite")
            return try DatabaseQueue.createRAIDDatabase(at: dbURL.path)
        } catch {
            fatalError("Failed to initialize RAID database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(dbQueue: dbQueue)
        }
    }
}
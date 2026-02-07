// RAIDApp.swift
// RAID Golf - iOS Port
//
// Phase 4C: App entry point with template bootstrap

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
                .task { await bootstrapTemplates() }
        }
    }

    /// Load seed templates into database (idempotent, non-fatal).
    /// Runs async so it doesn't block UI init.
    private func bootstrapTemplates() async {
        do {
            try await Task.detached(priority: .utility) { [dbQueue] in
                try TemplateBootstrap.loadSeeds(into: dbQueue)
            }.value
        } catch {
            print("[RAID] Template bootstrap failed (non-fatal): \(error)")
        }
    }
}

/// Kernel-safe template bootstrap.
/// Loads bundled seed templates via the repository insert path.
/// Idempotent: duplicate inserts are caught and ignored (PK constraint).
enum TemplateBootstrap {
    static func loadSeeds(into dbQueue: DatabaseQueue) throws {
        guard let seedURL = Bundle.main.url(forResource: "template_seeds", withExtension: "json") else {
            print("[RAID] template_seeds.json not found in bundle — skipping bootstrap")
            return
        }

        let seedData = try Data(contentsOf: seedURL)
        guard let seeds = try JSONSerialization.jsonObject(with: seedData) as? [[String: Any]] else {
            print("[RAID] template_seeds.json is not a JSON array — skipping bootstrap")
            return
        }

        let repo = TemplateRepository(dbQueue: dbQueue)

        for seed in seeds {
            let templateJSON = try JSONSerialization.data(withJSONObject: seed)
            do {
                let record = try repo.insertTemplate(rawJSON: templateJSON)
                print("[RAID] Template bootstrapped: \(record.club) hash=\(record.hash.prefix(12))…")
            } catch {
                // Expected on subsequent launches (PK constraint on template_hash).
                // Also handles any other non-fatal error.
            }
        }
    }
}

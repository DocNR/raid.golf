// RAIDApp.swift
// Gambit Golf
//
// App entry point with template bootstrap

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
            fatalError("Failed to initialize database: \(error)")
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
            print("[Gambit] Template bootstrap failed (non-fatal): \(error)")
        }
    }
}

/// Kernel-safe template bootstrap.
/// Loads bundled seed templates via the repository insert path.
/// Creates preference rows and sets first template as active for each club.
/// Idempotent: duplicate inserts are caught and ignored (PK constraint + INSERT OR IGNORE).
enum TemplateBootstrap {
    static func loadSeeds(into dbQueue: DatabaseQueue) throws {
        guard let seedURL = Bundle.main.url(forResource: "template_seeds", withExtension: "json") else {
            print("[Gambit] template_seeds.json not found in bundle — skipping bootstrap")
            return
        }

        let seedData = try Data(contentsOf: seedURL)
        guard let seeds = try JSONSerialization.jsonObject(with: seedData) as? [[String: Any]] else {
            print("[Gambit] template_seeds.json is not a JSON array — skipping bootstrap")
            return
        }

        let templateRepo = TemplateRepository(dbQueue: dbQueue)
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        for seed in seeds {
            let templateJSON = try JSONSerialization.data(withJSONObject: seed)
            do {
                let record = try templateRepo.insertTemplate(rawJSON: templateJSON)
                print("[Gambit] Template bootstrapped: \(record.club) hash=\(record.hash.prefix(12))…")

                // Ensure preference row exists for this template
                try prefsRepo.ensurePreferenceExists(forHash: record.hash, club: record.club)

                // Set as active if no active template exists for this club
                let activeTemplate = try prefsRepo.fetchActiveTemplate(forClub: record.club)
                if activeTemplate == nil {
                    try prefsRepo.setActive(templateHash: record.hash, club: record.club)
                    print("[Gambit] Set \(record.club) as active (first template for club)")
                }
            } catch {
                // Expected on subsequent launches (PK constraint on template_hash).
                // Also handles any other non-fatal error.
            }
        }
    }
}

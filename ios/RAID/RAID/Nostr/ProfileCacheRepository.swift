// ProfileCacheRepository.swift
// RAID Golf
//
// Persistent cache for Nostr profile metadata (kind 0 events).
// Backed by nostr_profiles table (v9 migration). Mutable, no immutability triggers.
// Profiles are upserted on each fetch — always reflects the latest relay data.

import Foundation
import GRDB

class ProfileCacheRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Upsert a single profile. Updates all fields on conflict.
    func upsertProfile(_ profile: NostrProfile) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO nostr_profiles
                    (pubkey_hex, name, display_name, picture, about, banner, nip05, cached_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (pubkey_hex) DO UPDATE SET
                    name = excluded.name,
                    display_name = excluded.display_name,
                    picture = excluded.picture,
                    about = excluded.about,
                    banner = excluded.banner,
                    nip05 = excluded.nip05,
                    cached_at = excluded.cached_at
                """,
                arguments: [
                    profile.pubkeyHex,
                    profile.name,
                    profile.displayName,
                    profile.picture,
                    profile.about,
                    profile.banner,
                    profile.nip05,
                    now
                ]
            )
        }
    }

    /// Batch upsert. Wraps all inserts in one write transaction.
    func upsertProfiles(_ profiles: [NostrProfile]) throws {
        guard !profiles.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            for profile in profiles {
                try db.execute(
                    sql: """
                    INSERT INTO nostr_profiles
                        (pubkey_hex, name, display_name, picture, about, banner, nip05, cached_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (pubkey_hex) DO UPDATE SET
                        name = excluded.name,
                        display_name = excluded.display_name,
                        picture = excluded.picture,
                        about = excluded.about,
                        banner = excluded.banner,
                        nip05 = excluded.nip05,
                        cached_at = excluded.cached_at
                    """,
                    arguments: [
                        profile.pubkeyHex,
                        profile.name,
                        profile.displayName,
                        profile.picture,
                        profile.about,
                        profile.banner,
                        profile.nip05,
                        now
                    ]
                )
            }
        }
    }

    /// Fetch one profile by pubkey hex. Returns nil if not cached.
    func fetchProfile(pubkeyHex: String) throws -> NostrProfile? {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM nostr_profiles WHERE pubkey_hex = ? LIMIT 1",
                arguments: [pubkeyHex])
            return rows.first.map { rowToProfile($0) }
        }
    }

    /// Full-text search over name, display_name, and nip05.
    /// Minimum 2-character query should be enforced by the caller.
    func searchProfiles(query: String, limit: Int = 20) throws -> [NostrProfile] {
        let q = "%\(query)%"
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT * FROM nostr_profiles
                WHERE name LIKE ? OR display_name LIKE ? OR nip05 LIKE ?
                ORDER BY
                    CASE
                        WHEN display_name LIKE ? THEN 0
                        WHEN name LIKE ? THEN 1
                        ELSE 2
                    END,
                    COALESCE(display_name, name, pubkey_hex) ASC
                LIMIT ?
                """,
                arguments: [q, q, q, q, q, limit])
            return rows.map { rowToProfile($0) }
        }
    }

    /// Return all cached pubkey hex strings.
    func allCachedPubkeys() throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT pubkey_hex FROM nostr_profiles")
            return rows.map { $0["pubkey_hex"] as String }
        }
    }

    // MARK: - Private

    private func rowToProfile(_ row: Row) -> NostrProfile {
        NostrProfile(
            pubkeyHex: row["pubkey_hex"],
            name: row["name"],
            displayName: row["display_name"],
            picture: row["picture"],
            about: row["about"],
            banner: row["banner"],
            nip05: row["nip05"]
        )
    }
}

// TemplatePreferencesRepository.swift
// RAID Golf
//
// Template Preferences (non-kernel product layer)
//
// Purpose:
// - Manage mutable preferences for KPI templates
// - Handle display names, active/hidden status
// - Transactional template activation (deactivate others, activate target)
//
// Design:
// - NOT a kernel repository (operates on mutable template_preferences table)
// - Preference layer on top of immutable kpi_templates
// - Active template uniqueness enforced via partial unique index

import Foundation
import GRDB

// MARK: - Template Preference Record

struct TemplatePreference {
    let templateHash: String
    let club: String
    let displayName: String?
    let isActive: Bool
    let isHidden: Bool
    let updatedAt: String
}

// MARK: - Template Preferences Repository

class TemplatePreferencesRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Read Operations

    /// Fetch preference for a specific template hash
    /// - Parameter hash: Template hash
    /// - Returns: Template preference if it exists, nil otherwise
    /// - Throws: Database error
    func fetchPreference(forHash hash: String) throws -> TemplatePreference? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT * FROM template_preferences WHERE template_hash = ?",
                arguments: [hash]) else {
                return nil
            }

            return TemplatePreference(
                templateHash: row["template_hash"],
                club: row["club"],
                displayName: row["display_name"],
                isActive: (row["is_active"] as Int) == 1,
                isHidden: (row["is_hidden"] as Int) == 1,
                updatedAt: row["updated_at"]
            )
        }
    }

    /// Fetch the active template record for a club (joins to kpi_templates)
    /// - Parameter club: Club identifier (e.g., "7i", "PW")
    /// - Returns: The full TemplateRecord for the active template, or nil if none is active
    /// - Throws: Database error
    func fetchActiveTemplate(forClub club: String) throws -> TemplateRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT t.template_hash, t.schema_version, t.club, t.canonical_json, t.created_at, t.imported_at
                FROM kpi_templates t
                INNER JOIN template_preferences tp ON t.template_hash = tp.template_hash
                WHERE tp.club = ? AND tp.is_active = 1
                """, arguments: [club]) else {
                return nil
            }

            return TemplateRecord(
                hash: row["template_hash"],
                schemaVersion: row["schema_version"],
                club: row["club"],
                canonicalJSON: row["canonical_json"],
                createdAt: row["created_at"],
                importedAt: row["imported_at"]
            )
        }
    }

    // MARK: - Write Operations

    /// Ensure a preference row exists for a template (INSERT OR IGNORE with defaults)
    /// - Parameters:
    ///   - hash: Template hash
    ///   - club: Club identifier
    /// - Throws: Database error
    func ensurePreferenceExists(forHash hash: String, club: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO template_preferences
                    (template_hash, club, display_name, is_active, is_hidden, updated_at)
                VALUES (?, ?, NULL, 0, 0, ?)
                """,
                arguments: [hash, club, now]
            )
        }
    }

    /// Set a template as active for its club. Transactional:
    /// 1. Deactivate any currently-active template for the same club
    /// 2. Ensure preference row exists for the target template
    /// 3. Activate the specified template
    /// - Parameters:
    ///   - templateHash: Template hash to activate
    ///   - club: Club identifier
    /// - Throws: Database error
    func setActive(templateHash: String, club: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            // 1. Deactivate any currently-active template for the same club
            try db.execute(
                sql: """
                UPDATE template_preferences
                SET is_active = 0, updated_at = ?
                WHERE club = ? AND is_active = 1
                """,
                arguments: [now, club]
            )

            // 2. Ensure preference row exists for the target template
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO template_preferences
                    (template_hash, club, display_name, is_active, is_hidden, updated_at)
                VALUES (?, ?, NULL, 0, 0, ?)
                """,
                arguments: [templateHash, club, now]
            )

            // 3. Activate the target template
            try db.execute(
                sql: """
                UPDATE template_preferences
                SET is_active = 1, updated_at = ?
                WHERE template_hash = ?
                """,
                arguments: [now, templateHash]
            )
        }
    }

    /// Update display name for a template
    /// - Parameters:
    ///   - templateHash: Template hash
    ///   - name: Display name (nil to clear)
    /// - Throws: Database error
    func setDisplayName(templateHash: String, name: String?) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE template_preferences
                SET display_name = ?, updated_at = ?
                WHERE template_hash = ?
                """,
                arguments: [name, now, templateHash]
            )
        }
    }

    /// Set hidden status for a template
    /// - Parameters:
    ///   - templateHash: Template hash
    ///   - hidden: Hidden status
    /// - Throws: Database error
    func setHidden(templateHash: String, hidden: Bool) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE template_preferences
                SET is_hidden = ?, updated_at = ?
                WHERE template_hash = ?
                """,
                arguments: [hidden ? 1 : 0, now, templateHash]
            )
        }
    }
}

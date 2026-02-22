// ParsedCourse.swift
// RAID Golf
//
// Data model for a parsed kind 33501 course event.
// Pure value type — no database or network dependencies.

import Foundation

struct ParsedCourse: Identifiable, Hashable {
    var id: String { dTag }

    let dTag: String
    let authorHex: String
    let title: String
    let location: String
    let country: String?
    let holes: [ParsedHole]
    let tees: [ParsedTee]
    let yardages: [ParsedYardage]
    let content: String?
    let website: String?
    let architect: String?
    let established: String?
    let operatorPubkey: String?
    let eventId: String
    let eventCreatedAt: UInt64

    struct ParsedHole: Hashable, Codable {
        let number: Int
        let par: Int
        let handicap: Int
    }

    struct ParsedTee: Hashable, Codable {
        let name: String
        let rating: Double
        let slope: Int
    }

    struct ParsedYardage: Hashable, Codable {
        let hole: Int
        let tee: String
        let yards: Int
    }

    // MARK: - Helpers

    /// Yardages for a specific tee, keyed by hole number.
    func yardages(forTee tee: String) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for y in yardages where y.tee == tee {
            result[y.hole] = y.yards
        }
        return result
    }

    /// Total yardage for a specific tee.
    func totalYardage(forTee tee: String) -> Int {
        yardages.filter { $0.tee == tee }.reduce(0) { $0 + $1.yards }
    }

    /// Total par computed from hole definitions.
    func totalPar() -> Int {
        holes.reduce(0) { $0 + $1.par }
    }
}

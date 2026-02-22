// CoursesViewModel.swift
// RAID Golf
//
// Two-phase load for course discovery:
// Phase A: instant paint from GRDB cache
// Phase B: relay fetch + cache upsert

import Foundation
import Observation

@Observable
class CoursesViewModel {
    var courses: [ParsedCourse] = []
    var isLoading = false
    var isBackgroundRefreshing = false
    var searchQuery = ""
    var errorMessage: String?

    private var hasLoaded = false

    var filteredCourses: [ParsedCourse] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return courses }
        return courses.filter {
            $0.title.lowercased().contains(q) ||
            $0.location.lowercased().contains(q)
        }
    }

    /// Phase A (cache) + Phase B (relay). Call once from .task.
    func loadIfNeeded(nostrService: NostrService, cacheRepo: CourseCacheRepository) async {
        guard !hasLoaded else { return }
        hasLoaded = true

        // Phase A: paint from cache
        do {
            let cached = try cacheRepo.fetchAllCourses()
            courses = cached
        } catch {
            print("[RAID][Courses] Cache read failed: \(error)")
        }

        // Phase B: relay fetch
        await refresh(nostrService: nostrService, cacheRepo: cacheRepo)
    }

    /// Phase B only. Call from pull-to-refresh.
    func refresh(nostrService: NostrService, cacheRepo: CourseCacheRepository) async {
        if courses.isEmpty {
            isLoading = true
        } else {
            isBackgroundRefreshing = true
        }

        defer {
            isLoading = false
            isBackgroundRefreshing = false
        }

        do {
            let events = try await nostrService.fetchCourses()
            var rawJSONs: [String: String] = [:]
            var parsed: [ParsedCourse] = []

            for event in events {
                guard let course = CourseEventParser.parse(event: event) else { continue }
                rawJSONs[course.dTag] = (try? event.asJson()) ?? "{}"
                parsed.append(course)
            }

            if !parsed.isEmpty {
                try cacheRepo.upsertCourses(parsed, rawJSONs: rawJSONs)
            }

            // Re-read from cache for consistent sort order
            let all = try cacheRepo.fetchAllCourses()
            courses = all
            errorMessage = nil
        } catch {
            print("[RAID][Courses] Relay fetch failed: \(error)")
            errorMessage = "Failed to load courses: \(error.localizedDescription)"
        }
    }

    /// Clear all state (sign-out cleanup).
    func reset() {
        courses = []
        hasLoaded = false
        isLoading = false
        isBackgroundRefreshing = false
        searchQuery = ""
        errorMessage = nil
    }
}

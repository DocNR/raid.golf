// CourseDetailView.swift
// RAID Golf
//
// Pure course profile: hero image, metadata, tee picker, collapsible scorecard.
// "Start Round" presents RoundSetupView as sheet. Favorite toggle in toolbar.

import SwiftUI
import GRDB

struct CourseDetailView: View {
    let course: ParsedCourse
    let dbQueue: DatabaseQueue
    let onRoundCreated: (Int64, String, [String], Bool) -> Void
    var isFavorited: Bool = false
    var onFavoriteToggle: (() -> Void)? = nil

    @State private var selectedTee: ParsedCourse.ParsedTee?
    @State private var showScorecard = false
    @State private var showRoundSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroImage
                courseMetadata
                teePickerCard
                scorecardSection
                startRoundButton
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let toggle = onFavoriteToggle {
                    Button {
                        toggle()
                    } label: {
                        Image(systemName: isFavorited ? "star.fill" : "star")
                            .foregroundStyle(isFavorited ? .orange : .secondary)
                    }
                }
            }
        }
        .onAppear {
            if selectedTee == nil, let first = course.tees.first {
                selectedTee = first
            }
        }
        .sheet(isPresented: $showRoundSetup) {
            RoundSetupView(
                dbQueue: dbQueue,
                course: course,
                preselectedTee: selectedTee,
                onRoundCreated: onRoundCreated
            )
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = course.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                case .failure:
                    imagePlaceholder
                case .empty:
                    imagePlaceholder
                        .overlay(ProgressView())
                @unknown default:
                    imagePlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius))
        }
    }

    @ViewBuilder
    private var imagePlaceholder: some View {
        LinearGradient(
            colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 200)
    }

    // MARK: - Course Metadata (inline, no card)

    @ViewBuilder
    private var courseMetadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.location)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let content = course.content, !content.isEmpty {
                Text(content)
                    .font(.subheadline)
            }

            HStack(spacing: 16) {
                if let architect = course.architect {
                    Label(architect, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let year = course.established {
                    Label(year, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let website = course.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tee Picker Card

    @ViewBuilder
    private var teePickerCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tees")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("Tees", selection: $selectedTee) {
                    ForEach(course.tees, id: \.self) { tee in
                        Text(tee.name).tag(Optional(tee))
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }

            if let tee = selectedTee {
                HStack(spacing: 16) {
                    Label("Rating \(tee.rating, specifier: "%.1f")", systemImage: "chart.bar")
                    Label("Slope \(tee.slope)", systemImage: "arrow.up.right")
                    Spacer()
                    let yards = course.totalYardage(forTee: tee.name)
                    if yards > 0 {
                        Text("\(yards) yds")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .scorecardCardStyle()
    }

    // MARK: - Scorecard (Collapsible)

    @ViewBuilder
    private var scorecardSection: some View {
        if let tee = selectedTee {
            DisclosureGroup("Scorecard", isExpanded: $showScorecard) {
                CourseScorecardPreview(
                    course: course,
                    teeName: tee.name,
                    playerLabels: []
                )
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
            .tint(.secondary)
            .padding()
            .scorecardCardStyle()
        }
    }

    // MARK: - Start Round Button

    @ViewBuilder
    private var startRoundButton: some View {
        Button {
            showRoundSetup = true
        } label: {
            Text("Start Round")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(selectedTee == nil)
    }
}

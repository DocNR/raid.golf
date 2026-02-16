// PracticeView.swift
// RAID Golf
//
// Consolidated practice hub. Accessed from the side drawer.
// Combines Sessions (with CSV import), Trends, and Templates via segmented control.
// Each child view keeps its own NavigationStack — zero modifications to existing views.

import SwiftUI
import GRDB

struct PracticeView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedSection) {
                    Text("Sessions").tag(0)
                    Text("Trends").tag(1)
                    Text("Templates").tag(2)
                }
                .pickerStyle(.segmented)

                Button("Done") { dismiss() }
                    .padding(.leading, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            switch selectedSection {
            case 0: SessionsView(dbQueue: dbQueue)
            case 1: TrendsView(dbQueue: dbQueue)
            default: TemplateListView(dbQueue: dbQueue)
            }
        }
    }
}

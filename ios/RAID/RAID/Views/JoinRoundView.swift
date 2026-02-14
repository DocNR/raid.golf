// JoinRoundView.swift
// Gambit Golf
//
// Join a multi-device round by pasting a nevent invite code.
// Flow: paste nevent → fetch kind 1501 from relays → verify → create local round.

import SwiftUI
import GRDB
import NostrSDK

struct JoinRoundView: View {
    let dbQueue: DatabaseQueue
    let onJoined: (Int64, String) -> Void  // (roundId, courseHash)

    @Environment(\.dismiss) private var dismiss
    @State private var inviteText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste nevent or nostr: URI", text: $inviteText, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Round Invite")
                } footer: {
                    Text("Paste the invite code shared by the round creator.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Join Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Join") { joinRound() }
                            .disabled(inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func joinRound() {
        let trimmed = inviteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                // 1. Parse nevent from input (handle both raw nevent and nostr: URI)
                let nevent: String
                if let parsed = RoundInviteBuilder.parseNostrURI(uri: trimmed) {
                    nevent = parsed
                } else if trimmed.hasPrefix("nevent1") {
                    nevent = trimmed
                } else {
                    throw RoundJoinError.initiationNotFound
                }

                let (eventIdHex, _) = try RoundInviteBuilder.parseNevent(nevent: nevent)

                // 2. Check if already joined locally
                let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
                if let existing = try nostrRepo.fetchRound(byInitiationEventId: eventIdHex) {
                    // Already joined — navigate to existing round
                    let courseHash = try await dbQueue.read { db in
                        try String.fetchOne(
                            db,
                            sql: "SELECT course_hash FROM rounds WHERE round_id = ?",
                            arguments: [existing.roundId]
                        )
                    }
                    await MainActor.run {
                        isLoading = false
                        dismiss()
                        if let courseHash {
                            onJoined(existing.roundId, courseHash)
                        }
                    }
                    return
                }

                // 3. Fetch kind 1501 from relays
                guard let event = try await NostrClient.fetchEvent(eventIdHex: eventIdHex) else {
                    throw RoundJoinError.initiationNotFound
                }

                // 4. Parse content and tags
                let content = try NIP101gEventParser.parseInitiationContent(json: event.content())

                // Extract tags as [[String]]
                let tags = event.tags().toVec().map { tag -> [String] in
                    tag.asVec()
                }
                let tagData = NIP101gEventParser.parseInitiationTags(tagArrays: tags)

                // 5. Verify hashes (warn but allow join if failed)
                if let courseHash = tagData.courseHash, let rulesHash = tagData.rulesHash {
                    let hashesValid = try NIP101gEventParser.verifyHashes(
                        content: content,
                        courseHash: courseHash,
                        rulesHash: rulesHash
                    )
                    if !hashesValid {
                        print("[Gambit] Hash verification failed for initiation \(eventIdHex) — proceeding anyway (embedded content is authoritative)")
                    }
                }

                // 6. Get my pubkey
                let keyManager = try KeyManager.loadOrCreate()
                let myPubkey = keyManager.signingKeys().publicKey().toHex()

                // 7. Create local round
                let date = tagData.date ?? ISO8601DateFormatter().string(from: Date())
                let service = RoundJoinService(dbQueue: dbQueue)
                let roundId = try service.createLocalRound(
                    from: content,
                    initiationEventId: eventIdHex,
                    date: date,
                    playerPubkeys: tagData.playerPubkeys,
                    myPubkey: myPubkey
                )

                // 8. Get course hash for navigation
                let courseHash = try await dbQueue.read { db in
                    try String.fetchOne(
                        db,
                        sql: "SELECT course_hash FROM rounds WHERE round_id = ?",
                        arguments: [roundId]
                    )
                }

                await MainActor.run {
                    isLoading = false
                    dismiss()
                    if let courseHash {
                        onJoined(roundId, courseHash)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

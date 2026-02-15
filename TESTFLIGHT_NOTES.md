# Gambit Golf — TestFlight Beta Notes

Thank you for testing Gambit Golf.

## What to Test

1. **CSV Import**: Import a Rapsodo MLM2Pro CSV file. Verify shot counts match your CSV. Check that clubs and metrics appear correctly.

2. **Trends**: View trends for different clubs and metrics. Verify A-only trends filter by active template.

3. **Templates**: Create, rename, hide, and duplicate templates. Set active templates per club. Verify templates affect shot grading.

4. **Scorecard**: Create a round (solo or multiplayer), enter scores hole-by-hole, and complete the round. In multiplayer, verify the round-robin flow (P1 then P2 per hole) and the review screen showing all players' scores. Verify scores save correctly and appear in round history.

5. **Nostr Posting**: Complete a round and tap "Post to Nostr". Verify the note appears on a Nostr client (e.g., Damus, Primal). Check your profile view for npub/nsec.

6. **Multiplayer Rounds (Same-Device)**: Create a round and add players from your Nostr follow list or by entering their npub. Score for all players using the round-robin flow. Verify per-player progress tracking and the review scorecard before finishing.

7. **Multi-Device Rounds**: Create a multi-device round (toggle on Create Round screen). After creating, a setup screen with QR code appears. Have a second player scan or paste the nevent invite on another device to join. Score on both devices independently. Verify live scorecard updates appear in the "View Scores" sheet (QR icon in toolbar). Verify final scores from both players appear in round detail after both finish.

## Known Issues

- **B-001: Club name normalization**: If your CSV uses "7 Iron" and your template uses "7i", they won't match. This will be addressed in a future update. For now, use the club picker when creating templates to ensure exact matches.

- **B-005: Multi-device round completion UX**: If you finish a multi-device round before the other player, the review screen may show stale scores. The full final scores will appear correctly in the round detail view after both players finish.

- **B-006: Camera QR scanning not yet implemented**: To join a multi-device round, you must paste the nevent invite text. Camera-based QR scanning will be added in a future update.

- **B-007: No signature verification on remote scores**: Remote scores from kind 1502/30501 events are not yet verified against the round's player roster. This will be hardened in a future security update.

- **No cloud sync**: All data is local. Deleting the app deletes your data.

## How to Report Bugs

1. Use the TestFlight feedback form (shake your device while in the app).
2. Include steps to reproduce, expected behavior, and actual behavior.
3. Screenshots are helpful.

## Privacy

- All practice and round data is stored locally in SQLite on your device.
- Nostr posting is opt-in. You control what gets posted.
- The app does not include analytics, tracking, or telemetry.

## Build Info

This is an early beta. Expect rough edges. Your feedback helps shape the product.

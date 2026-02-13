# Gambit Golf — TestFlight Beta Notes

Thank you for testing Gambit Golf.

## What to Test

1. **CSV Import**: Import a Rapsodo MLM2Pro CSV file. Verify shot counts match your CSV. Check that clubs and metrics appear correctly.

2. **Trends**: View trends for different clubs and metrics. Verify A-only trends filter by active template.

3. **Templates**: Create, rename, hide, and duplicate templates. Set active templates per club. Verify templates affect shot grading.

4. **Scorecard**: Create a round, enter scores hole-by-hole, and complete the round. Verify scores save correctly and appear in round history.

5. **Nostr Posting**: Complete a round and tap "Post to Nostr". Verify the note appears on a Nostr client (e.g., Damus, Primal). Check your profile view for npub/nsec.

## Known Issues

- **B-001: Club name normalization**: If your CSV uses "7 Iron" and your template uses "7i", they won't match. This will be addressed in a future update. For now, use the club picker when creating templates to ensure exact matches.

- **No multiplayer**: Rounds are single-player only. Multiplayer scorecards are not implemented yet.

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

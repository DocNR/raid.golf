# Gambit Golf

Practice analytics for golfers. Import Rapsodo CSV files, track your range sessions with A/B/C shot grading, score your rounds, and optionally share via Nostr. All data stored locally on your device.

## Quick Start

1. **Import Practice Data**: Tap the Sessions tab and import a Rapsodo CSV file. Your shots are automatically classified as A, B, or C based on KPI templates.

2. **View Trends**: Tap the Trends tab to see how your shot quality evolves over time. Filter by club and metric (carry, ball speed, etc.).

3. **Manage Templates**: Tap the Templates tab to view, create, or customize KPI templates. Templates define what makes an A, B, or C shot for each club. A starter 7-iron template is included.

4. **Record Rounds**: Tap the Rounds tab to score rounds hole-by-hole, solo or with other players. Add players from your Nostr follow list or by npub. Track your scores over time. Optionally post your scorecards to Nostr.

## Nostr Integration

Gambit Golf includes optional Nostr integration for social sharing. Your Nostr keypair is auto-generated on first use and stored securely in the iOS Keychain. You can post completed rounds to Nostr relays. Posting is opt-in and entirely under your control.

To view your Nostr identity and relay settings, tap the profile button (person icon) on the Rounds tab.

## Known Limitations

- **Club name matching**: Template-to-shot matching uses exact string comparison. If your CSV uses "7i" and your template uses "7 Iron", they won't match. The club picker in template creation sources names from imported shots to help avoid this issue.

- **Local-first by design**: All data is stored locally in SQLite on your device. There is no cloud sync. Deleting the app deletes your data.

- **Same-device multiplayer**: Multiplayer rounds are scored on a single device (pass-and-play). Multi-device score sync is not yet implemented.

## Requirements

- iOS 17.0 or later
- Rapsodo MLM2Pro CSV export (for practice data import)

## License

RAID Golf kernel and analysis framework: see repository root for license details.

iOS app (Gambit Golf): proprietary, not open source.

## Support

For bugs or feedback, open an issue on the GitHub repository or use the TestFlight feedback form if you're a beta tester.

# RAID Golf — TestFlight Beta Notes

Thank you for testing RAID Golf.

---

## What's New in This Build

### Onboarding
- First-run welcome sheet with three paths: Create Account, Sign In, or Skip (guest mode)
- New account creation publishes a Nostr profile (kind 0) on completion
- Sign In supports nsec (full access) or npub (read-only browsing)
- Contextual activation prompts appear at natural moments for guest-mode users: after your 3rd round, after completing a round, and after 5+ practice sessions. Each prompt is dismissable and stops appearing after 3 dismissals.
- Settings consolidated into a single sheet (gear icon in the side drawer): Keys & Relays, About, and Sign Out in one place.

### Social Feed
- Rich content rendering: inline images, animated GIFs, inline video, tappable URLs, and @mentions that resolve to display names and link to user profiles
- Tapping an @mention opens that user's profile sheet directly in-app

### Identity
- npub read-only sign-in: sign in with just your public key to browse feeds and profiles without exposing your secret key. Publishing is disabled in read-only mode (react, comment, post buttons are hidden).
- Sign-out now fully resets the feed and clears cached profile images, so re-sign-in or switching accounts always shows fresh content.

---

## What to Test

### Onboarding (new users)
1. Delete the app and reinstall. Verify the welcome sheet appears on first launch.
2. Test all three paths: Create Account (fill in a display name, tap Create), Sign In with nsec (paste a valid nsec1 key), and Skip (guest mode).
3. In guest mode, create 3 rounds and verify the "Play with Friends" activation prompt appears.
4. Complete a round in guest mode and verify the "Share this Round" prompt appears.

### npub Read-Only Mode
5. Sign out (Settings → Sign Out).
6. Sign in with a public key only (npub1... or 64-char hex). Verify the "Read-only mode" banner appears on the profile screen.
7. Verify react and comment buttons are absent from feed cards in read-only mode.
8. Verify feed, profile, follow list, and round browsing all work normally.

### Rich Content
9. Open the feed. Find a post with a URL and verify it's tappable (opens in-app browser).
10. Find a post with an image URL in the content and verify the image renders inline.
11. Find a post with an @mention and verify it shows a display name (not raw npub), and tapping it opens a profile sheet.

### Practice Analytics
12. Import a Rapsodo MLM2Pro CSV file. Verify shot counts match your CSV. Check that clubs and metrics appear correctly.
13. View trends for a club. Verify A-only trends filter by active template.
14. Create, rename, and hide a template. Verify templates affect shot grading.

### Rounds (Solo)
15. Create a solo round, enter scores hole-by-hole, and complete it. Verify scores appear in round history.
16. Open a completed round and verify the scorecard grid shows correct scores with circle/square notation.

### Rounds (Multiplayer — Same Device)
17. Create a round with 2+ players. Enter scores using the round-robin flow (P1 then P2 per hole). Verify the review screen shows all players' scores before finishing.

### Rounds (Multiplayer — Multi-Device)
18. Create a multi-device round on Device A. Share the nevent invite to Device B (paste or copy link).
19. Join on Device B. Score independently on both devices. Verify live scorecard updates appear via the refresh button.
20. Finish on both devices. Verify combined final scorecard in round detail.

### Sign Out
21. Sign out via Settings. Verify the feed clears and the welcome screen re-appears. Sign back in and verify the feed reloads fresh.

---

## Known Issues

- **B-001: Club name matching is exact.** If your CSV uses "7 Iron" and your template uses "7i", they won't match. Use the club picker when creating templates to ensure exact names match your CSV.
- **B-002: Multi-device completion UX.** If you finish before the other player, the review screen may show stale scores. Full final scores appear correctly in round detail after both players finish.
- **B-003: No camera QR scanning.** To join a multi-device round, paste the nevent invite text. Camera-based QR scanning is not yet implemented.
- **B-005: Profile cache concurrency.** `NostrService.profileCache` has no write synchronization. Concurrent profile fetches from multiple async contexts may rarely cause a crash. Low-frequency issue in practice; tracked for a future fix.
- **B-006: No outbox queue for publish failures.** If the app is force-quit during the ~1s relay publish window, reactions, comments, and replies may not be delivered. No retry mechanism exists yet.
- **B-007: Comment thread caching.** Comment threads re-fetch from relays on each visit. This is noticeable on slow connections. Caching is planned for a future update.
- **No cloud sync.** All data is local. Deleting the app deletes your data.

---

## How to Report Bugs

1. Use the TestFlight feedback form (shake your device while in the app).
2. Include steps to reproduce, expected behavior, and actual behavior.
3. Screenshots or screen recordings are helpful.

---

## Privacy

- All practice and round data is stored locally in SQLite on your device.
- Nostr features are opt-in. Guest mode provides full practice and round functionality with no network activity.
- Your secret key (nsec) is stored only in the iOS Keychain and never leaves your device.
- The app does not include analytics, tracking, or telemetry.

---

## Build Info

314+ unit and integration tests passing. Early beta — expect rough edges. Your feedback shapes the product.

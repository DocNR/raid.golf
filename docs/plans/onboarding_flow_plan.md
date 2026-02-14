# Onboarding Flow Plan — Gambit Golf

> UX-layer plan for first-run experience, account creation, and Nostr activation.
> Companion doc: `nostr_integration_plan.md` (protocol layer).
> Inspired by [Primal's onboarding](https://primal.net) — hide complexity, reveal power.

---

## Design Principles

1. **Golf app first, Nostr app never (from the user's perspective).** Users should feel like they're using a modern golf tracker. The word "Nostr" should appear only in settings, never in the main flow.
2. **Zero-friction start.** A user should go from App Store install → tracking their first practice session or round in under 60 seconds. No sign-up, no email, no password.
3. **Silent key generation.** A Nostr keypair is generated on first launch and stored in Keychain. The user doesn't know or care. Social features activate later, on their terms.
4. **Progressive disclosure.** Features reveal themselves when relevant — not dumped on the user at once.
5. **No dead ends.** Every screen has a clear next action. Empty states guide, they don't just complain.

---

## Current State

### What exists today:

| Component | Behavior |
|-----------|----------|
| `FirstRunSheetView` | 3 feature cards (Practice, Rounds, Templates) + "Get Started" button |
| `@AppStorage("hasSeenFirstRun")` | Boolean gate for showing the sheet once |
| `KeyManager.loadOrCreate()` | Auto-generates keypair on first use (triggered by Nostr features) |
| `NostrProfileView` | Shows npub + nsec copy (accessed via person.circle button on Rounds tab) |

### What's wrong:

- First-run sheet is informational but doesn't guide action (no "import a CSV" or "start a round" flow)
- No profile setup — user has no name/avatar until they manually set it (which they can't do yet — kind 0 publish isn't built)
- Keypair generation happens lazily (first Nostr action), not at launch — no consistent identity from day one
- No concept of "guest mode" vs. "activated" — features are available or not, with no smooth transition
- No key import flow for existing Nostr users

---

## Proposed Flow

### Overview (State Machine)

```
App Install
    │
    ▼
[First Launch]
    │
    ├──→ Silent keypair generation (Keychain)
    │
    ▼
[Welcome Sheet] ← replaces current FirstRunSheetView
    │
    ├── "Create New Account" ──→ [Profile Setup]
    │                                  │
    │                                  ▼
    │                            [Topic/Interest Picker] (optional, future)
    │                                  │
    │                                  ▼
    │                            [Main App — Nostr activated]
    │
    ├── "Sign In" ──→ [Import nsec/npub]
    │                       │
    │                       ▼
    │                 [Main App — Nostr activated]
    │
    └── "Skip for Now" ──→ [Main App — Guest mode]
                                │
                                ├── (later) contextual prompts to activate
                                └── Settings → "Enable Nostr" → same activation flow
```

### State Flags

```swift
// Persistent state
@AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
@AppStorage("nostrActivated") var nostrActivated = false

// Keypair always exists after first launch (KeyManager.loadOrCreate() in RAIDApp.init)
// nostrActivated gates: publishing, relay reads, player selection, profile display
```

---

## Screen-by-Screen Specification

### Screen 1: Welcome Sheet

**Replaces:** `FirstRunSheetView`
**Trigger:** `!hasCompletedOnboarding` on app launch
**Presentation:** Full-screen sheet, non-dismissable

```
┌─────────────────────────────┐
│                             │
│       [App Icon / Logo]     │
│                             │
│     Welcome to Gambit Golf  │
│                             │
│  Track your practice, score │
│  your rounds, play with     │
│  friends.                   │
│                             │
│  ┌───────────────────────┐  │
│  │  Create Account       │  │  ← Primary CTA (borderedProminent)
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Sign In              │  │  ← Secondary (bordered)
│  └───────────────────────┘  │
│                             │
│      Skip for Now →         │  ← Tertiary (text button, subtle)
│                             │
│  No email or password       │
│  required. Your data stays  │
│  on your device.            │
│                             │
└─────────────────────────────┘
```

**Behavior:**

| Action | What Happens |
|--------|-------------|
| Create Account | Navigate to Profile Setup screen |
| Sign In | Navigate to Key Import screen |
| Skip for Now | Set `hasCompletedOnboarding = true`, `nostrActivated = false`, go to main app |

**Notes:**
- Keypair is already generated before this screen appears (in `RAIDApp.init`)
- "Create Account" doesn't generate keys — it activates them + sets up profile
- No mention of Nostr, keys, relays, or cryptography on this screen

---

### Screen 2a: Profile Setup (Create Account path)

**Trigger:** User tapped "Create Account" on Welcome Sheet
**Presentation:** Pushed onto NavigationStack within the sheet

```
┌─────────────────────────────┐
│  ← Back        Create       │
│─────────────────────────────│
│                             │
│     Set Up Your Profile     │
│                             │
│     ┌─────────┐             │
│     │  📷     │  ← tap to   │
│     │ avatar  │    paste URL │
│     └─────────┘    (MVP)    │
│                             │
│  Display Name               │
│  ┌───────────────────────┐  │
│  │ e.g. Tiger Woods      │  │
│  └───────────────────────┘  │
│                             │
│  Username (optional)        │
│  ┌───────────────────────┐  │
│  │ e.g. tiger             │  │
│  └───────────────────────┘  │
│                             │
│  About (optional)           │
│  ┌───────────────────────┐  │
│  │ Scratch golfer from SF │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Create Account        │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**Behavior:**
1. Display Name is required (minimum 1 character). Username and About are optional.
2. "Create Account" button:
   - Publishes kind 0 event with `name`, `display_name`, `picture`, `about`
   - Sets `nostrActivated = true`
   - Sets `hasCompletedOnboarding = true`
   - Dismisses sheet → main app
3. Avatar: paste URL for MVP. NIP-96 upload in future phase.
4. If kind 0 publish fails (no network), save profile locally and retry on next app foreground. Don't block the user.

**What the user sees:** "Set up your profile" — feels like any social app.
**What actually happens:** Kind 0 event published to Nostr relays.

---

### Screen 2b: Key Import (Sign In path)

**Trigger:** User tapped "Sign In" on Welcome Sheet
**Presentation:** Pushed onto NavigationStack within the sheet

```
┌─────────────────────────────┐
│  ← Back                     │
│─────────────────────────────│
│                             │
│     Sign In                 │
│                             │
│  Paste your secret key      │
│  (nsec) to restore your     │
│  account.                   │
│                             │
│  ┌───────────────────────┐  │
│  │ nsec1...              │  │  ← SecureField or TextField
│  └───────────────────────┘  │
│                             │
│  ⚠️ Your key never leaves   │
│  this device. It's stored   │
│  in your device's secure    │
│  keychain.                  │
│                             │
│  ┌───────────────────────┐  │
│  │  Sign In               │  │
│  └───────────────────────┘  │
│                             │
│  [error message area]       │
│                             │
└─────────────────────────────┘
```

**Behavior:**
1. Validate nsec format via `Keys.parse(secretKey:)`
2. On success:
   - Overwrite auto-generated keypair in Keychain via `KeyManager.importKey(nsec:)`
   - Fetch existing kind 0 profile from relays (best-effort)
   - Set `nostrActivated = true`
   - Set `hasCompletedOnboarding = true`
   - Dismiss sheet → main app
3. On failure: show inline error ("Invalid key format. Keys start with nsec1...")
4. Support both `nsec1...` (bech32) and raw hex (advanced users)

**What the user sees:** "Sign In" with a paste field — feels like a password login.
**What actually happens:** nsec imported to Keychain, existing identity restored.

---

### Screen 3: Main App (Guest Mode)

**Trigger:** User tapped "Skip for Now" (or completed onboarding with `nostrActivated = false`)
**Behavior:** Same TabView as today, with these differences:

| Feature | Guest Mode | Activated Mode |
|---------|-----------|---------------|
| Practice (CSV import) | Full access | Full access |
| Rounds (scorecard) | Full access | Full access |
| Templates | Full access | Full access |
| Trends | Full access | Full access |
| Player selection (rounds) | Hidden | Shown (follow list) |
| Round sharing (Nostr) | Hidden | Shown |
| Profile button (Rounds tab) | Shows "Enable Account" | Shows profile |
| Settings → Nostr section | "Enable Account" CTA | Profile + relay management |

**Key detail:** The person.circle button on the Rounds tab currently opens `NostrProfileView`. In guest mode, it should instead show an activation prompt (see Screen 4).

---

### Screen 4: Contextual Activation Prompts

These appear at natural moments when Nostr features would add value. They are **not** nagging modals — they appear inline or as gentle callouts.

#### Prompt A: "Play with friends" (on Rounds tab)

**Trigger:** User taps person.circle in guest mode, OR creates their 3rd+ round
**Location:** Sheet presentation

```
┌─────────────────────────────┐
│                             │
│     Play with Friends       │
│                             │
│  Create an account to       │
│  invite friends to your     │
│  rounds and share scores.   │
│                             │
│  ┌───────────────────────┐  │
│  │  Create Account        │  │  → Profile Setup (Screen 2a)
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Sign In               │  │  → Key Import (Screen 2b)
│  └───────────────────────┘  │
│                             │
│       Not Now               │
│                             │
└─────────────────────────────┘
```

#### Prompt B: "Share your round" (on Round Detail)

**Trigger:** User completes a round in guest mode
**Location:** Inline banner at top of RoundDetailView

```
┌─────────────────────────────────────┐
│ 📤 Share this round with friends?   │
│     Create Account  |  Not Now      │
└─────────────────────────────────────┘
```

#### Prompt C: "Back up your data" (Settings)

**Trigger:** User has 5+ sessions and is still in guest mode
**Location:** Settings section with a callout card

**Frequency rules:**
- Each prompt shown at most once per session (app foreground)
- "Not Now" dismisses for that session only — prompt may reappear next launch
- After 3 dismissals of the same prompt, stop showing it permanently
- Track dismissal count in `@AppStorage`

---

### Screen 5: Settings → Account Section

**Guest mode:**

```
Account
├── Enable Account              → Activation flow (Screen 2a or 2b)
└── (nothing else)
```

**Activated mode:**

```
Account
├── Edit Profile                → Profile editing (name, avatar, about)
├── Nostr Identity
│   ├── Public Key (npub)       → Copy button
│   └── Secret Key (nsec)       → Copy with confirmation
├── Relays                      → Relay management (Phase 7C)
└── (future: Connected Apps, Wallet, etc.)
```

**Note:** The current `NostrProfileView` sheet on the Rounds tab should be replaced by navigating to Settings → Account in activated mode, or showing the activation prompt in guest mode. This consolidates identity management into one place.

---

## Implementation Phases

### Phase O-1: Welcome Sheet Redesign

**Replace `FirstRunSheetView` with new 3-button welcome sheet.**

Changes:
- New `WelcomeView` with Create Account / Sign In / Skip
- `@AppStorage("hasCompletedOnboarding")` replaces `hasSeenFirstRun`
- Silent keypair generation moved to `RAIDApp.init` (before any UI)
- `@AppStorage("nostrActivated")` flag added
- "Skip" goes straight to main app (guest mode)

**Depends on:** Phase 7A.1 (key import) from nostr_integration_plan.md

### Phase O-2: Profile Setup Screen

**Add profile creation flow for "Create Account" path.**

Changes:
- New `ProfileSetupView` with name, username, about, avatar URL fields
- Publishes kind 0 on completion (requires Phase 7B from nostr_integration_plan.md)
- Graceful offline handling (save locally, publish on next foreground)

**Depends on:** Phase 7B (profile publishing)

### Phase O-3: Key Import Screen

**Add nsec import flow for "Sign In" path.**

Changes:
- New `KeyImportView` with secure text field
- Validation via `Keys.parse(secretKey:)`
- `KeyManager.importKey(nsec:)` overwrites auto-generated key
- Fetches existing profile from relays after import

**Depends on:** Phase 7A.1 (key import)

### Phase O-4: Guest Mode Gating

**Gate Nostr features behind `nostrActivated` flag.**

Changes:
- `CreateRoundView` players section: hidden when `!nostrActivated`
- `RoundDetailView` share button: hidden when `!nostrActivated`
- Rounds tab person.circle: shows activation prompt when `!nostrActivated`
- All publishing calls gated: `guard nostrActivated else { return }`

### Phase O-5: Contextual Activation Prompts

**Add gentle nudges at natural moments.**

Changes:
- Activation prompt sheet (reusable component)
- Inline banner for round completion
- Settings account section with CTA
- Dismissal tracking with `@AppStorage` counters

### Phase O-6: Settings Consolidation

**Move all identity/Nostr management to Settings → Account.**

Changes:
- Remove `NostrProfileView` sheet from Rounds tab toolbar
- Add Account section to a new Settings tab (or gear icon in existing tab)
- Edit Profile screen for activated users
- Relay management placeholder (for Phase 7C)

---

## Sequencing

```
Phase 7A.1 (Key Import)
    │
    ├──→ Phase O-1 (Welcome Sheet) ← can ship with just Skip + Create stub
    │
    ├──→ Phase O-3 (Key Import Screen)
    │
    └──→ Phase O-4 (Guest Mode Gating) ← can ship independently

Phase 7B (Profile Publishing)
    │
    └──→ Phase O-2 (Profile Setup)

Phase O-4 (Guest Mode Gating)
    │
    └──→ Phase O-5 (Contextual Prompts)

Phase O-1 + O-2 + O-3 + O-4
    │
    └──→ Phase O-6 (Settings Consolidation)
```

**Minimum viable onboarding (can ship first):**
- Phase O-1 (Welcome Sheet with Skip only — Create/SignIn show "Coming Soon")
- Phase O-4 (Guest mode gating)

This gives us the foundation. Profile setup and key import plug in when their protocol dependencies land.

---

## Migration from Current State

### Users who already have the app:

- `hasSeenFirstRun = true` in their `@AppStorage` → don't show Welcome Sheet
- Set `hasCompletedOnboarding = true` automatically on app update
- If they have a keypair in Keychain already → set `nostrActivated = true`
- If no keypair → set `nostrActivated = false` (guest mode)
- Net effect: existing users see no change in behavior

### New installs after this ships:

- Fresh `@AppStorage` → show Welcome Sheet
- Choose their path (Create / Sign In / Skip)
- Keypair auto-generated regardless of choice

---

## Copy & Tone Guidelines

| Instead of... | Say... |
|--------------|--------|
| "Nostr keypair" | "Account" |
| "Public key" | "Your ID" (or hide entirely) |
| "Secret key" | "Secret key" (only in backup/import contexts) |
| "Relay" | Avoid in main flow; use in Settings only |
| "Sign event" | Never expose this |
| "npub1..." | Show only in profile/settings, with copy button |
| "Decentralized" | "Your data stays on your device" |

The word "Nostr" should appear:
- In Settings → Account → Nostr Identity section
- In the nsec backup warning text
- Nowhere else in the main user flow

---

## Open Questions

1. **Tab for Settings?** Currently no Settings tab exists. Options:
   - Add a 5th tab (Settings gear icon)
   - Put account management behind the person.circle button
   - Use a gear icon on an existing tab's toolbar

2. **Avatar upload vs. URL paste?** MVP uses URL paste. NIP-96 upload is better UX but adds dependency on external file hosting servers. Decide when we build Phase O-2.

3. **Follow suggestions during onboarding?** Primal shows topic/interest pickers. For a golf app, we could suggest following golf accounts or popular courses. Deferred — not needed for MVP onboarding.

4. **Existing key detection on first launch?** Should we check if the user already has a Nostr identity in another app (e.g., via universal links or clipboard)? Probably not — too invasive. The "Sign In" button is sufficient.

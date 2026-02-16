# Social Feed and Course Discovery Design

**Project:** Gambit Golf (raid.golf)
**Date:** February 16, 2026
**Status:** Design document for post-MVP features

## Overview

This document describes the design for Gambit Golf's social feed and course discovery features, built on top of the Nostr protocol. These features enable golfers to share rounds, follow friends, discover new courses, and engage with a community of players.

**Current Status:** The MVP implementation focuses on on-course scoring. The social and discovery features described here are planned for post-MVP development.

## Understanding Nostr Events

Gambit Golf uses the Nostr protocol for all social and data publishing features. Nostr is a decentralized protocol where users publish signed "events" to relay servers. Think of events as messages that contain golf data — scorecards, course definitions, comments, etc.

### Event Types Explained

Nostr has several types of events, each with different persistence and update behaviors:

**Immutable Events**
Once published, these events can never be changed or deleted. Think of them like writing in pen on paper — permanent and verifiable. If you need to "fix" something, you publish a new event.

- Kind 1501: Round Initiation (marks the start of a round)
- Kind 1502: Final Round Record (complete scorecard with per-hole scores)
- Kind 1: Social notes (general-purpose text posts)

**Replaceable Events**
The author can update these events, and only the latest version matters. Think of them like writing on a whiteboard — you can erase and rewrite, and only the current state matters.

- Kind 10002: Relay list
- Other metadata events

**Addressable Replaceable Events**
Like replaceable events, but with a unique identifier (the `d` tag) so an author can maintain multiple independent items. For example, a user can have many different course definitions (one per course), each with its own `d` tag, and can update any of them independently.

- Kind 30501: Live Scorecard (real-time round in progress)
- Kind 33501: Course Definition (course layout, tees, pars)

**Ephemeral Events**
Fire-and-forget events that relays don't store. Used for presence indicators, typing notifications, etc. (Not currently used in Gambit Golf.)

### How Events Work

Every event has:
- **kind**: A number that tells clients what type of data it contains (1 = note, 1502 = final scorecard, etc.)
- **content**: The actual data (can be text, JSON, or other formats)
- **tags**: Structured metadata (references to other events, hashtags, geolocation, etc.)
- **pubkey**: The author's public key
- **sig**: Cryptographic signature proving the author wrote it

Because events are signed, you always know who published what. The signature cannot be forged, so you can trust the source of any event.

## Social Feed Architecture

The social feed has multiple sections that surface different types of content to the user.

### Live Rounds Section

**Purpose:** Show in-progress rounds from players you follow.

**Content:** Kind 30501 live scorecards

**Position:** Top of the feed, above the main timeline (dedicated section, not mixed chronologically)

**Behavior:**
- Kind 30501 events are addressable replaceable, so they update in-place as players record each hole
- Subscribed clients receive updates automatically and re-render the live scorecard
- Each player can have only one active kind 30501 at a time (identified by the `d` tag)

**Staleness Handling:**
The app must handle rounds that are completed or abandoned:
1. **Status tag detection:** When a kind 30501 includes a status tag indicating completion, remove it from the live section
2. **Matching kind 1502:** If a final round record (kind 1502) appears that matches the live round (same course, same date, same player), remove the kind 30501 from the live section
3. **Time-based fallback:** If no update received for 8 hours, consider the round stale and remove it from the live section

**Query:**
```
kinds: [30501]
authors: [list of followed pubkeys]
since: 8 hours ago
```

### Main Feed (Timeline)

**Purpose:** Show golf-related social posts from players you follow.

**Content:** Kind 1 notes with the `#t: ["golf"]` hashtag

**Why the hashtag filter?** When you follow someone on Nostr, you follow their entire social presence, not just their golf activity. The `#t: golf` tag lets users filter their feed to only show golf-related posts from people they follow.

**Tag Details:**
- `t:golf` is the primary filter (standard, indexed by all relays)
- `t:gambitgolf` is also attached to Gambit Golf posts for more specific filtering
- `client` tag is attached to identify the app, but it's multi-letter and not reliably indexed by relays, so it's not useful for relay-side filtering

**Query:**
```
kinds: [1]
#t: ["golf"]
authors: [list of followed pubkeys]
```

### Rich Scorecard Cards

When a kind 1 note in the feed references a kind 1502 final round record (via an `e` tag), the app renders a rich scorecard card instead of just displaying text.

**Flow:**
1. Fetch kind 1 notes from the timeline
2. Parse each note for `e` tags referencing kind 1502 events
3. Fetch the referenced kind 1502 events on-demand
4. Render the scorecard data as a rich card: course name, date, total score, per-hole details, etc.

**Why kind 1 + kind 1502?**
Kind 1502 contains structured golf data (scores, course, date) but has no social affordances (no replies, reactions, visibility in general-purpose Nostr clients). By publishing a companion kind 1 note that references the kind 1502, users get:
- A social artifact that appears in standard Nostr feeds
- The ability to add personal commentary ("Great round at Pebble Beach!")
- Rich rendering in Gambit Golf while remaining readable in generic Nostr clients

### Comments on Scorecards

**Problem:** Kind 1 notes (the standard Nostr note type) can be replied to using normal replies (also kind 1, with `e` and `p` tags). But how do you comment on a kind 1502 scorecard?

**Solution:** NIP-22 defines kind 1111 ("Comment") for replying to non-kind-1 events.

**Important Clarification:** NIP-22 is the spec number, but it defines kind 1111 as the event kind. Kind 22 is actually short-form video (NIP-71), completely unrelated.

**How Kind 1111 Works:**
- Kind 1111 events reference the event they're commenting on using uppercase tags for the root and lowercase tags for the parent (to support threading)
- `K` tag: kind of the root event (e.g., `["K", "1502"]`)
- `E` tag: event ID of the root event
- `P` tag: pubkey of the root event author
- `k`, `e`, `p` tags: kind, event ID, and pubkey of the direct parent (for nested replies)

**UI Integration:**
- Scorecard cards show a comment count
- Tapping the comment button opens the kind 1111 thread for that scorecard
- Users can post comments directly on scorecards

**Query for Comments:**
```
kinds: [1111]
#K: ["1502"]
#E: [event_id_of_scorecard]
```

### Discovery Tab

**Purpose:** Help users discover new golfers and see activity at courses they play, beyond just the people they follow.

**Content:** Same as the main feed (kind 1 notes with `#t: ["golf"]`), but without the `authors` filter.

**Filtering:**
- Show all golf notes published to the relay, not just from followed users
- Filter by recency (e.g., last 24-48 hours) to keep content fresh
- Apply the same rich scorecard card rendering

**Query:**
```
kinds: [1]
#t: ["golf"]
since: 24 hours ago
```

**Why This Works:**
- Enables serendipitous discovery of new players
- See what's happening at courses you play or plan to visit
- Provides a public leaderboard effect for local courses

## Feed Query Reference

| Section | Content | Query |
|---------|---------|-------|
| Live Rounds | Kind 30501 from follows | `kinds:[30501], authors:[follows], since:8h_ago` |
| Main Feed | Kind 1 golf notes from follows | `kinds:[1], #t:["golf"], authors:[follows]` |
| Scorecard Cards | Kind 1502 referenced by feed notes | Fetched on-demand via `e` tag in kind 1 notes |
| Comments | Kind 1111 on scorecards | `kinds:[1111], #K:["1502"], #E:[event_id]` |
| Discover | Kind 1 golf notes, anyone | `kinds:[1], #t:["golf"], since:24h_ago` |

## Course Discovery (Kind 33501)

Golf courses are represented as kind 33501 addressable replaceable events. This design enables user-contributed course data while providing a path to verified, course-operated definitions.

### What is a Kind 33501?

A kind 33501 event describes a golf course. It contains:
- Course name
- Location (latitude/longitude coordinates)
- Tee sets (e.g., Championship, Blue, White, Red)
- Hole definitions for each tee: par, handicap index, yardage
- Optional: course rating, slope rating

**Addressable Replaceable:** The `d` tag makes each course definition unique per author. A user can publish multiple course definitions (one per course), and can update any of them later.

**User-Contributed:** Anyone can publish a kind 33501 for any course. There's no central authority required. This bootstraps the course database through community contribution.

### The Deduplication Problem

Multiple users will inevitably publish kind 33501 events for the same physical course. How does the app know which one to show?

**Solution: Geo-Coordinate Clustering**

Courses within approximately 500 meters of each other are considered the same physical course. The app clusters kind 33501 events by location.

Within each cluster, the app applies a curation algorithm to surface the best definition.

### Community Curation Algorithm

The app ranks course definitions within each cluster using signals that are hard to game and reflect real usage:

**Primary Signal: Usage Count**
How many kind 1501 round initiations reference this specific kind 33501? Each time a player starts a round using this course definition, it increments the count. This is the strongest signal because it requires real rounds of golf, not just reactions.

**Secondary Signal: Unique Reactors**
NIP-25 reactions (kind 7 events, analogous to "likes") from unique users. Only count each reactor once to prevent spam.

**Tertiary Signal: Recency Bonus**
Newer course definitions get a small bonus to allow corrections or better-maintained definitions to rise.

**Rough Formula:**
```
score = (rounds_played × 10) + (unique_reactors × 2) + recency_bonus
```

The highest-scoring definition in each cluster is shown by default. Users can tap to see alternatives.

### Verified Course Badges

While community curation works well, official verification adds trust and enables premium features.

**Verification via NIP-32 Labels**

Gambit Golf's pubkey serves as the initial trust anchor. To mark a course as verified:
1. Gambit Golf publishes a kind 1985 label event referencing the kind 33501
2. The label includes a namespace (e.g., `golf/verified`) and a mark (e.g., `verified`)
3. Clients display a verified badge next to courses that have this label from the Gambit Golf pubkey

**Benefits of Verification:**
- Verified courses float to the top of search results
- Users trust the data is accurate and maintained
- Courses can later transition to self-publishing (see Business Model)

**Query for Verification:**
```
kinds: [1985]
authors: [gambit_golf_pubkey]
#L: ["golf/verified"]
#l: ["verified"]
```

## Business Model: Course Onboarding

The course discovery design enables a multi-stage business model that starts free and scales to premium features.

### Stage 1: Community (Free)

**Status:** Day one, requires no business development.

- Users submit kind 33501 course definitions for any course they play
- Geo-clustering + usage-based curation automatically ranks them
- No verification, community wins through collective contribution
- Gambit Golf maintains a lightweight review process to prevent spam

**Value to Golfers:** Immediate access to course data for scorekeeping.

### Stage 2: Course Verification

**Status:** Early partnership model.

- Gambit Golf partners with courses to verify their official kind 33501
- Help courses claim their definition using their own keypair (if they want ownership)
- Verified badge displayed prominently in app
- Course maintains static data: tee sets, pars, handicap indexes, yardages

**Value to Courses:**
- Official presence in the app
- Accurate data representation
- Visibility to golfers using the app

**Revenue Model:** Potential for small verification fee or free as a customer acquisition strategy.

### Stage 3: Premium Course Tools

**Status:** Future high-value feature set.

Courses publish live operational data via their kind 33501. Since it's addressable replaceable, updates propagate automatically to all subscribed clients.

**Live Course Data:**
- Daily pin/flag positions (changes each day)
- Temporary rules (cart path only, ground under repair, etc.)
- Weather alerts
- Pace of play updates

**Player Experience:**
A golfer arrives at a verified course. Their app automatically fetches the latest kind 33501 and shows today's pin positions on each hole, current rules, and any alerts. No manual checking required.

**Revenue Model:** Subscription fee for premium operational data publishing.

### Stage 4: Tee Times — The Big Opportunity

**Vision:** Courses publish available tee time slots as structured data alongside their kind 33501 or as separate events that reference it.

**How It Works:**
- Course updates tee time availability in real-time via Nostr events
- Players see available slots directly in the Gambit Golf app
- Players book directly with the course (no intermediary platform)
- Payment and confirmation handled course-side or via integrated payment protocol

**Why This Matters:**
- Proprietary platforms like GolfNow take 15-30% commission per booking
- Nostr-based tee times create an open marketplace where courses keep more revenue
- Courses own their data and customer relationships
- Lower friction for golfers (book from the same app they score with)

**Pitch to Courses:**
"Stop giving 20% to tee time marketplaces. Publish your availability on Nostr, keep your revenue, and own your customer data. We'll help you get set up."

**Technical Notes:**
- Tee time events could be kind 33501 with structured tags, or a new kind (TBD)
- Booking confirmation could use NIP-04 encrypted DMs or a new booking event kind
- Payment integration is a separate concern (possibly Lightning Network, credit card, or course-managed)

## Implementation Priority

This is a design document for future planning. The current MVP focuses on on-course scoring. Social and discovery features are post-MVP.

**Suggested Implementation Order:**

1. **Basic Feed** — Kind 1 notes filtered by `#t:golf` from followed users. Text-only display.

2. **Rich Scorecard Cards** — Detect `e` tags referencing kind 1502, fetch on-demand, render rich cards.

3. **Live Rounds Section** — Dedicated section at top of feed showing kind 30501 from follows, with staleness handling.

4. **Discovery Tab** — Same query as main feed but without `authors` filter, recency-filtered.

5. **Course Definitions (Kind 33501)** — Allow users to publish course definitions, geo-clustering, community curation algorithm.

6. **Course Verification and Badges** — NIP-32 label system, verified badge in UI.

7. **Comments (Kind 1111)** — Comment threads on scorecards, nested reply support.

8. **Premium Course Tools** — Live operational data publishing for verified courses (pins, rules, weather).

9. **Tee Times** — Availability publishing, booking flow, payment integration.

## Technical Considerations

### Relay Strategy

Gambit Golf operates its own relay for guaranteed data availability, but clients should query multiple relays for discovery and federation.

**Recommended Setup:**
- Always query Gambit Golf relay for user's own data
- Query 3-5 popular public relays for discovery and follows
- Users can configure additional relays in settings

### Caching and Offline Support

Kind 1 and kind 1502 events are immutable, so they can be cached aggressively. Kind 30501 and kind 33501 are replaceable, so clients must refresh periodically.

**Strategy:**
- Cache immutable events indefinitely with local SQLite
- Refresh replaceable events on app launch and periodically during use
- Support offline viewing of cached scorecards and rounds

### Privacy and Blocking

Nostr is a public protocol. All published events are visible to anyone. Users should be informed:
- Scorecards published via kind 1502 + kind 1 are public
- Course definitions are public
- Blocking a user hides their content in your client but doesn't prevent them from seeing your events

Future: Encrypted scorecards (NIP-04 or NIP-44) for private rounds.

### Spam and Moderation

User-contributed course definitions create spam risk. Mitigation strategies:
- Usage-based curation naturally demotes unused/spam courses
- Client-side filtering: ignore courses with zero rounds played
- Report function: users can flag spam course definitions
- Web of trust (future): weight definitions from users you follow more heavily

## Open Questions

1. **Tee time event structure:** New kind or extend 33501?
2. **Payment integration:** Lightning, credit card, course-managed, or all three?
3. **Course authentication:** How do courses prove they own their keypair? (DNS verification, email confirmation, physical verification?)
4. **Comment moderation:** Who can delete kind 1111 comments on their scorecards? (Nostr doesn't support deletion, so client-side hiding only)
5. **Private rounds:** Should we support encrypted kind 1502 for private scorecards?

## Conclusion

The social feed and course discovery design leverages Nostr's decentralized architecture to create an open, user-owned golf social network. By starting with community-contributed course data and evolving toward verified, course-operated definitions with premium features, Gambit Golf can bootstrap quickly while building toward a sustainable business model that benefits both golfers and courses.

The phased implementation approach allows us to deliver value incrementally, validate assumptions with real users, and adapt the design based on feedback before committing to the more complex premium features.

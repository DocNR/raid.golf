# NIP-101g: Golf Events (Deferred / Post-MVP)

`draft` `optional`

> **Status:** This specification is **deferred** and **not part of the current MVP**.  
> The MVP scope is focused on **launch monitor practice analytics and KPI standards**, not on-course scoring or course discovery.  
> This document is maintained for future expansion once the MVP is validated.
> This document is superseded in part by docs/private/nip-101g.md

This NIP defines event kinds for golf score tracking and course information on Nostr. It is designed to be extensible, but it is **explicitly out of scope** for the current MVP.

## Abstract

This specification enables golfers to:
1. Share golf course information
2. Record and publish golf rounds
3. Verify rounds through peer attestation

## Event Kinds

- `33501`: Golf Course Definition (addressable event)
- `11501`: Live Round Scoring (regular event)
- `1501`: Golf Round Record (regular event)
- `1502`: Round Attestation (regular event)

## Golf Course Definition (kind: 33501)

Addressable events that define golf courses. These are replaceable by the author and identified by the `d` tag.

### Structure

```json
{
  "kind": 33501,
  "content": "<optional course description>",
  "tags": [
    ["d", "<unique-identifier>"],
    ["name", "<course name>"],
    ["location", "<city>", "<state/province>", "<country>"],
    ["hole", "<number>", "<par>", "<handicap>"],
    ["tee", "<name>", "<rating>", "<slope>"],
    ["imeta", "url <image-url>", "m <mime-type>", "alt <description>"]
  ]
}
```

### Required Tags

- `d`: Unique identifier for the course (UUID recommended)
- `name`: Course name
- `location`: City, state/province, country
- `hole`: One tag per hole with number (1-18), par, and handicap index
- `tee`: At least one tee set with name, course rating, and slope rating

### Optional Tags

- `imeta`: Course cover image following [NIP-92](https://github.com/nostr-protocol/nips/blob/master/92.md) format
- `g`: Geohash for location-based discovery and filtering

### Tag Formatting Rules

**CRITICAL**: All tag values must follow Nostr conventions:

- **Tee names MUST NOT contain underscores**
- Use spaces for readability in multi-word names
- All text values should be clean, readable strings

**Examples:**
- ✅ Correct: `["tee", "Silver M", "68.4", "118"]`
- ✅ Correct: `["tee", "Championship", "74.2", "142"]`
- ✅ Correct: `["tee", "Bethpage Black", "81.8", "155"]` (championship course)
- ❌ Wrong: `["tee", "Silver_M", "68.4", "118"]`
- ❌ Wrong: `["tee", "Silver-M", "68.4", "118"]`

### USGA-Compliant Validation Ranges

Following official USGA standards for course rating and slope rating:

- **Course Rating**: 40-90 (covers municipal to championship courses)
- **Slope Rating**: 55-155 (113 is standard difficulty)
- **Hole Count**: 18, 36, or 54 holes (multiples of 18 for golf complexes)
- **Hole Numbers**: 1-54 (to support multi-course complexes)
- **Par Values**: 3-6 per hole

**Note**: Course Rating and Tee Rating refer to the same USGA measurement - the expected score for a scratch golfer under normal conditions.

### Example

```json
{
  "kind": 33501,
  "pubkey": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
  "created_at": 1714924800,
  "content": "Pete Dye masterpiece located in beautiful Geauga County just 30 minutes east of downtown Cleveland.",
  "tags": [
    ["d", "fowlers-mill-golf-course"],
    ["name", "Fowler's Mill Golf Course"],
    ["location", "Chesterland", "Ohio", "USA"],
    ["t", "golf"],
    ["hole", "1", "4", "5"],
    ["hole", "2", "4", "15"],
    ["hole", "3", "3", "7"],
    ["hole", "4", "4", "1"],
    ["hole", "5", "5", "13"],
    ["hole", "6", "4", "3"],
    ["hole", "7", "3", "17"],
    ["hole", "8", "5", "9"],
    ["hole", "9", "4", "11"],
    ["hole", "10", "4", "8"],
    ["hole", "11", "4", "12"],
    ["hole", "12", "4", "10"],
    ["hole", "13", "3", "14"],
    ["hole", "14", "5", "6"],
    ["hole", "15", "4", "4"],
    ["hole", "16", "4", "18"],
    ["hole", "17", "3", "16"],
    ["hole", "18", "5", "2"],
    ["tee", "Gold", "74.7", "136"],
    ["tee", "Black", "72.8", "133"],
    ["tee", "Green", "69.9", "128"],
    ["tee", "Silver M", "68.4", "118"],
    ["tee", "Silver W", "71.8", "118"],
    ["g", "dpqh"],
    ["imeta", 
      "url https://example.com/fowlers-mill-cover.jpg",
      "m image/jpeg",
      "alt Fowler's Mill Golf Course aerial view",
      "dim 1920x1080"
    ]
  ],
  "sig": "..."
}
```

## Live Round Scoring (kind: 11501)

Regular events that track real-time golf round progress. These events enable multiplayer coordination, live spectating, and progressive round updates.

### Structure

```json
{
  "kind": 11501,
  "content": "<optional round notes or current status>",
  "tags": [
    ["d", "<shared-round-identifier>"],
    ["course", "<course-reference>"],
    ["date", "<ISO-8601 date>"],
    ["tee", "<tee name used>"],
    ["status", "<setup|in_progress|finalized>"],
    ["p", "<player pubkey>"],
    ["score", "<hole>", "<strokes>"],
    ["game", "<stroke|skins|match>"],
    ["group", "<group-identifier>"]
  ]
}
```

### Required Tags

- `d`: Shared identifier for the round (enables multiple players to publish to same round)
- `course`: Reference to course using format `33501:<course-author-pubkey>:<course-d-tag>`
- `date`: Date of play in ISO-8601 format (YYYY-MM-DD)
- `tee`: Name of tee set used (must match course definition exactly)
- `status`: Current round status (`setup`, `in_progress`, or `finalized`)
- `p`: Player pubkey (multiple players can publish to same round using different pubkeys)

### Optional Tags

- `score`: Hole number and strokes taken (one tag per completed hole)
- `game`: Game format being played (e.g., `stroke`, `skins`, `match`)
- `group`: Group identifier for organizing multiple concurrent rounds
- `a`: Reference to NIP-52 calendar invitation that initiated this round

### Status Progression

1. **`setup`**: Initial event created when round is organized
   - Contains course, date, tee, and player information
   - May reference NIP-52 calendar invitation via `a` tag
   - No scores yet recorded

2. **`in_progress`**: Round is actively being played
   - Contains progressive score updates as holes are completed
   - Multiple players publish their own scores using shared `d` tag
   - Enables real-time spectating and leaderboards

3. **`finalized`**: Player has completed and submitted their round
   - Contains all 18 hole scores
   - Triggers creation of permanent kind 1501 record
   - Round is ready for attestation

### Multiplayer Coordination

Multiple players can participate in the same round by:
- Using the same `d` tag (shared round identifier)
- Each publishing their own 11501 events with their pubkey in `p` tag
- Progressing through status updates independently (asynchronous play)
- Referencing the same NIP-52 calendar invitation via `a` tag

### Example: Setup Status

```json
{
  "kind": 11501,
  "pubkey": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
  "created_at": 1714924800,
  "content": "Starting our Saturday morning round at Fowler's Mill",
  "tags": [
    ["d", "fowlers-mill-2024-05-05-morning-group"],
    ["course", "33501:3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d:fowlers-mill-golf-course"],
    ["date", "2024-05-05"],
    ["tee", "Silver M"],
    ["status", "setup"],
    ["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],
    ["p", "4ac0d8cf2cf332d893612bfce574f6c2d8b8707b52e5fd56d8c3e9922f9574"],
    ["p", "5bc0d8cf2cf332d893612bfce574f6c2d8b8707b52e5fd56d8c3e9922f9575"],
    ["game", "skins"],
    ["group", "saturday-morning-crew"],
    ["a", "31923:organizer_pubkey:round-invitation-uuid"]
  ],
  "sig": "..."
}
```

### Example: In Progress Status

```json
{
  "kind": 11501,
  "pubkey": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
  "created_at": 1714926400,
  "content": "Through 9 holes, playing well!",
  "tags": [
    ["d", "fowlers-mill-2024-05-05-morning-group"],
    ["course", "33501:3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d:fowlers-mill-golf-course"],
    ["date", "2024-05-05"],
    ["tee", "Silver M"],
    ["status", "in_progress"],
    ["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],
    ["score", "1", "5"],
    ["score", "2", "4"],
    ["score", "3", "3"],
    ["score", "4", "5"],
    ["score", "5", "4"],
    ["score", "6", "6"],
    ["score", "7", "5"],
    ["score", "8", "4"],
    ["score", "9", "4"],
    ["game", "skins"],
    ["group", "saturday-morning-crew"]
  ],
  "sig": "..."
}
```

### Example: Finalized Status

```json
{
  "kind": 11501,
  "pubkey": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
  "created_at": 1714930000,
  "content": "Round complete! Great day on the course.",
  "tags": [
    ["d", "fowlers-mill-2024-05-05-morning-group"],
    ["course", "33501:3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d:fowlers-mill-golf-course"],
    ["date", "2024-05-05"],
    ["tee", "Silver M"],
    ["status", "finalized"],
    ["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],
    ["score", "1", "5"],
    ["score", "2", "4"],
    ["score", "3", "3"],
    ["score", "4", "5"],
    ["score", "5", "4"],
    ["score", "6", "6"],
    ["score", "7", "5"],
    ["score", "8", "4"],
    ["score", "9", "4"],
    ["score", "10", "4"],
    ["score", "11", "5"],
    ["score", "12", "3"],
    ["score", "13", "4"],
    ["score", "14", "6"],
    ["score", "15", "5"],
    ["score", "16", "4"],
    ["score", "17", "3"],
    ["score", "18", "5"],
    ["total", "79"],
    ["game", "skins"],
    ["group", "saturday-morning-crew"]
  ],
  "sig": "..."
}
```

### Sharing and Discovery

Live rounds can be shared via:
- **QR codes**: Encode round `d` tag for easy mobile scanning
- **Deep links**: `nostr:nevent1...` format for direct app linking
- **Direct messages**: Share round identifier with friends
- **Social posts**: Reference round in kind 1 notes for broader discovery

Query pattern for following a live round:
```json
{
  "kinds": [11501],
  "#d": ["fowlers-mill-2024-05-05-morning-group"],
  "since": 1714924800
}
```

## Golf Round Record (kind: 1501)

Regular events that record completed golf rounds. Each round is a unique event.

### Structure

```json
{
  "kind": 1501,
  "content": "<optional round notes>",
  "tags": [
    ["d", "<unique-identifier>"],
    ["course", "<course-reference>"],
    ["date", "<ISO-8601 date>"],
    ["tee", "<tee name used>"],
    ["score", "<hole>", "<strokes>"],
    ["total", "<total strokes>"],
    ["p", "<player pubkey>"]
  ]
}
```

### Required Tags

- `d`: Unique identifier for the round (UUID recommended)
- `course`: Reference to course using format `33501:<course-author-pubkey>:<course-d-tag>`
- `date`: Date of play in ISO-8601 format (YYYY-MM-DD)
- `tee`: Name of tee set used (must match course definition exactly)
- `score`: One tag per hole with hole number and strokes taken
- `total`: Total strokes for the round

### Optional Tags

- `p`: Tag other players in the round (supports attestation)

### Example

```json
{
  "kind": 1501,
  "pubkey": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
  "created_at": 1714924800,
  "content": "Great weather, played well on the back nine!",
  "tags": [
    ["d", "660e8400-e29b-41d4-a716-446655440001"],
    ["course", "33501:3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d:fowlers-mill-golf-course"],
    ["date", "2024-05-05"],
    ["tee", "Silver M"],
    ["score", "1", "5"],
    ["score", "2", "4"],
    ["score", "3", "3"],
    ["score", "4", "5"],
    ["score", "5", "4"],
    ["score", "6", "6"],
    ["score", "7", "5"],
    ["score", "8", "4"],
    ["score", "9", "4"],
    ["score", "10", "4"],
    ["score", "11", "5"],
    ["score", "12", "3"],
    ["score", "13", "4"],
    ["score", "14", "6"],
    ["score", "15", "5"],
    ["score", "16", "4"],
    ["score", "17", "3"],
    ["score", "18", "5"],
    ["total", "79"],
    ["p", "4ac0d8cf2cf332d893612bfce574f6c2d8b8707b52e5fd56d8c3e9922f9574"],
    ["p", "5bc0d8cf2cf332d893612bfce574f6c2d8b8707b52e5fd56d8c3e9922f9575"]
  ],
  "sig": "..."
}
```

## Round Attestation (kind: 1502)

Regular events that verify the accuracy of golf rounds. Players can attest to rounds they played in.

### Structure

```json
{
  "kind": 1502,
  "content": "<optional attestation note>",
  "tags": [
    ["e", "<round event id>"],
    ["p", "<round author pubkey>"],
    ["status", "<verified|disputed>"]
  ]
}
```

### Required Tags

- `e`: Event ID of the round being attested (since 1501 is a regular event)
- `p`: Pubkey of the round's author
- `status`: Either "verified" or "disputed"

### Example

```json
{
  "kind": 1502,
  "pubkey": "4ac0d8cf2cf332d893612bfce574f6c2d8b8707b52e5fd56d8c3e9922f9574",
  "created_at": 1714928400,
  "content": "I can confirm these scores are accurate.",
  "tags": [
    ["e", "7f3b5c2d1e4a6b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c"],
    ["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],
    ["status", "verified"]
  ],
  "sig": "..."
}
```

## Multiplayer Coordination with NIP-52

For multiplayer golf rounds, this specification integrates with [NIP-52 Calendar Events](https://github.com/nostr-protocol/nips/blob/master/52.md) to provide invitation and RSVP functionality:

- **Golf Round Invitations** (NIP-52 kind 31923): Schedule multiplayer rounds with course, time, and game type
- **RSVP Responses** (NIP-52 kind 31925): Players accept/decline invitations with golf-specific preferences
- **Live Coordination** (NIP-101g kind 11501): Real-time scoring linked to calendar events
- **Final Records** (NIP-101g kind 1501): Completed rounds reference the original invitation

See: `docs/planning/multiplayer-nip52-architecture.md` for technical details  
See: `docs/reference/nip-52-golf-integration.md` for implementation reference

## Extensibility

This specification is designed to grow incrementally. Since kind 33501 events are **replaceable**, courses can be updated with new features as they become available.

### Planned Extensions

Future versions of this specification may include:

#### Enhanced Course Information
```json
// Total par per tee set (5th parameter)
["tee", "Red", "68.1", "125", "70"]

// Par overrides for holes that play different pars from different tees
["par-override", "1", "Red", "5"]  // Hole 1 is par 5 from red tees
["par-override", "18", "Red", "4"] // Hole 18 is par 4 from red tees

// Hole yardages from each tee
["yardage", "1", "Black", "425"]
["yardage", "1", "White", "395"]
["yardage", "1", "Red", "340"]

// Hole-specific images
["imeta",
  "url https://example.com/hole-7.jpg",
  "m image/jpeg", 
  "alt Hole 7 - Signature par 3 over water",
  "dim 1920x1080",
  "hole 7"
]
```

#### Additional Course Metadata
```json
// Course details
["website", "https://fowlersmillgolf.com"]
["phone", "+1-440-729-7569"]
["architect", "Pete Dye"]
["established", "1995"]
["gps", "41.234567", "-81.234567"]

// Hole descriptions
["hole-description", "7", "Signature par 3 over water. Aim for the right side of the green."]
```

#### Round Extensions
```json
// Weather conditions
["weather", "Sunny, 75°F, light breeze"]

// Equipment used
["equipment", "driver", "TaylorMade SIM2"]
["equipment", "irons", "Titleist T200"]

// Game format
["format", "stroke-play"]
["format", "match-play"]
```

### Forward Compatibility

**Clients MUST ignore unknown tags** to ensure forward compatibility. This allows:
- New features to be added without breaking existing clients
- Gradual adoption of enhanced features
- Experimentation with new tag types

## Implementation Notes

### Course References

The course reference format `33501:<pubkey>:<d-tag>` follows NIP-01 conventions for referencing addressable events. This allows clients to:
1. Identify the event kind (33501)
2. Know the author's pubkey
3. Find the specific course by its `d` tag

### Tag Validation

Implementations MUST:
- Reject events with malformed tag values (e.g., underscores in tee names)
- Validate that tee names in round events match course definitions exactly
- Ensure all required tags are present
- Verify data types and formats

### Privacy Considerations

- Rounds are public by default when published
- Consider using private relays for rounds you don't want publicly visible
- Local storage is recommended before publishing

## Client Implementation Guidelines

### Minimum Viable Client

1. **Course Management**
   - Fetch and display course definitions
   - Allow creation of new courses
   - Store courses locally for offline use
   - Parse and display course images from `imeta` tags

2. **Round Recording**
   - Select course and tee
   - Input scores hole by hole
   - Calculate total score
   - Publish completed rounds

3. **Social Features**
   - Display rounds from followed users
   - Show attestation status
   - Allow attestation of rounds played in

### Data Validation

- Ensure all 18 holes have scores before publishing
- Validate course references exist
- Check date formats
- Verify total score matches sum of holes
- Validate tee names match course definition exactly

### Display Recommendations

- Show attestation badges on verified rounds
- Highlight disputed rounds
- Display handicap-adjusted scores when player handicaps are known
- Group rounds by course and date
- Display course images when available

## Security Considerations

1. **Round Integrity**: Attestations provide social proof but are not cryptographic proof
2. **Course Authorship**: Anyone can create course definitions; clients may want to prefer certain authors
3. **Privacy**: Published rounds are permanent and public on open relays
4. **Image Security**: Validate image URLs and consider content filtering for `imeta` tags

## References

- [NIP-01: Basic protocol flow description](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-33: Addressable Events](https://github.com/nostr-protocol/nips/blob/master/33.md)
- [NIP-92: Media Attachments](https://github.com/nostr-protocol/nips/blob/master/92.md)

---

*Note: This specification follows a progressive enhancement approach with clear upgrade paths for future features.*

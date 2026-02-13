---
name: nak
description: Use the Nostr Army Knife (nak) CLI to interact with Nostr relays — publish events, query/fetch events, decode/encode nip19 entities, verify signatures, and test event structures during development.
argument-hint: [subcommand] [args...]
allowed-tools: Bash, Read, Grep
---

# Nostr Army Knife (nak) Skill

You have access to `nak`, a powerful CLI for interacting with the Nostr protocol. Use it for testing, debugging, and validating Nostr events during development.

## Common Operations

### Publish a test event
```bash
nak event -k <kind> -c '<content>' -t <tag>=<value> --sec <nsec_or_hex> wss://relay.damus.io
```

### Query events from a relay
```bash
nak req -k <kind> -a <pubkey_hex> -l <limit> wss://relay.damus.io
```

### Fetch by nip19 code
```bash
nak fetch <nevent1...or npub1...> --relay wss://relay.damus.io
```

### Decode nip19 entities
```bash
nak decode <npub1... | nsec1... | nevent1... | nprofile1...>
```

### Encode to nip19
```bash
nak encode npub <hex_pubkey>
nak encode nevent <hex_event_id>
```

### Verify an event signature
```bash
echo '<event_json>' | nak verify
```

### Generate a keypair
```bash
nak key generate
nak key public <secret_hex>
```

## Usage with Arguments

When invoked as `/nak <args>`, execute: `nak $ARGUMENTS`

If no arguments are provided, ask what the user wants to do with nak.

## Default Relays for Gambit Golf

When no relay is specified, suggest these:
- `wss://relay.damus.io`
- `wss://nos.lol`
- `wss://relay.nostr.band`

## Tips

- Use `-q` flag to suppress info messages when piping output
- Use `--bare` with `req` to get just the filter JSON (no REQ envelope)
- Pipe events between commands: `nak req ... | nak decode`
- Use `--sec $NOSTR_SECRET_KEY` env var instead of pasting keys in commands
- Add `-qq` for fully silent mode (no stdout either)
- The `--envelope` flag on `event` wraps output in `["EVENT", ...]` format
- Use `--nevent` to get the nevent code after publishing

## Gambit Golf Context

This project publishes golf round events to Nostr. Key event kinds:
- Kind 1: Plain text notes (current implementation)
- Tags: `["t","golf"]`, `["t","gambitgolf"]`, `["client","gambit-golf-ios"]`

When testing Gambit Golf events, filter with:
```bash
nak req -k 1 --tag t=gambitgolf -l 10 wss://relay.damus.io
```

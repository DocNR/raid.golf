// RAID Golf — Bot Configuration
// Hardcoded pubkey for the RAID Golf Bot.
// The bot processes course requests sent via NIP-17 DMs.
// Future: NIP-05 lookup (bot@raid.golf) or NIP-46 bunker for key rotation.

import Foundation

enum RAIDBot {
    /// RAID Golf Bot pubkey (hex). Update when bot key rotates.
    static let pubkeyHex = "33d5b38f640d11fc9900757fe8daece3a443434eab1209da7cc87a6375fbdb0a"
}

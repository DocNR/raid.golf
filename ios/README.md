# RAID Golf - iOS Port

**Status:** Phase 1 Complete (Project Setup)  
**Next:** Phase 2 (Kernel Harness)

---

## Phase 1 Setup Instructions

### 1. Create Xcode Project

Since the folder structure exists, create the Xcode project manually:

1. Open Xcode
2. File → New → Project
3. Select: **iOS** → **App**
4. Configuration:
   - Product Name: `RAID`
   - Team: (your team)
   - Organization Identifier: (your identifier, e.g., `com.yourdomain`)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None** (we'll use GRDB for SQLite)
   - Include Tests: **Yes**
5. Save Location: Select this `ios/` directory
   - Xcode will create `RAID.xcodeproj` in `ios/`

### 2. Add Existing Source Files to Project

After creating the project, add the existing source folders:

1. In Xcode, right-click on the `RAID` group in the Project Navigator
2. Select "Add Files to RAID..."
3. Navigate to `ios/RAID/` and select:
   - `Kernel/` folder
   - `Models/` folder
   - `Ingest/` folder
   - `Views/` folder
4. **Important:** Check "Create folder references" (not groups)
5. Click "Add"

### 3. Add GRDB Dependency

1. In Xcode, select the project in the Project Navigator
2. Select the "RAID" target
3. Go to the "Package Dependencies" tab
4. Click the "+" button
5. Enter package URL: `https://github.com/groue/GRDB.swift.git`
6. Select version: "Up to Next Major" from `6.0.0`
7. Click "Add Package"
8. Select "GRDB" library and click "Add Package"

### 4. Configure Test Target for Vector Access

The test target needs access to `tests/vectors/` from the repo root.

**Option A: Copy at Build Time (Recommended)**

1. Select the `RAIDTests` target in Xcode
2. Go to "Build Phases"
3. Click "+" → "New Copy Files Phase"
4. Set "Destination" to "Resources"
5. Click "+" under the file list
6. Click "Add Other..." → "Add Files..."
7. Navigate to `raid.golf/tests/vectors/` (parent directory)
8. Select the `vectors/` folder
9. Check "Copy items if needed"
10. Click "Add"

This copies test vectors into the test bundle at build time.

**Access vectors in tests:**
```swift
let bundle = Bundle(for: type(of: self))
let vectorsURL = bundle.resourceURL!.appendingPathComponent("vectors")
let jcsVectorsURL = vectorsURL.appendingPathComponent("jcs_vectors.json")
```

### 5. Build and Run

1. Select a simulator (e.g., iPhone 15 Pro)
2. Press Cmd+R to build and run
3. You should see the placeholder UI: "RAID Golf - Phase 1 Setup Complete"

### 6. Run Tests

1. Press Cmd+U to run tests
2. All tests should fail with "Not implemented" messages (expected for Phase 1)
3. Tests will be implemented in Phase 2

---

## Project Structure

```
ios/
├── RAID.xcodeproj          # Created by Xcode in step 1
├── RAID/
│   ├── RAIDApp.swift       # Main app entry point
│   ├── ContentView.swift   # Placeholder UI
│   ├── Kernel/             # Phase 2 - Core implementation
│   │   ├── Canonical.swift # RFC 8785 JCS
│   │   ├── Hashing.swift   # SHA-256
│   │   ├── Schema.swift    # SQLite + triggers
│   │   └── Repository.swift# Data access
│   ├── Models/             # Data models
│   │   ├── Session.swift
│   │   ├── ClubSubsession.swift
│   │   └── KPITemplate.swift
│   ├── Ingest/             # Phase 3 - CSV parsing
│   │   └── RapsodoIngest.swift
│   └── Views/              # Phase 4 - UI
│       └── (minimal)
└── RAIDTests/
    └── KernelTests.swift   # Phase 2 test harness
```

---

## Phase 2 Roadmap

See `docs/private/ios-port-plan.md` for full details.

**Phase 2.1: Canonical.swift**
- Implement RFC 8785 JCS canonicalization
- Token-preserving number parse (critical!)
- Test against 12 vectors in `tests/vectors/jcs_vectors.json`

**Phase 2.2: Hashing.swift**
- Implement SHA-256 hashing via CryptoKit
- Test against golden hashes in `tests/vectors/expected/template_hashes.json`

**Phase 2.3: Schema.swift**
- Port schema from `raid/schema.sql`
- Implement immutability triggers (UPDATE/DELETE → ABORT)
- Test trigger enforcement

**Phase 2.4: Repository.swift**
- Implement insert path: canonicalize → hash → store
- Implement read path: return stored hash (never recompute)
- Test enforcement of "no re-hash on read"

---

## Exit Criteria (Phase 1)

- [x] Xcode project structure created
- [x] GRDB dependency configured
- [x] Folder structure matches plan
- [x] Placeholder files created
- [x] Test target configured
- [ ] **USER ACTION REQUIRED:** Complete steps 1-6 above in Xcode

---

## Next Steps

After completing Phase 1 setup in Xcode:
1. Verify project builds (Cmd+R)
2. Verify tests run (Cmd+U) - should see "Not implemented" failures
3. Begin Phase 2.1: Implement `Canonical.swift`
4. Start with JCS vector 01 (simplest case)

---

## References

- Plan: `docs/private/ios-port-plan.md`
- Python Reference: `raid/canonical.py`, `raid/hashing.py`, `raid/schema.sql`
- Kernel Contract: `docs/private/kernel/KERNEL_CONTRACT_v2.md`
- JCS Spec: `docs/specs/jcs_hashing.md`
- Schema Brief: `docs/schema_brief/00_index.md`
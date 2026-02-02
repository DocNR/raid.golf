#!/bin/bash
# RAID Phase 0.1 Smoke Test
# Tests basic CLI functionality end-to-end

set -e  # Exit on error

DB="./smoke_test.db"
CSV="data/session_logs/mlm2pro_shotexport_012726.csv"

echo "=== RAID Phase 0.1 Smoke Test ==="
echo

# Cleanup
if [ -f "$DB" ]; then
    echo "Cleaning up existing test database..."
    rm "$DB"
fi

# Step 1: Load templates
echo "1. Loading templates..."
python3 -m raid.cli --db "$DB" templates load
echo

# Step 2: Verify templates loaded
echo "2. Listing templates..."
python3 -m raid.cli --db "$DB" templates list
echo

# Step 3: Ingest a session
echo "3. Ingesting session from $CSV..."
python3 -m raid.cli --db "$DB" ingest "$CSV"
echo

# Step 4: List sessions
echo "4. Listing all sessions..."
python3 -m raid.cli --db "$DB" sessions
echo

# Step 5: Show session details
echo "5. Showing session 1 details..."
python3 -m raid.cli --db "$DB" show 1
echo

# Step 6: Show trend for 7i
echo "6. Showing trend for 7i..."
python3 -m raid.cli --db "$DB" trend 7i
echo

# Step 7: Export session 1
echo "7. Exporting session 1 (JSON)..."
python3 -m raid.cli --db "$DB" export 1 --format json > /dev/null
echo "✅ Export successful"
echo

# Step 8: Test idempotency - load templates again
echo "8. Testing template load idempotency..."
python3 -m raid.cli --db "$DB" templates load
echo

# Step 9: Test duplicate ingest (should create new session)
echo "9. Testing duplicate ingest (should create session 2)..."
python3 -m raid.cli --db "$DB" ingest "$CSV"
echo

# Step 10: Verify two sessions exist
echo "10. Verifying two sessions exist..."
python3 -m raid.cli --db "$DB" sessions
echo

# Cleanup
echo "Cleaning up test database..."
rm "$DB"

echo
echo "=== ✅ All smoke tests passed ==="

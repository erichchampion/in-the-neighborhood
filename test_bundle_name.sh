#!/bin/bash
# Test script to verify the app bundle name is correct

set -e

PROJECT_DIR="/Users/erich/git/github/erichchampion/in-the-neighborhood"
LOG_FILE="$PROJECT_DIR/.cursor/debug.log"

# Clean build to ensure fresh output
echo "Cleaning build..."
cd "$PROJECT_DIR"
xcodebuild clean -project "In the Neighborhood.xcodeproj" -scheme InTheNeighborhood -configuration Debug 2>&1 | head -5

# Get DerivedData path
DERIVED_DATA=$(xcodebuild -showBuildSettings -project "In the Neighborhood.xcodeproj" -target InTheNeighborhood -configuration Debug 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | sed 's/.*= *//')
echo "DerivedData: $DERIVED_DATA" | tee -a "$LOG_FILE"

# Build the project
echo "Building project..."
xcodebuild build -project "In the Neighborhood.xcodeproj" -scheme InTheNeighborhood -configuration Debug -sdk iphonesimulator 2>&1 | tee -a "$LOG_FILE" | tail -20

# Check what bundle was actually created
if [ -n "$DERIVED_DATA" ]; then
    echo "Checking bundles in: $DERIVED_DATA" | tee -a "$LOG_FILE"
    ls -la "$DERIVED_DATA"/*.app 2>/dev/null | tee -a "$LOG_FILE" || echo "No .app bundles found" | tee -a "$LOG_FILE"
    
    # Check for correct bundle name
    if [ -d "$DERIVED_DATA/In the Neighborhood.app" ]; then
        echo '{"timestamp":'$(date +%s000)',"location":"test_bundle_name.sh","message":"SUCCESS: Found correct bundle name","data":{"bundle_name":"In the Neighborhood.app"}}' >> "$LOG_FILE"
        echo "✓ SUCCESS: Found 'In the Neighborhood.app'"
        exit 0
    elif [ -d "$DERIVED_DATA/InTheNeighborhood.app" ]; then
        echo '{"timestamp":'$(date +%s000)',"location":"test_bundle_name.sh","message":"FAILED: Found wrong bundle name","data":{"bundle_name":"InTheNeighborhood.app"}}' >> "$LOG_FILE"
        echo "✗ FAILED: Found 'InTheNeighborhood.app' instead"
        exit 1
    else
        echo '{"timestamp":'$(date +%s000)',"location":"test_bundle_name.sh","message":"ERROR: No bundle found","data":{}}' >> "$LOG_FILE"
        echo "✗ ERROR: No bundle found in $DERIVED_DATA"
        exit 1
    fi
fi

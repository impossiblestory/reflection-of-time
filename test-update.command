#!/bin/bash

# =====================================
# test-update.command
# Test mode for "시간의 반영"
# Updates ONLY current.jpg
# Does NOT modify archive or archive.json
# =====================================

cd "$(dirname "$0")"

echo "====================================="
echo "TEST MODE"
echo "====================================="
echo ""
echo "This mode updates ONLY current.jpg."
echo "archive/ and archive.json are NOT modified."
echo ""

# Find newest image in incoming
latest=$(find incoming -maxdepth 1 -type f \( \
    -iname "*.jpg" -o \
    -iname "*.jpeg" -o \
    -iname "*.png" \
\) | head -n 1)

if [ -z "$latest" ]; then
    echo "No image found in incoming/"
    echo ""
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
fi

cp "$latest" current.jpg

echo ""
echo "✓ current.jpg updated."
echo "✓ archive NOT changed."
echo "✓ archive.json NOT changed."
echo "✓ No Git commit created."
echo ""
echo "You can now refresh the projection or webpage to preview."
echo ""
read -n 1 -s -r -p "Press any key to finish..."

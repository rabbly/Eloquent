#!/bin/bash
# Setup script for FillerWordDetector
# Installs xcodegen and generates the Xcode project

set -e

echo "=== FillerWordDetector Setup ==="

# Check for Homebrew
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Install it from https://brew.sh then re-run this script."
  exit 1
fi

# Install xcodegen if needed
if ! command -v xcodegen &>/dev/null; then
  echo "Installing xcodegen..."
  brew install xcodegen
else
  echo "xcodegen already installed."
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Done! Open FillerWordDetector.xcodeproj in Xcode."
echo ""
echo "Before building, in Xcode:"
echo "  1. Select the FillerWordDetector target"
echo "  2. Under Signing & Capabilities, set your Team"
echo "  3. Build & Run (Cmd+R)"
echo ""
echo "On first launch the app will request Microphone and Speech Recognition permissions."

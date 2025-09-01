#!/bin/bash

# Test script for the microphone widget
# This script tests the IPC commands that the microphone widget uses

echo "Testing Microphone Widget Functionality"
echo "======================================"

# Test input volume increase
echo "1. Testing input volume increase..."
qs -c noctalia-shell ipc call volume muteInput

# Test input volume decrease
echo "2. Testing input volume decrease..."
qs -c noctalia-shell ipc call volume muteInput

echo "Microphone widget test completed!"
echo "Check your bar to see if the Microphone widget is working correctly."
echo ""
echo "To add the Microphone widget to your bar:"
echo "1. Open the settings panel"
echo "2. Go to the Bar tab"
echo "3. Add 'Microphone' to your desired section (left, center, or right)"
echo "4. The widget will appear in your bar"

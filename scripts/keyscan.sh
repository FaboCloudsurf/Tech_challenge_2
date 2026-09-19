#!/bin/bash
echo "Scanning full git history for exposed secrets..."
git log --all -p | grep -i "BEGIN.*PRIVATE KEY" && echo "WARNING: private key found!"
git log --all -p | grep "AKIA[0-9A-Z]\{16\}" && echo "Warning: AWS key found!"
echo "Scan complete."

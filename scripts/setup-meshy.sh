#!/bin/bash
# Setup script: paste your Meshy API key and verify it works

set -e

if [ ! -f .env ]; then
    echo "ERROR: .env file not found. Run from the SALTLINE root."
    exit 1
fi

echo "=== Meshy AI Setup ==="
echo "1. Go to https://meshy.ai → Account → API Keys"
echo "2. Copy your key (starts with 'msy_')"
echo ""
read -p "Paste your MESHY_API_KEY here: " KEY

if [ -z "$KEY" ]; then
    echo "ERROR: No key provided."
    exit 1
fi

# Update .env
sed -i.bak "s/^MESHY_API_KEY=.*/MESHY_API_KEY=$KEY/" .env
rm -f .env.bak

echo "✓ Key saved to .env"

# Quick verification
if grep -q "^MESHY_API_KEY=$KEY$" .env; then
    echo "✓ .env verified"
    echo ""
    echo "Next: run the animal generator"
    echo "  python3 .claude/skills/realistic-animals/scripts/gen_animal.py \\"
    echo "    --name lamplight_crab \\"
    echo "    --prompt 'large deep-sea crab, dark chitin, long legs, raised pincers, bioluminescent lure, photoreal, neutral T pose, full body, plain background, no base' \\"
    echo "    --animate walk idle \\"
    echo "    --out assets/models/fauna"
else
    echo "ERROR: Failed to save key. Check .env manually."
    exit 1
fi

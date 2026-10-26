#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-tokens.py --check
python3 scripts/check-ui-tokens.py
swift run -j 2 SendaChecks
swift build --product Senda -j 2
bin_dir="$(swift build --show-bin-path)"
"$bin_dir/Senda" --selection-checks
"$bin_dir/Senda" --performance-checks --verify

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Command Line Tools do not ship XCTest on this host. These deterministic
# executable checks exercise the production core without requiring full Xcode.
swift run ClearFlowCoreChecks
swift build --product ClearFlow

scripts/test-audio.sh

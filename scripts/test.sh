#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift build
mkdir -p .build/test-results
set -o pipefail
.build/debug/SmartClip --self-test 2>&1 | tee .build/test-results/core.log

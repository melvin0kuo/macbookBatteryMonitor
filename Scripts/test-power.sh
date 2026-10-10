#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
models=(Sources/macbookBatteryMonitor/Model/ComponentPower.swift)
if [[ -f Sources/macbookBatteryMonitor/Model/PowerBreakdown.swift ]]; then
    models+=(Sources/macbookBatteryMonitor/Model/PowerBreakdown.swift)
fi
swiftc "${models[@]}" Sources/macbookBatteryMonitor/UI/PowerFlowLayers.swift Tests/macbookBatteryMonitorTests/*.swift Tests/main.swift -o build/tests/power-tests
build/tests/power-tests

#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
audit_temp_dir="$(mktemp -d)"
trap 'rm -rf "$audit_temp_dir"' EXIT
cp "$project_dir/Scripts/release_math_audit.swift" "$audit_temp_dir/main.swift"

swiftc \
  -suppress-warnings \
  "$project_dir/Sources/FlybookEurope/FlightNetwork.swift" \
  "$project_dir/Scripts/release_math_support.swift" \
  "$project_dir/Sources/FlybookEurope/Components.swift" \
  "$project_dir/Sources/FlybookEurope/ETOPSSettings.swift" \
  "$project_dir/Sources/FlybookEurope/Models.swift" \
  "$project_dir/Sources/FlybookEurope/CharterMath.swift" \
  "$project_dir/Sources/FlybookEurope/TimeInput.swift" \
  "$project_dir/Sources/FlybookEurope/FlightAltitudeRules.swift" \
  "$project_dir/Sources/FlybookEurope/SolarCalculator.swift" \
  "$audit_temp_dir/main.swift" \
  -o "$audit_temp_dir/release-math-audit"

"$audit_temp_dir/release-math-audit"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${RUNNER_TEMP:-/tmp}/ProtokollLogicTests"
rm -rf "$TMP"
mkdir -p "$TMP/Sources/ProtokollLogic" "$TMP/Tests/ProtokollLogicTests"

FILES=(
  "AsrRecognize/Utilities/Formatters.swift"
  "AsrRecognize/Models/TranscriptSegment.swift"
  "AsrRecognize/Models/MeetingSummary.swift"
  "AsrRecognize/Services/RecognitionLanguage.swift"
  "AsrRecognize/Services/ExportService.swift"
  "AsrRecognize/Services/ImportJobStore.swift"
  "AsrRecognize/Services/ImportValidation.swift"
  "AsrRecognize/Services/AISummaryRequest.swift"
)

for f in "${FILES[@]}"; do
  if [ -f "$ROOT/$f" ]; then cp "$ROOT/$f" "$TMP/Sources/ProtokollLogic/"; fi
done

if [ -d "$ROOT/ProtokollTests" ]; then
  cp "$ROOT"/ProtokollTests/*.swift "$TMP/Tests/ProtokollLogicTests/"
fi

cat > "$TMP/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProtokollLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ProtokollLogic"),
        .testTarget(name: "ProtokollLogicTests", dependencies: ["ProtokollLogic"])
    ]
)
EOF

swift test --package-path "$TMP"

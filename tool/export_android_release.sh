#!/bin/sh

set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PUB_VERSION=$(sed -n 's/^version:[[:space:]]*//p' "$PROJECT_ROOT/pubspec.yaml" | head -n 1)
VERSION=${PUB_VERSION%%+*}
VERSION_CODE=${PUB_VERSION#*+}
BUILD_OUTPUT="$PROJECT_ROOT/build/app/outputs"
FLUTTER_APK_OUTPUT="$BUILD_OUTPUT/flutter-apk"
GRADLE_APK_OUTPUT="$BUILD_OUTPUT/apk/release"
APK_METADATA="$GRADLE_APK_OUTPUT/output-metadata.json"
STAGING_DIR="$BUILD_OUTPUT/fknotes-release"
STAGED_UNIVERSAL_APK="$STAGING_DIR/app-universal-release.apk"
STAGED_UNIVERSAL_METADATA="$STAGING_DIR/universal-output-metadata.json"
RELEASE_ROOT=${FKNOTES_RELEASE_ROOT:-"$PROJECT_ROOT/release/android"}
RELEASE_DIR="$RELEASE_ROOT/$VERSION"
NOTES_PATH="$PROJECT_ROOT/docs/releases/$VERSION.md"
GITHUB_REPOSITORY=${FKNOTES_GITHUB_REPOSITORY:-wsshow/feikong-notes}
UPDATE_MANDATORY=${FKNOTES_UPDATE_MANDATORY:-false}
RELEASE_DATE=${FKNOTES_RELEASE_DATE:-}

UNIVERSAL_NAME="fknotes-$VERSION+$VERSION_CODE-universal-release.apk"
ARM64_NAME="fknotes-$VERSION+$VERSION_CODE-arm64-v8a-release.apk"

if [ -z "$RELEASE_DATE" ]; then
  RELEASE_DATE=$(date +%F)
fi

case "$PUB_VERSION" in
  *+*) ;;
  *)
    echo "pubspec.yaml version must include a build number, for example 0.1.0+1." >&2
    exit 1
    ;;
esac

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "Invalid release version in pubspec.yaml: $PUB_VERSION" >&2
    exit 1
    ;;
esac

case "$VERSION_CODE" in
  ''|0|*[!0-9]*)
    echo "Invalid Android versionCode in pubspec.yaml: $PUB_VERSION" >&2
    exit 1
    ;;
esac

case "$UPDATE_MANDATORY" in
  true|false) ;;
  *)
    echo "FKNOTES_UPDATE_MANDATORY must be true or false." >&2
    exit 1
    ;;
esac

case "$RELEASE_DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *)
    echo "FKNOTES_RELEASE_DATE must use YYYY-MM-DD." >&2
    exit 1
    ;;
esac

mkdir -p "$RELEASE_DIR"

if [ ! -s "$NOTES_PATH" ]; then
  echo "Release notes are missing or empty: $NOTES_PATH" >&2
  echo "Create docs/releases/$VERSION.md before building." >&2
  exit 1
fi

if [ "${1:-}" = "--check-notes" ]; then
  if [ -d "$STAGING_DIR" ]; then
    find "$STAGING_DIR" -depth -delete
  fi
  exit 0
fi

metadata_version_name() {
  sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

metadata_version_code() {
  sed -n 's/.*"versionCode"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" | head -n 1
}

metadata_output_count() {
  sed -n 's/.*"outputFile"[[:space:]]*:[[:space:]]*"[^"]*".*/x/p' "$1" | wc -l | tr -d ' '
}

verify_metadata() {
  metadata=$1
  label=$2
  built_version=$(metadata_version_name "$metadata")
  built_version_code=$(metadata_version_code "$metadata")
  output_count=$(metadata_output_count "$metadata")
  if [ "$output_count" != "1" ]; then
    echo "$label build must contain exactly one APK output; found $output_count." >&2
    exit 1
  fi
  if [ "$built_version" != "$VERSION" ]; then
    echo "$label versionName mismatch: pubspec=$VERSION, APK=$built_version." >&2
    exit 1
  fi
  if [ "$built_version_code" != "$VERSION_CODE" ]; then
    echo "$label versionCode mismatch: pubspec=$VERSION_CODE, APK=$built_version_code." >&2
    exit 1
  fi
}

if [ "${1:-}" = "--stage-universal" ]; then
  UNIVERSAL_SOURCE="$FLUTTER_APK_OUTPUT/app-release.apk"
  if [ ! -f "$UNIVERSAL_SOURCE" ] || [ ! -f "$APK_METADATA" ]; then
    echo "Universal release APK or metadata is missing." >&2
    exit 1
  fi
  verify_metadata "$APK_METADATA" "Universal"
  python3 "$PROJECT_ROOT/tool/check_android_release.py" "$UNIVERSAL_SOURCE"
  mkdir -p "$STAGING_DIR"
  cp "$UNIVERSAL_SOURCE" "$STAGED_UNIVERSAL_APK"
  cp "$APK_METADATA" "$STAGED_UNIVERSAL_METADATA"
  echo "Universal Android APK staged for release export."
  exit 0
fi

ARM64_SOURCE="$FLUTTER_APK_OUTPUT/app-release.apk"
for required_file in \
  "$STAGED_UNIVERSAL_APK" \
  "$STAGED_UNIVERSAL_METADATA" \
  "$APK_METADATA" \
  "$ARM64_SOURCE"
do
  if [ ! -f "$required_file" ]; then
    echo "Release artifact is missing: $required_file" >&2
    echo "Run the complete Android release target instead of the export script directly." >&2
    exit 1
  fi
done

verify_metadata "$STAGED_UNIVERSAL_METADATA" "Universal"
verify_metadata "$APK_METADATA" "arm64-v8a"
python3 "$PROJECT_ROOT/tool/check_android_release.py" "$STAGED_UNIVERSAL_APK" "$ARM64_SOURCE"

apk_abis() {
  unzip -Z1 "$1" | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u
}

ARM64_ABIS=$(apk_abis "$ARM64_SOURCE")
if [ "$ARM64_ABIS" != "arm64-v8a" ]; then
  echo "arm64-v8a APK contains unexpected ABIs:" >&2
  echo "$ARM64_ABIS" >&2
  exit 1
fi

UNIVERSAL_ABIS=$(apk_abis "$STAGED_UNIVERSAL_APK")
UNIVERSAL_ABI_COUNT=$(printf '%s\n' "$UNIVERSAL_ABIS" | sed '/^$/d' | wc -l | tr -d ' ')
if ! printf '%s\n' "$UNIVERSAL_ABIS" | grep -qx 'arm64-v8a' || [ "$UNIVERSAL_ABI_COUNT" -lt 2 ]; then
  echo "Universal APK does not contain the expected fallback ABIs:" >&2
  echo "$UNIVERSAL_ABIS" >&2
  exit 1
fi

find "$RELEASE_DIR" -maxdepth 1 -type f \( -name 'fknotes-*.apk' -o -name 'fknotes-*.apk.sha256' \) -delete
cp "$STAGED_UNIVERSAL_APK" "$RELEASE_DIR/$UNIVERSAL_NAME"
cp "$ARM64_SOURCE" "$RELEASE_DIR/$ARM64_NAME"

for apk_name in "$UNIVERSAL_NAME" "$ARM64_NAME"
do
  (
    cd "$RELEASE_DIR"
    shasum -a 256 "$apk_name" > "$apk_name.sha256"
  )
done

find "$RELEASE_DIR" -maxdepth 1 -type f \( -name '*.aab' -o -name 'SHA256SUMS' -o -name '.DS_Store' \) -delete
if [ -d "$RELEASE_DIR/r8" ]; then
  find "$RELEASE_DIR/r8" -depth -delete
fi

python3 "$PROJECT_ROOT/tool/prepare_github_release.py" \
  --dist "$RELEASE_DIR" \
  --repository "$GITHUB_REPOSITORY" \
  --version "$VERSION" \
  --build-number "$VERSION_CODE" \
  --notes "$NOTES_PATH" \
  --date "$RELEASE_DATE" \
  --mandatory "$UPDATE_MANDATORY"
cp "$RELEASE_DIR/latest.json" "$RELEASE_ROOT/latest.json"

find "$RELEASE_ROOT" -name '.DS_Store' -type f -delete
find "$STAGING_DIR" -depth -delete

echo "Android release $VERSION exported with one shared versionCode ($VERSION_CODE)."
echo "Artifacts: universal and arm64-v8a."

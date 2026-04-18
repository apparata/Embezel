#!/bin/bash
#
# Build, sign, notarize, and release Embezel via GitHub Releases with Sparkle.
#
# Requirements:
#   - Xcode command line tools
#   - gh CLI (authenticated)
#   - xcrun notarytool keychain profile named "notary" already stored
#     (run: xcrun notarytool store-credentials notary --apple-id <APPLE_ID> --team-id DR5YAK7GKS)
#

set -euo pipefail

# ---------- Constants ----------

SCHEME="AppSnap (Release)"
PROJECT_NAME="AppSnap"
APP_NAME="Embezel"
BUNDLE_ID="se.apparata.AppSnap"
TEAM_ID="DR5YAK7GKS"
KEYCHAIN_PROFILE="notary"
SPARKLE_VERSION="2.9.0"
GH_OWNER="apparata"
GH_REPO="Embezel"

# ---------- Paths ----------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SPARKLE_TOOLS_DIR="$PROJECT_DIR/Sparkle-tools"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
INFO_PLIST_SOURCE="$PROJECT_DIR/AppSnap/Info.plist"
PROJECT_PBXPROJ="$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj"

# ---------- Helpers ----------

error() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo ""
    echo "==> $*"
}

dump_log_on_failure() {
    local log="$1"
    if [ -f "$log" ]; then
        echo ""
        echo "--- Last 30 lines of $(basename "$log") ---"
        tail -30 "$log"
    fi
}

# ---------- Sanity checks ----------

command -v xcodebuild >/dev/null || error "xcodebuild not found"
command -v gh >/dev/null || error "gh CLI not found (brew install gh)"
command -v hdiutil >/dev/null || error "hdiutil not found"
command -v /usr/libexec/PlistBuddy >/dev/null || error "PlistBuddy not found"

[ -f "$EXPORT_OPTIONS" ] || error "ExportOptions.plist not found at $EXPORT_OPTIONS"
[ -f "$INFO_PLIST_SOURCE" ] || error "Info.plist not found at $INFO_PLIST_SOURCE"
[ -f "$PROJECT_PBXPROJ" ] || error "project.pbxproj not found at $PROJECT_PBXPROJ"

# ---------- Clean build dir ----------

info "Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------- Ensure Sparkle tools ----------

if [ ! -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ]; then
    info "Downloading Sparkle $SPARKLE_VERSION tools"
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        -o "$BUILD_DIR/Sparkle.tar.xz" \
        || error "Failed to download Sparkle tools"
    mkdir -p "$SPARKLE_TOOLS_DIR"
    tar -xf "$BUILD_DIR/Sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" || error "Failed to extract Sparkle tools"
    rm "$BUILD_DIR/Sparkle.tar.xz"
fi

[ -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ] || error "sign_update not found or not executable"
[ -x "$SPARKLE_TOOLS_DIR/bin/generate_appcast" ] || error "generate_appcast not found or not executable"

# ---------- Version management ----------

info "Checking version"

CURRENT_VERSION="$(xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | grep -E '^\s*MARKETING_VERSION\s*=' | head -1 | awk -F'= ' '{print $2}' | tr -d ' ' || true)"

if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_SOURCE" 2>/dev/null || true)"
fi

[ -n "$CURRENT_VERSION" ] || error "Could not determine current version"

echo "Current version: $CURRENT_VERSION"

LATEST_TAG="$(gh release view --repo "$GH_OWNER/$GH_REPO" --json tagName -q '.tagName' 2>/dev/null || true)"
if [ -n "$LATEST_TAG" ]; then
    echo "Latest GitHub release: $LATEST_TAG"
else
    echo "No existing GitHub release found"
fi

version_gt() {
    # Returns 0 if $1 > $2, 1 otherwise. Uses sort -V.
    [ "$1" = "$2" ] && return 1
    local highest
    highest="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)"
    [ "$highest" = "$1" ]
}

NEW_VERSION="$CURRENT_VERSION"
VERSION_BUMPED="no"

if [ -n "$LATEST_TAG" ] && ! version_gt "$CURRENT_VERSION" "$LATEST_TAG"; then
    echo ""
    echo "Current version ($CURRENT_VERSION) is not newer than latest release ($LATEST_TAG)."
    while true; do
        read -r -p "Enter new version (e.g. 1.2.0): " NEW_VERSION
        if [ -z "$NEW_VERSION" ]; then
            echo "Version cannot be empty."
            continue
        fi
        if ! version_gt "$NEW_VERSION" "$LATEST_TAG"; then
            echo "Version $NEW_VERSION must be newer than $LATEST_TAG."
            continue
        fi
        break
    done
    VERSION_BUMPED="yes"
fi

if [ "$VERSION_BUMPED" = "yes" ]; then
    info "Updating version to $NEW_VERSION"

    # Update MARKETING_VERSION in project.pbxproj
    sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1$NEW_VERSION;/g" "$PROJECT_PBXPROJ" \
        || error "Failed to update MARKETING_VERSION in project.pbxproj"

    # Update CURRENT_PROJECT_VERSION in project.pbxproj
    sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[^;]+;/\1$NEW_VERSION;/g" "$PROJECT_PBXPROJ" \
        || error "Failed to update CURRENT_PROJECT_VERSION in project.pbxproj"

    # Update Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST_SOURCE" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $NEW_VERSION" "$INFO_PLIST_SOURCE" \
        || error "Failed to set CFBundleShortVersionString"

    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST_SOURCE" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $NEW_VERSION" "$INFO_PLIST_SOURCE" \
        || error "Failed to set CFBundleVersion"

    cd "$PROJECT_DIR"
    git add "$PROJECT_PBXPROJ" "$INFO_PLIST_SOURCE"
    git commit -m "Bump to $NEW_VERSION" || error "Failed to commit version bump"
    git push origin HEAD || error "Failed to push version bump"
fi

VERSION="$NEW_VERSION"
TAG="$VERSION"

# ---------- Release title ----------

info "Release title"
read -r -p "Release title (leave empty to use '$VERSION'): " RELEASE_TITLE
if [ -z "$RELEASE_TITLE" ]; then
    RELEASE_TITLE="$VERSION"
fi
read -r -p "Release subtitle (optional, shown in release notes): " RELEASE_SUBTITLE || true

# ---------- Archive ----------

info "Archiving"
xcodebuild archive \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    -arch arm64 \
    ENABLE_HARDENED_RUNTIME=YES \
    2>&1 | tee "$BUILD_DIR/archive.log" | tail -5 \
    || { dump_log_on_failure "$BUILD_DIR/archive.log"; error "xcodebuild archive failed"; }

[ -d "$ARCHIVE_PATH" ] || { dump_log_on_failure "$BUILD_DIR/archive.log"; error "Archive not produced at $ARCHIVE_PATH"; }

# ---------- Export ----------

info "Exporting archive"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>&1 | tee "$BUILD_DIR/export.log" | tail -5 \
    || { dump_log_on_failure "$BUILD_DIR/export.log"; error "xcodebuild export failed"; }

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP_PATH" ] || { dump_log_on_failure "$BUILD_DIR/export.log"; error "Exported app not found at $APP_PATH"; }

# Sanity check: version from exported app
EXPORTED_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
echo "Exported app version: $EXPORTED_VERSION"
if [ "$EXPORTED_VERSION" != "$VERSION" ]; then
    error "Exported version ($EXPORTED_VERSION) does not match expected version ($VERSION)"
fi

# ---------- Verify codesign ----------

info "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || error "codesign verification failed"

# ---------- Create DMG ----------

info "Creating DMG"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -a "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    || error "hdiutil failed to create DMG"

rm -rf "$DMG_STAGING"
[ -f "$DMG_PATH" ] || error "DMG not created at $DMG_PATH"

# ---------- Notarize ----------

info "Submitting DMG for notarization (this may take several minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait \
    2>&1 | tee "$BUILD_DIR/notarize.log" \
    || { dump_log_on_failure "$BUILD_DIR/notarize.log"; error "Notarization failed"; }

if ! grep -q "status: Accepted" "$BUILD_DIR/notarize.log"; then
    dump_log_on_failure "$BUILD_DIR/notarize.log"
    error "Notarization did not reach Accepted status"
fi

info "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH" || error "stapler staple failed"
xcrun stapler validate "$DMG_PATH" || error "stapler validate failed"

# ---------- Sign for Sparkle ----------

info "Signing DMG for Sparkle"
SPARKLE_SIG_OUTPUT="$("$SPARKLE_TOOLS_DIR/bin/sign_update" "$DMG_PATH")" \
    || error "Sparkle sign_update failed"
echo "$SPARKLE_SIG_OUTPUT"

# ---------- Tag, push, create GitHub release ----------

info "Tagging and pushing"
cd "$PROJECT_DIR"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag $TAG already exists locally."
else
    git tag "$TAG" || error "Failed to create tag"
fi

git push origin "$TAG" || error "Failed to push tag"

info "Creating GitHub release"
RELEASE_NOTES_ARGS=("--generate-notes")
if [ -n "${RELEASE_SUBTITLE:-}" ]; then
    RELEASE_NOTES_FILE="$BUILD_DIR/release-notes.md"
    {
        echo "$RELEASE_SUBTITLE"
        echo ""
    } > "$RELEASE_NOTES_FILE"
    RELEASE_NOTES_ARGS=("--notes-file" "$RELEASE_NOTES_FILE" "--generate-notes")
fi

gh release create "$TAG" \
    --repo "$GH_OWNER/$GH_REPO" \
    --title "$RELEASE_TITLE" \
    "${RELEASE_NOTES_ARGS[@]}" \
    "$DMG_PATH" \
    || error "Failed to create GitHub release"

# ---------- Generate appcast ----------

info "Generating appcast"
APPCAST_DIR="$BUILD_DIR/appcast-assets"
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"

if [ -f "$PROJECT_DIR/appcast.xml" ]; then
    cp "$PROJECT_DIR/appcast.xml" "$APPCAST_DIR/"
fi

cp "$DMG_PATH" "$APPCAST_DIR/"

"$SPARKLE_TOOLS_DIR/bin/generate_appcast" \
    --download-url-prefix "https://github.com/$GH_OWNER/$GH_REPO/releases/download/$TAG/" \
    -o "$APPCAST_DIR/appcast.xml" \
    "$APPCAST_DIR" \
    || error "generate_appcast failed"

cp "$APPCAST_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"

cd "$PROJECT_DIR"
git add appcast.xml
if git diff --cached --quiet; then
    echo "appcast.xml unchanged, nothing to commit."
else
    git commit -m "Update appcast for $VERSION" || error "Failed to commit appcast"
    git push origin HEAD || error "Failed to push appcast"
fi

info "Done!"
echo "Released $APP_NAME $VERSION"
echo "DMG: $DMG_PATH"
echo "Release: https://github.com/$GH_OWNER/$GH_REPO/releases/tag/$TAG"

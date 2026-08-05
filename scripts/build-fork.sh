#!/usr/bin/env bash
#
# Builds this fork into a signed, stripped, arm64-only "Atoll Fork.app".
#
# It installs beside a stock Atoll rather than over it: the fork carries its own
# bundle identifier, so the two keep separate settings and separate permission
# grants, and nothing here ever touches /Applications/Atoll.app.
#
#   ./scripts/build-fork.sh              build, strip, prune, sign
#   ./scripts/build-fork.sh --dmg        also package a .dmg
#   ./scripts/build-fork.sh --install    also install /Applications/Atoll Fork.app
#
# Signing: set SIGN_IDENTITY to a certificate in your keychain. A stable
# identity matters more than it looks — macOS ties Accessibility, Calendar and
# Screen Recording grants to the code signature, so an ad-hoc signature (whose
# hash changes on every build) makes the system re-ask for every permission
# after each rebuild. Create one in Keychain Access:
#   Certificate Assistant → Create a Certificate
#   Name: Atoll Personal · Identity Type: Self Signed Root · Type: Code Signing
# Falls back to ad-hoc so the script still works before that exists.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-Atoll Personal}"
APP_NAME="${APP_NAME:-Atoll Fork}"   # installed beside the upstream Atoll.app
KEEP_LOCALES="${KEEP_LOCALES:-en ru Base}"
BUILD_DIR="$REPO/.build-fork"
LOG="$BUILD_DIR/xcodebuild.log"

WANT_DMG=false
WANT_INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --dmg)     WANT_DMG=true ;;
        --install) WANT_INSTALL=true ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

mkdir -p "$BUILD_DIR"
rm -rf "$BUILD_DIR/Release"

say "Building (arm64, Release, no coverage)"
# ENABLE_CODE_COVERAGE=NO: without it the SPM dependencies come back
# instrumented, which costs both size and a counter on every branch.
# CODE_SIGNING_ALLOWED=NO here because stripping invalidates a signature —
# the app is signed further down, after it has been stripped and pruned.
xcodebuild \
    -project "$REPO/DynamicIsland.xcodeproj" \
    -scheme DynamicIsland \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_CODE_COVERAGE=NO \
    CLANG_COVERAGE_MAPPING=NO \
    CODE_SIGNING_ALLOWED=NO \
    build > "$LOG" 2>&1 \
  || { echo "build failed — see $LOG"; grep -aE "error:" "$LOG" | sort -u | head -20; exit 1; }

BUILT="$BUILD_DIR/Release/Atoll.app"
[ -d "$BUILT" ] || { echo "no app at $BUILT"; exit 1; }

before=$(du -sm "$BUILT" | cut -f1)

# Installed beside the upstream build, so the bundle needs its own name. Only the
# directory is renamed — the executable inside keeps the name Info.plist declares
# in CFBundleExecutable, and nothing is signed yet.
APP="$BUILD_DIR/Release/$APP_NAME.app"
rm -rf "$APP"
[ "$BUILT" = "$APP" ] || mv "$BUILT" "$APP"
BIN="$APP/Contents/MacOS/Atoll"

say "Stripping symbols"
# A local Release build keeps the full symbol table — ~46 MB of __LINKEDIT on
# this project. The dSYM in DerivedData keeps what is needed to symbolicate.
chmod u+w "$BIN"
strip -rSTx "$BIN"

say "Pruning locales (keeping: $KEEP_LOCALES)"
for lproj in "$APP/Contents/Resources"/*.lproj; do
    [ -d "$lproj" ] || continue
    name=$(basename "$lproj" .lproj)
    keep=false
    for k in $KEEP_LOCALES; do [ "$name" = "$k" ] && keep=true; done
    $keep || rm -rf "$lproj"
done

say "Signing as: $SIGN_IDENTITY"
# Deliberately not `find-identity -v`: a self-signed root is reported
# CSSMERR_TP_NOT_TRUSTED and filtered out by -v, yet it signs perfectly well.
# What matters here is that the identity is stable between builds, which is
# what keeps the permission grants; trusting it is a separate question.
if security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
    identity="$SIGN_IDENTITY"
else
    echo "  ! '$SIGN_IDENTITY' not found in the keychain — falling back to ad-hoc."
    echo "    Permissions will be re-requested after every rebuild until a stable"
    echo "    certificate exists. See the header of this script."
    identity="-"
fi
# Frameworks first: codesign refuses to seal a bundle whose nested code is
# unsigned or was signed after the outer bundle.
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null |
    while IFS= read -r -d '' item; do
        codesign --force --sign "$identity" --timestamp=none --options runtime "$item" >/dev/null 2>&1 || true
    done
codesign --force --deep --sign "$identity" --timestamp=none \
    --entitlements "$REPO/DynamicIsland/DynamicIsland.entitlements" \
    "$APP" 2>&1 | sed 's/^/  /'

say "Verifying"
codesign --verify --deep --strict "$APP" && echo "  signature OK"
authority=$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
if [ "$identity" = "-" ]; then
    echo "  signed: ad-hoc"
else
    [ "$authority" = "$identity" ] \
        || { echo "  ! expected to be signed by '$identity' but got '${authority:-ad-hoc}'"; exit 1; }
    echo "  signed by: $authority"
fi
arch_line=$(lipo -info "$BIN")
echo "  $arch_line"
case "$arch_line" in *x86_64*) echo "  ! still fat — ARCHS did not take"; exit 1 ;; esac
cov=$(otool -l "$BIN" | grep -c "__LLVM_COV" || true)
echo "  __LLVM_COV segments: $cov"
after=$(du -sm "$APP" | cut -f1)
echo "  app size: ${before} MB → ${after} MB"

if $WANT_DMG; then
    say "Packaging .dmg"
    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
    dmg="$BUILD_DIR/${APP_NAME// /-}-$version.dmg"
    rm -f "$dmg"
    staging="$BUILD_DIR/dmg-staging"
    rm -rf "$staging"; mkdir -p "$staging"
    cp -R "$APP" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "Atoll" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
    rm -rf "$staging"
    echo "  $dmg ($(du -sh "$dmg" | cut -f1))"
fi

if $WANT_INSTALL; then
    say "Installing to /Applications"
    # Only ever touches this fork's own bundle, never /Applications/Atoll.app.
    pkill -f "/Applications/$APP_NAME.app" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "  /Applications/$APP_NAME.app"
fi

say "Done"
echo "  $APP"

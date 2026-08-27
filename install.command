#!/bin/zsh
#
# install.command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
APP_NAME="RALBEOSXToolbox"
DISPLAY_NAME="RALBE OSX Toolbox"
BUILD_CONFIG="release"
APP_BUNDLE="$PROJECT_DIR/$DISPLAY_NAME.app"
INSTALL_DIR="/Applications"

echo "=================================="
echo " $DISPLAY_NAME installer"
echo "=================================="

if ! command -v swift >/dev/null 2>&1; then
    echo ""
    echo "ERROR: Swift toolchain not found."
    echo "Install the Xcode Command Line Tools first, then re-run this script:"
    echo "    xcode-select --install"
    exit 1
fi

echo ""
echo "-> Building $DISPLAY_NAME ($BUILD_CONFIG)..."
cd "$PROJECT_DIR"

set +e
swift build -c "$BUILD_CONFIG" 2>&1 | grep -v -E "ld: warning: search path '.*CommandLineTools/Developer/(usr/lib|Library/Frameworks)' not found"
BUILD_EXIT=${pipestatus[1]}
set -e
if [ "$BUILD_EXIT" -ne 0 ]; then
    exit "$BUILD_EXIT"
fi

BIN_PATH="$PROJECT_DIR/.build/$BUILD_CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo ""
    echo "ERROR: Build finished but binary not found at:"
    echo "    $BIN_PATH"
    exit 1
fi

echo ""
echo "-> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

ICON_SOURCE="$PROJECT_DIR/toolbox_icon.png"
if [ -f "$ICON_SOURCE" ]; then
    echo ""
    echo "-> Building app icon..."
    ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "   WARNING: $ICON_SOURCE not found, app will use the default icon."
fi

echo ""
echo "-> Preparing a stable local code-signing identity..."
# Plain ad-hoc signing (--sign -) hashes the whole binary, so every rebuild
# gets a different signature and macOS treats it as a "new" app - resetting
# Accessibility/Full Disk Access/etc. A self-signed certificate gives the
# app a STABLE identity across rebuilds so TCC grants survive them.
SIGNING_IDENTITY_NAME="RALBE OSX Toolbox Local Dev"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if ! security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -q "$SIGNING_IDENTITY_NAME"; then
    echo "   No local signing identity found - creating one now (one-time setup)."
    CERT_DIR="$(mktemp -d)"
    cat > "$CERT_DIR/cert.cnf" <<CNF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ext
prompt = no

[req_distinguished_name]
CN = $SIGNING_IDENTITY_NAME

[v3_ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

    if openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
            -days 36500 -nodes -config "$CERT_DIR/cert.cnf" >/dev/null 2>&1 \
        && openssl pkcs12 -export -out "$CERT_DIR/cert.p12" -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" -passout pass:ralbetoolbox >/dev/null 2>&1 \
        && security import "$CERT_DIR/cert.p12" -k "$LOGIN_KEYCHAIN" -P "ralbetoolbox" -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 \
        && security add-trusted-cert -d -r trustRoot -k "$LOGIN_KEYCHAIN" "$CERT_DIR/cert.pem" >/dev/null 2>&1; then
        echo "   Created '$SIGNING_IDENTITY_NAME' in your login keychain (self-signed,"
        echo "   code-signing only - visible/removable any time in Keychain Access)."
    else
        echo "   WARNING: could not create a local signing identity - falling back to"
        echo "   ad-hoc signing. Permissions will need re-granting after each rebuild."
    fi
    rm -rf "$CERT_DIR"
fi

if security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -q "$SIGNING_IDENTITY_NAME"; then
    SIGN_IDENTITY="$SIGNING_IDENTITY_NAME"
else
    SIGN_IDENTITY="-"
fi

echo ""
echo "-> Signing app (identity: $SIGN_IDENTITY)..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "-> Installing..."
FINAL_PATH="$APP_BUNDLE"
if [ -w "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR/$DISPLAY_NAME.app"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    FINAL_PATH="$INSTALL_DIR/$DISPLAY_NAME.app"
    echo "   Installed to $FINAL_PATH"
else
    # /Applications isn't writable by the current user (no admin group
    # membership, or an ACL) - fall back to the native macOS admin
    # password/Touch ID prompt rather than silently leaving the app
    # un-installed; the user can cancel it.
    echo "   No write access to $INSTALL_DIR - requesting administrator privileges..."
    ESCAPED_SRC="${APP_BUNDLE//\'/\'\\\'\'}"
    ESCAPED_DST="${INSTALL_DIR//\'/\'\\\'\'}/${DISPLAY_NAME//\'/\'\\\'\'}.app"
    if osascript -e "do shell script \"rm -rf '$ESCAPED_DST' && cp -R '$ESCAPED_SRC' '$ESCAPED_DST'\" with administrator privileges" >/dev/null 2>&1; then
        FINAL_PATH="$INSTALL_DIR/$DISPLAY_NAME.app"
        echo "   Installed to $FINAL_PATH"
    else
        echo "   Administrator authorization was not granted - app left at $APP_BUNDLE"
    fi
fi

echo ""
echo "=================================="
echo " Done!"
echo "=================================="
echo ""
echo "IMPORTANT - Permissions:"
echo "RALBE OSX Toolbox needs Accessibility access (Autoclicker + Caffeine"
echo "Injection hotkeys), may separately prompt for Input Monitoring access"
echo "(global shortcuts), Location Services (WiFi SSID trigger), and Full Disk"
echo "Access (App Cleaner). It will prompt for what it can on first launch; for"
echo "the rest, open System Settings > Privacy & Security and enable"
echo "'$DISPLAY_NAME' under Accessibility, Input Monitoring, and Full Disk Access."
echo ""
echo "Menu bar: a single '$DISPLAY_NAME' menu bar icon gives access to all three"
echo "tools (Caffeine Injection, Autoclicker, App Cleaner). Autoclicker also has"
echo "its own window, opened via the menu bar or by relaunching the app."
echo ""
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "NOTE: signed ad-hoc this time (fallback), which changes signature on"
    echo "every rebuild and can reset permissions. If access seems stuck, remove"
    echo "'$DISPLAY_NAME' from the relevant Privacy & Security list and re-add it."
else
    echo "NOTE: signed with the stable local identity '$SIGN_IDENTITY', so"
    echo "permissions should now persist across rebuilds - no need to remove and"
    echo "re-grant them each time you update the app."
fi
echo ""

open "$FINAL_PATH"

echo "Press Return to close this window..."
read -r _

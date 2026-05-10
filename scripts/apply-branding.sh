#!/usr/bin/env bash
#
# Faza 0g.3 (08.05.2026): apply Printsoft Assist branding na RustDesk source.
#
# Zaklada ze CWD to root sklonowanego RustDesk (forka mc-printsoft/printsoft-assist-client).
# Aplikuje sed patches + kopiuje assets z patches/../assets.
#
# Uruchomienie:
#   cd /path/to/printsoft-assist-client
#   bash /path/to/printsoft-suite/infra/assist/client/scripts/apply-branding.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/../patches"
ASSETS_DIR="${SCRIPT_DIR}/../assets"

echo "=== Printsoft Assist branding apply ==="
echo "Working directory: $(pwd)"

# Sanity check — czy jestesmy w forku RustDesk?
if [ ! -f "Cargo.toml" ] || ! grep -q '^name = "rustdesk"' Cargo.toml 2>/dev/null; then
  if ! grep -q '^name = "printsoft-assist"' Cargo.toml 2>/dev/null; then
    echo "BLAD: nie jestem w forku RustDesk (brak Cargo.toml z name=rustdesk)."
    exit 1
  fi
  echo "INFO: branding juz zaplikowany (Cargo.toml ma printsoft-assist). Refresh."
fi

# ─── 1. Default rendezvous + pubkey w libs/hbb_common/src/config.rs ───
echo "[1/8] Rendezvous server + public key (config.rs)"
sed -i.bak 's|"rs-ny.rustdesk.com"|"assist.printsoft.app"|g' libs/hbb_common/src/config.rs
sed -i.bak 's|"OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw="|"iIaqYsmm0eIZOo9xVs1ONg5X1NEBgWrAmWhHEivW9ow="|g' libs/hbb_common/src/config.rs

# ─── 2. APP_NAME w config.rs (RwLock default value) ───
echo "[2/8] APP_NAME (Printsoft Assist)"
sed -i.bak 's|RwLock::new("RustDesk".to_owned())|RwLock::new("Printsoft Assist".to_owned())|g' libs/hbb_common/src/config.rs

# ─── 3. Update endpoint (libs/hbb_common/src/lib.rs) ───
echo "[3/8] Update endpoint (api.rustdesk.com -> ps.printsoft.app)"
sed -i.bak 's|https://api.rustdesk.com/version/latest|https://ps.printsoft.app/api/assist/agent/version|g' libs/hbb_common/src/lib.rs

# ─── 4. is_custom_client guard ───
# Po rebrand APP_NAME != "RustDesk" -> is_custom_client zwraca true ->
# check_software_update early-return. Patchujemy żeby update flow działał.
echo "[4/8] Wlacz update flow dla custom client (src/common.rs)"
# Zmieniam guard `if is_custom_client()` w check_software_update na noop comment.
# Dokladne miejsce: src/common.rs ~line 1010 funkcja check_software_update.
# Robimy to ostroznie - jesli linia wyglada inaczej w nowej wersji, sed nic nie robi
# i widac to w git diff.
if grep -q 'if is_custom_client() {' src/common.rs; then
  # Pierwsze wystapienie w pliku (po check_software_update) - guard early return.
  # Strategie: zmieniam if -> if false (zostawiamy sygnaturę żeby nie wywaylac kompilacji).
  # Editujemy tylko linie wewnatrz check_software_update: szukamy unique pattern.
  python3 - <<'PYEOF'
import re
with open('src/common.rs', 'r') as f:
    content = f.read()

# Szukam funkcji check_software_update i zamieniam pierwszy if is_custom_client
# wewnątrz niej na `if false &&` żeby uszanować logiczna intencje a nie cache'owalo update.
pattern = re.compile(r'(fn check_software_update[^{]*\{[\s\S]*?)if is_custom_client\(\) \{[\s\S]*?return;[\s\S]*?\}', re.MULTILINE)
new_content, count = pattern.subn(r'\1// PRINTSOFT ASSIST: is_custom_client guard removed (auto-update enabled)', content, count=1)
if count > 0:
    with open('src/common.rs', 'w') as f:
        f.write(new_content)
    print(f"   patched {count} occurrence(s) in check_software_update")
else:
    print("   WARN: nie znaleziono guard - moze RustDesk zmienil strukture, sprawdz recznie")
PYEOF
fi

# ─── 5. Cargo.toml package name ───
# UWAGA: RustDesk Cargo.toml ma kilka miejsc z "rustdesk":
#   1. [package] name = "rustdesk"        -> "printsoft-assist"
#   2. [package] default-run = "rustdesk" -> "printsoft-assist" (musi pasowac do package name)
#   3. [package.metadata.bundle] name = "RustDesk" -> "Printsoft Assist" (macOS .app bundle name)
#      [package.metadata.bundle] identifier = "com.carriez.rustdesk" -> "app.printsoft.assist"
#
# UWAGA: NIE zmieniamy [lib] name = "librustdesk" — to nazwa biblioteki uzywana
# w 10+ plikach (.rs, .dart, CMake). Zostaje "librustdesk", bo to tylko internal
# library name i Flutter ja loaduje przez konkretne sciezki w native_model.dart.
echo "[5/8] Cargo.toml metadata"
sed -i.bak 's|^name = "rustdesk"|name = "printsoft-assist"|' Cargo.toml
sed -i.bak 's|^default-run = "rustdesk"|default-run = "printsoft-assist"|' Cargo.toml
sed -i.bak 's|^description = .*|description = "Printsoft Assist - remote support tool"|' Cargo.toml
# [package.metadata.bundle] - zmieniamy 'name = "RustDesk"' i 'identifier'.
# UWAGA: 'name = "RustDesk"' wystepuje w [package.metadata.bundle] sekcji,
# ale sed nie wie o sekcjach. Robimy to przez Python zeby nie polamac
# linii 'name = "rustdesk"' w innych miejscach (Cargo.toml moze miec [[bin]] name).
python3 - <<'PYEOF'
import re
with open('Cargo.toml', 'r') as f:
    content = f.read()
# Wymien tylko w [package.metadata.bundle] sekcji
content = re.sub(
    r'(\[package\.metadata\.bundle\][\s\S]*?)name = "RustDesk"',
    r'\1name = "Printsoft Assist"',
    content
)
content = re.sub(
    r'(\[package\.metadata\.bundle\][\s\S]*?)identifier = "com\.carriez\.rustdesk"',
    r'\1identifier = "app.printsoft.assist"',
    content
)
with open('Cargo.toml', 'w') as f:
    f.write(content)
print("   [package.metadata.bundle] patched")
PYEOF

# ─── 6. Flutter pubspec ───
echo "[6/8] Flutter pubspec.yaml"
if [ -f "flutter/pubspec.yaml" ]; then
  sed -i.bak 's|^description: .*|description: Printsoft Assist|' flutter/pubspec.yaml
fi

# ─── 7. Platform-specific window/product names ───
echo "[7/8] Platform branding (Mac/Win/Linux)"

# macOS
if [ -f "flutter/macos/Runner/Configs/AppInfo.xcconfig" ]; then
  sed -i.bak 's|PRODUCT_NAME = RustDesk|PRODUCT_NAME = Printsoft Assist|g' flutter/macos/Runner/Configs/AppInfo.xcconfig
  sed -i.bak 's|com.carriez.flutterHbb|app.printsoft.assist|g' flutter/macos/Runner/Configs/AppInfo.xcconfig
fi

# 0g.14b (10.05.2026): URL scheme + bundle identifier w macOS Info.plist
# Bez tego custom URL scheme (printsoft-assist://) nie dziala
if [ -f "flutter/macos/Runner/Info.plist" ]; then
  sed -i.bak 's|<string>rustdesk</string>|<string>printsoft-assist</string>|g' flutter/macos/Runner/Info.plist
  sed -i.bak 's|<string>com.carriez.rustdesk</string>|<string>app.printsoft.assist</string>|g' flutter/macos/Runner/Info.plist
fi

# 0g.14b: Cargo.toml Windows resource info (FileDescription, OriginalFilename, etc.)
# Te wartosci ladnie sie pojawiaja w Properties pliku .exe na Windowsie
sed -i.bak 's|OriginalFilename = "rustdesk.exe"|OriginalFilename = "printsoft-assist.exe"|g' Cargo.toml
sed -i.bak 's|ProductName = "RustDesk"|ProductName = "Printsoft Assist"|g' Cargo.toml
sed -i.bak 's|FileDescription = "RustDesk Remote Desktop"|FileDescription = "Printsoft Assist - remote support"|g' Cargo.toml
sed -i.bak 's|CompanyName = "Purslane Ltd"|CompanyName = "Print-Soft Maciej Chorzepa"|g' Cargo.toml

# Windows
if [ -f "flutter/windows/runner/Runner.rc" ]; then
  sed -i.bak 's|"RustDesk Remote Desktop"|"Printsoft Assist"|g' flutter/windows/runner/Runner.rc
  sed -i.bak 's|"RustDesk"|"Printsoft Assist"|g' flutter/windows/runner/Runner.rc
fi

# Linux
if [ -f "flutter/linux/CMakeLists.txt" ]; then
  sed -i.bak 's|set(BINARY_NAME "rustdesk")|set(BINARY_NAME "printsoft-assist")|g' flutter/linux/CMakeLists.txt
  sed -i.bak 's|com.carriez.flutter_hbb|app.printsoft.assist|g' flutter/linux/CMakeLists.txt
fi

# ─── 8. Icon assets ───
echo "[8/8] Icon assets (generate from assets/logo.svg)"

if [ -d "$ASSETS_DIR" ] && [ -f "${ASSETS_DIR}/logo.svg" ]; then
  # Generujemy PNG-i z SVG dla wszystkich potrzebnych rozmiarow.
  # Wymaga: rsvg-convert (apt install librsvg2-bin / brew install librsvg)
  # albo ImageMagick (apt install imagemagick / brew install imagemagick).
  TMP_DIR=$(mktemp -d)
  trap "rm -rf $TMP_DIR" EXIT

  generate_png() {
    local size=$1
    local out=$2
    if command -v rsvg-convert &> /dev/null; then
      rsvg-convert -w "$size" -h "$size" "${ASSETS_DIR}/logo.svg" -o "$out"
    elif command -v magick &> /dev/null; then
      magick -background transparent -resize "${size}x${size}" "${ASSETS_DIR}/logo.svg" "$out"
    elif command -v convert &> /dev/null; then
      convert -background transparent -resize "${size}x${size}" "${ASSETS_DIR}/logo.svg" "$out"
    else
      echo "   WARN: brak rsvg-convert / magick / convert. Skip generacji $out (size $size)."
      return 1
    fi
  }

  # res/ icons (uzywane przez Linux + cross-platform)
  if [ -d "res" ]; then
    generate_png 32 res/32x32.png || true
    generate_png 64 res/64x64.png || true
    generate_png 128 res/128x128.png || true
    generate_png 256 res/128x128@2x.png || true
    generate_png 512 res/icon.png || true
    generate_png 1024 res/mac-icon.png || true

    # icon.ico Windows multi-size
    if command -v magick &> /dev/null || command -v convert &> /dev/null; then
      ICON_TOOL=$(command -v magick || command -v convert)
      generate_png 16 "$TMP_DIR/16.png" || true
      generate_png 32 "$TMP_DIR/32.png" || true
      generate_png 48 "$TMP_DIR/48.png" || true
      generate_png 256 "$TMP_DIR/256.png" || true
      $ICON_TOOL "$TMP_DIR/16.png" "$TMP_DIR/32.png" "$TMP_DIR/48.png" "$TMP_DIR/256.png" res/icon.ico 2>/dev/null && echo "   res/icon.ico OK"
      # Windows app_icon.ico
      if [ -f "flutter/windows/runner/resources/app_icon.ico" ]; then
        cp res/icon.ico flutter/windows/runner/resources/app_icon.ico
      fi
    fi
  fi

  # Flutter assets
  if [ -d "flutter/assets" ]; then
    generate_png 512 flutter/assets/logo.png || true
    generate_png 256 flutter/assets/icon.png || true
  fi

  # macOS AppIcon iconset (jesli sips/iconutil dostepny — Mac only)
  if command -v sips &> /dev/null && command -v iconutil &> /dev/null; then
    ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    generate_png 16 "$ICONSET_DIR/icon_16x16.png" || true
    generate_png 32 "$ICONSET_DIR/icon_16x16@2x.png" || true
    generate_png 32 "$ICONSET_DIR/icon_32x32.png" || true
    generate_png 64 "$ICONSET_DIR/icon_32x32@2x.png" || true
    generate_png 128 "$ICONSET_DIR/icon_128x128.png" || true
    generate_png 256 "$ICONSET_DIR/icon_128x128@2x.png" || true
    generate_png 256 "$ICONSET_DIR/icon_256x256.png" || true
    generate_png 512 "$ICONSET_DIR/icon_256x256@2x.png" || true
    generate_png 512 "$ICONSET_DIR/icon_512x512.png" || true
    generate_png 1024 "$ICONSET_DIR/icon_512x512@2x.png" || true
    iconutil -c icns "$ICONSET_DIR" -o "$TMP_DIR/AppIcon.icns" 2>/dev/null && {
      MAC_ICONSET_DIR="flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset"
      if [ -d "$MAC_ICONSET_DIR" ]; then
        cp "$ICONSET_DIR"/*.png "$MAC_ICONSET_DIR/" 2>/dev/null
        echo "   Mac iconset OK"
      fi
    }
  fi
else
  echo "   assets/logo.svg nie istnieje, skip icon generation"
fi

# ─── Cleanup .bak files ───
echo "Cleanup .bak files"
find libs/hbb_common src flutter Cargo.toml -name "*.bak" -delete 2>/dev/null || true

echo ""
echo "=== Branding aplikowany. ==="
echo ""
echo "Sprawdz git diff czy patches sa OK:"
echo "  git diff --stat"
echo ""
echo "Build lokalnie (Mac):"
echo "  python3 build.py --flutter --hwcodec"

# Setup printsoft-assist-client repo (one-time)

Workflow utworzenia osobnego repo dla branded RustDesk client.
Robimy to **raz** — potem CI buduje za każdym razem przy push tagu.

## 1. Utworzenie repo na GitHub

```bash
# Tworzymy publiczne repo (klient pobiera z Releases bez auth)
gh repo create mc-printsoft/printsoft-assist-client \
  --public \
  --description "Branded RustDesk client for Printsoft Suite remote support" \
  --homepage "https://ps.printsoft.app/assist/download"

# Klonuj lokalnie
cd ~/Projekty
gh repo clone mc-printsoft/printsoft-assist-client
cd printsoft-assist-client
```

## 2. Pobierz RustDesk source jako bazę

```bash
# Dodaj upstream RustDesk jako remote
git remote add upstream https://github.com/rustdesk/rustdesk.git
git fetch upstream --tags

# Reset master na konkretna wersje RustDesk (1.4.6 to najnowsza na 08.05.2026)
git reset --hard upstream/1.4.6
git submodule update --init --recursive

# Push do origin (tworzy master z RustDesk source)
git push -u origin master --force
```

## 3. Skopiuj branding files

```bash
# Z printsoft-suite repo
PSUITE=~/Projekty/printsoft-suite

# Branding scripts + assets + patches
mkdir -p scripts assets patches
cp $PSUITE/infra/assist/client/scripts/apply-branding.sh scripts/
cp $PSUITE/infra/assist/client/assets/logo.svg assets/
cp -r $PSUITE/infra/assist/client/patches/* patches/ 2>/dev/null || true

# README + research dokumentacja
cp $PSUITE/infra/assist/client/README.md ./BRANDING.md  # zachowaj RustDesk README
cp $PSUITE/infra/assist/client/RESEARCH.md ./

# GitHub Actions workflow
mkdir -p .github/workflows
cp $PSUITE/infra/assist/client/scripts/github-workflow-template.yml \
   .github/workflows/release.yml

git add scripts/ assets/ BRANDING.md RESEARCH.md .github/
git commit -m "Add Printsoft Assist branding scripts + assets"
git push
```

## 4. Test lokalny (opcjonalny — CI tez sprawdzi)

```bash
# Pre-flight: czy mamy build deps?
brew install librsvg imagemagick  # Mac

# Aplikuj branding patches
bash scripts/apply-branding.sh

# Sprawdz git diff
git diff --stat

# Build (tylko Mac, dla testu)
python3 build.py --flutter --hwcodec
# Output: flutter/build/macos/Build/Products/Release/Printsoft Assist.app
# Test: otworz aplikacje, w UI powinno byc "Printsoft Assist"
#       w Network settings powinno byc juz wpisane assist.printsoft.app

# REWERT branding (przed commit)
git checkout -- libs/ src/ Cargo.toml flutter/
```

## 5. Pierwszy release

```bash
# Tag i push -> trigger workflow .github/workflows/release.yml
git tag assist-1.4.6
git push origin assist-1.4.6

# Obserwuj
gh run watch -R mc-printsoft/printsoft-assist-client

# Po ~25-40 min: GitHub Release z artefaktami:
# - printsoft-assist-1.4.6.dmg (Mac arm64 + x64)
# - printsoft-assist-1.4.6.exe (Windows portable)
# - printsoft-assist-1.4.6.deb (Linux)
```

## 6. Post-release w Suite

```bash
# Dodaj VITE_ASSIST_VERSION do GitHub Secrets (dla SWA build w printsoft-suite)
gh secret set VITE_ASSIST_VERSION -R mc-printsoft/printsoft-suite -b "1.4.6"

# Backend env vars (Azure App Service psbackup-api)
az webapp config appsettings set \
  --resource-group psbackup-prod \
  --name psbackup-api \
  --settings \
    ASSIST_LATEST_VERSION="1.4.6" \
    ASSIST_DOWNLOAD_BASE_URL="https://github.com/mc-printsoft/printsoft-assist-client/releases/download/assist-1.4.6"

# Frontend redeploy zeby /assist/download wskazywalo na 1.4.6
gh workflow run "Azure Static Web Apps CI/CD" -R mc-printsoft/printsoft-suite
```

## 7. Maintenance — nowy RustDesk release

Gdy RustDesk wyda 1.4.7:
```bash
cd ~/Projekty/printsoft-assist-client
git fetch upstream --tags
git checkout master
git reset --hard upstream/1.4.7
git submodule update --recursive

# Re-apply patches (sed jest tolerant na drift)
bash scripts/apply-branding.sh
git add -A
git commit -m "Rebase on RustDesk 1.4.7"
git tag assist-1.4.7
git push origin master --force-with-lease
git push origin assist-1.4.7

# Update Suite env vars (Azure + GitHub Secret)
# (jak krok 6 ale z 1.4.7)
```

Budget: ~30 min per RustDesk release.

## Troubleshooting

### Build fails: vcpkg dependencies
RustDesk wymaga libvpx, libyuv, opus, aom (codecs wideo). CI workflow installuje przez vcpkg (cached).
Lokalnie: `brew install vcpkg && vcpkg install libvpx libyuv opus aom`.

### "Niezweryfikowany wydawca" przy pierwszym uruchomieniu na Windows
To normalne dla niesignowanych binarek. **D3 decyzja Macieja**: code-signing dorzucamy w v1.0 (DigiCert ~$300/yr lub Sectigo ~$100/yr).

Workaround dla testow: klient klika "Wiecej informacji" -> "Uruchom mimo to".

### macOS Gatekeeper blokuje
Klient prawym-klikiem -> "Otwórz" (dwa razy). Albo:
```bash
xattr -dr com.apple.quarantine "/Applications/Printsoft Assist.app"
```

### Auto-update nie dziala
Sprawdz:
- Backend `ASSIST_LATEST_VERSION` env var ustawiona
- Backend `ASSIST_DOWNLOAD_BASE_URL` wskazuje na faktyczne Release
- `is_custom_client()` guard removed w `src/common.rs` (apply-branding.sh)

# Printsoft Assist client (branded RustDesk fork)

Client builder dla **Printsoft Assist** - branded RustDesk z zaszytymi:
- `RENDEZVOUS_SERVER`: `assist.printsoft.app`
- `RS_PUB_KEY`: `iIaqYsmm0eIZOo9xVs1ONg5X1NEBgWrAmWhHEivW9ow=`
- `UPDATE_URL`: `https://ps.printsoft.app/api/assist/agent/version`
- `APP_NAME`: `Printsoft Assist`
- Logo "P" (placeholder, do podmiany)

## Architektura

```
RustDesk upstream (github.com/rustdesk/rustdesk)  v1.4.6
                       |
                       | git clone @ release tag
                       v
mc-printsoft/printsoft-assist-client  (osobne repo)
                       |
                       | apply patches/*.patch + cp assets/*
                       v
              build (Mac arm64+x64, Win, Linux)
                       |
                       v
GitHub Releases printsoft-assist-1.4.6-{mac,win,linux}.{dmg,exe,deb}
                       |
                       v
                Klient pobiera + instaluje
                       |
                       v
            Auto-update: pings ps.printsoft.app/api/assist/agent/version
```

## Workflow tworzenia nowego release

```bash
# 1. Clone fork repo (jednorazowo)
gh repo clone mc-printsoft/printsoft-assist-client
cd printsoft-assist-client

# 2. Update upstream do najnowszej wersji RustDesk
git remote add upstream https://github.com/rustdesk/rustdesk.git
git fetch upstream --tags
git checkout 1.4.6  # albo nowsza

# 3. Aplikuj patches (z infra/assist/client/patches/)
bash scripts/apply-branding.sh

# 4. Build lokalnie (test)
python3 build.py --flutter --hwcodec   # Mac
# Output: ./flutter/build/macos/Build/Products/Release/Printsoft Assist.app

# 5. Tag + push -> CI buduje Mac/Win/Linux
git tag assist-1.4.6
git push origin assist-1.4.6
```

## Pliki w tym folderze

- `patches/` - patches do RustDesk source (sed-friendly format)
- `assets/` - logo, ikony, nazwy aplikacji
- `scripts/apply-branding.sh` - master script aplikujacy wszystko
- `assets/README-icons.md` - jak generowac platform-specific icony

## Maintenance

Kazdy nowy RustDesk release (np. 1.4.7, 1.5.0):
- `git fetch upstream && git rebase v1.4.7`
- ~30 min: 5-10 hunks konfliktow, zwykle w `lang/en.rs`
- Patches w `patches/` mogą wymagac update line numbers (sed jest tolerant
  na drift, ale weryfikujemy po update)

## Reference

Research strategie i dokladne file paths: `infra/assist/client/RESEARCH.md`

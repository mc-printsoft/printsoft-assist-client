# RustDesk fork — research findings (08.05.2026)

Detaliczny raport z analizy RustDesk 1.4.6 source code dla branding strategy.

## Critical finding

**RustDesk NIE wspiera env vars dla branding przy build time.** Sprawdzono `build.py`, top-level `build.rs`, `src/common.rs`, `src/custom_server.rs`, `libs/hbb_common/src/config.rs` — zero `option_env!`/`env!` dla branding constants.

Dwie oficjalne metody customizacji:
1. **Filename trick** (`src/custom_server.rs:39`) — rename binary do `RustDesk-host=...,key=...,api=...`. Limited, nie rebrand.
2. **Signed custom config** (`src/common.rs:2184 read_custom_client`) — wymaga RustDesk Ed25519 privkey (pubkey `5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=`). **Nie dla nas** (paid licence).

**Wniosek**: musimy patchowac source. Method 2 z research = **fork-with-patches** (recommended).

## Critical patches (RustDesk 1.4.6)

### 1. Default rendezvous + pubkey

`libs/hbb_common/src/config.rs:159-160`:
```rust
pub const RENDEZVOUS_SERVERS: &[&str] = &[
    "rs-ny.rustdesk.com",     // -> "assist.printsoft.app"
];
pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";
                                                          // -> nasz key
```

### 2. APP_NAME

`libs/hbb_common/src/config.rs:111`:
```rust
pub static APP_NAME: Lazy<RwLock<String>> = Lazy::new(|| RwLock::new("RustDesk".to_owned()));
                                                                      // -> "Printsoft Assist"
```

### 3. Update endpoint

`libs/hbb_common/src/lib.rs:496`:
```rust
pub fn version_check_request(typ: String) -> (VersionCheckRequest, String) {
    const URL: &str = "https://api.rustdesk.com/version/latest";
                       // -> "https://ps.printsoft.app/api/assist/agent/version"
```

Backend response format wymagany:
```json
{ "url": "https://...../printsoft-assist-1.4.7.dmg" }
```
RustDesk parsuje wersje z **ostatniego segmentu URL** (`response_url.rsplit('/').next()`).

### 4. is_custom_client() guard removal

`src/common.rs ~line 1010` w `check_software_update()`:
```rust
fn check_software_update() {
    if is_custom_client() {  // true dla rebranded -> early return
        return;
    }
    // ... reszta update flow
}
```

`is_custom_client()` zwraca true gdy `APP_NAME != "RustDesk"`. Po naszym rebrandzie jest true → update flow disabled. **Trzeba usunąć ten guard** żeby update działał (auto-zaaplikowany przez Python regex w apply-branding.sh).

### 5. Cargo.toml + Flutter pubspec

```toml
# Cargo.toml
name = "rustdesk"        -> "printsoft-assist"
description = "..."      -> "Printsoft Assist - remote support tool"
```

```yaml
# flutter/pubspec.yaml
description: ...         -> Printsoft Assist
```

### 6. Platform branding

**macOS** (`flutter/macos/Runner/Configs/AppInfo.xcconfig`):
```
PRODUCT_NAME = RustDesk        -> Printsoft Assist
PRODUCT_BUNDLE_IDENTIFIER = com.carriez.flutterHbb -> app.printsoft.assist
```

**Windows** (`flutter/windows/runner/Runner.rc`):
```
"RustDesk Remote Desktop"  -> "Printsoft Assist"
"RustDesk"                 -> "Printsoft Assist"
```

**Linux** (`flutter/linux/CMakeLists.txt`):
```cmake
set(BINARY_NAME "rustdesk")              -> "printsoft-assist"
com.carriez.flutter_hbb                  -> app.printsoft.assist
```

### 7. UI strings (en.rs)

`src/lang/en.rs` ma ~50 wystapien "RustDesk" w stringach UI. Bulk replace OK,
manual review po update bo niektore są w error messages ("RustDesk service is not running")
gdzie literalna nazwa moze pomoc support team.

## Icon assets do replace

| Plik | Rozmiar | Source | Dla |
|---|---|---|---|
| `res/icon.ico` | multi (16, 32, 48, 256) | logo.svg | Windows tray + .exe icon |
| `res/icon.png` | 512x512 | logo.svg | Linux app icon |
| `res/32x32.png`, `64x64.png`, `128x128.png`, `128x128@2x.png` | per name | logo.svg | Linux desktop entry |
| `res/mac-icon.png` | 1024x1024 | logo.svg | macOS source dla .icns |
| `flutter/assets/logo.png`, `flutter/assets/icon.png` | 512x512, 256x256 | logo.svg | Flutter UI assets |
| `flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | iconset (16-1024) | logo.svg | macOS bundle .icns |
| `flutter/windows/runner/resources/app_icon.ico` | multi | logo.svg | Windows .exe metadata |

Wszystko generowane z `assets/logo.svg` przez `apply-branding.sh` (rsvg-convert + ImageMagick).

## Mac iconset (special)

macOS używa `.icns` zamiast PNG. Generowanie:
```bash
mkdir AppIcon.iconset
# generate sizes 16, 16@2x (32), 32, 32@2x (64), 128, 128@2x (256), 256, 256@2x (512), 512, 512@2x (1024)
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

`apply-branding.sh` wykonuje to automatycznie jeśli mac (`sips` + `iconutil` dostępne).

## Cargo.lock i submoduly

RustDesk uzywa `libs/hbb_common` jako submodule. `git submodule update --init --recursive` wymagane przy clone.

`Cargo.lock` w repo jest commitowany — po aplikacji patches **nie regenerujemy** Cargo.lock żeby nie pull dependencies upgrades (deterministic builds).

## Maintenance: nowy RustDesk release

1. `git fetch upstream && git checkout v1.4.7` (przykład)
2. `bash scripts/apply-branding.sh` (sed-y są tolerant na drift)
3. `git diff` — sprawdz konflikty (zwykle 5-10 hunks w `lang/en.rs`)
4. Jesli `is_custom_client` guard zmienil sie — Python regex w apply-branding.sh moze nie zlapac, manual fix
5. Lokalny build test: `python3 build.py --flutter --hwcodec`
6. `git tag assist-1.4.7 && git push origin assist-1.4.7` -> CI buduje wszystko

**Budget**: ~30 min per upstream release.

## Reference

- RustDesk source: https://github.com/rustdesk/rustdesk/tree/1.4.6
- Build doc: https://rustdesk.com/docs/en/dev/build/
- Self-host doc: https://rustdesk.com/docs/en/self-host/
- Custom client doc (signed only): https://rustdesk.com/docs/en/self-host/client-configuration/

## Dlaczego nie używamy `--bundle-id` / `--app-name` flags w build.py?

Sprawdzono: `build.py` accepts only `--feature`, `--flutter`, `--hwcodec`, `--vram`, `--portable`, `--unix-file-copy-paste`, `--skip-cargo`, `--skip-portable-pack`, `--package`, `--screencapturekit`. **Brak branding flags.** Jedyna opcja to source-level patches.

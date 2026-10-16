# Cork → CrossOver parity roadmap

Legend: ✅ done · 🟡 in progress · ⬜ planned

Data policy: Cork **never bundles or redistributes CodeWeavers data**. `crossover.tie`,
`compatdb-*.dat`, and `cxfixes.xml` are read only when the *user* supplies them or
they already exist on their machine (see `CrossOverData`).

## Phase 0 — Foundations ✅
- `CorkEngine` target + frozen API (`RecipeApp`, `AppCatalog`, `CrossTieCatalog`,
  `CompatDatabase`, `CrossOverData`).
- `cork-app` SwiftUI target + `cork` CLI.
- `docs/` architecture + this roadmap.

## Phase 1 — Recipe catalog (engine) ✅
- Streaming parser for `crossover.tie` (5,235 `<app>` records → 4,402 unique ids).
- `<appprofile>` / `<installprofile>` extraction: names, summary, medals, category,
  bottletemplate, predependency, associations, installer flags.
- `cork app search` / `cork app show` / `cork app recipe` against a user-supplied catalog.

## Phase 2 — Compatibility database ✅ (best-effort)
- `cork app rating <appid>` resolves a rating/medal, preferring a user-supplied
  `compatdb-*.dat` and falling back to the recipe medal.
- **Honest limitation:** `compatdb-26.dat` is an undocumented, signed/obfuscated
  container (structure at a 78-byte stride but not decodable without CodeWeavers'
  key). The parser returns an empty map and Cork relies on recipe medals.

## Phase 3 — Install engine ✅
- Recipe model for install steps: `<downloadurl>`/`<downloadurl64>`,
  `<installerwinver>`, `<installerdlloverrides>`, `<installersilentoption>`,
  `<filestocopy>`, `<preinstallregistry>`, `<lnkfile>`/shortcut, `<postinstallreboot>`,
  environment and `<predependency>`.
- **Full `<installerid>` chain resolution** (recursive, deduped, cycle-protected,
  dependencies ordered first).
- **CD-based installers** are modelled explicitly: when the main setup can be derived
  (e.g. `setup.exe`) a real `.runInstaller` step is emitted; otherwise an explicit
  "installation media required" step is produced instead of a silent no-op.
- `cork install <bottle> <appid>` executes a recipe against a bottle, streaming events.

## Phase 4 — Dependencies ✅
- Built-in, Cork-authored component catalog (14): `vcrun6/2015/2017/2019/2022`,
  `dotnet48`, `d3dx9`, `d3dx11`, `xact`, `directplay`, `msxml6`, `riched20`,
  `corefonts`, `gdiplus`.
- `cork deps list [--category]` and `cork deps install <bottle> <component>`.
- Components that cannot be automated (nested cab extraction, per-font archives)
  are marked **manual** and emit a warning rather than pretending to succeed.

## Phase 5 — macOS app bundling ✅
- `cork bundle <bottle> <exe> [--name --to --icon]` produces a self-contained `.app`
  (Info.plist, PkgInfo, bash launcher, `launch.json`, optional `.icns`) that resolves
  `cork`/Wine at launch time.
- Bottle file associations are applied to the generated bundle's
  `CFBundleDocumentTypes`/`UTExportedTypeDeclarations`.

## Phase 6 — GUI ✅
- SwiftUI: bottle manager (create / configure / run / logs), catalog browser with
  search, **install wizard** with a live event log, **drive_c file browser**, program
  launch, and **macOS app bundling**.
- Management views: **dependencies**, **diagnostics**, **file associations**.

## Phase 7 — Integration ✅
- File associations (`cxassoc.conf` equivalent): Cork-owned JSON per bottle +
  best-effort Wine-registry application; `cork assoc list/set/remove`.
- Diagnostics (`cxdiag` equivalent): `cork doctor [--bottle]` checks host, runtime and
  bottle; imports a user-supplied `cxfixes.xml` (268 fix entries) when present.
- Multiple Wine versions: manifest supports several Wine components; bottles are
  pinned to their recorded version; `cork runtime wine list/install/select/clear`.

## Known limitations
- CodeWeavers' patched Wine is proprietary and is not reconstructable; Cork uses
  Wine + DXMT/DXVK.
- `compatdb-*.dat` is not decodable without the vendor key (Phase 2 fallback in use).
- CD/DVD-based installers that the catalog does not name are surfaced as a manual
  step; Cork cannot guess an unnamed setup executable.
- Several dependency components require cabinet extraction or per-package download
  and are marked manual.
- A `.lk`/`.lnk` shortcut falls back to a minimal Shell Link when `cscript` is
  unavailable.

## Verify
```sh
swift build
swift run cork doctor
swift run cork app search word --catalog "<your crossover.tie>"
swift run cork deps list
.build/debug/cork-tests
```

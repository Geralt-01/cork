# Cork → CrossOver parity roadmap

Legend: ✅ done · 🟡 in progress · ⬜ planned

## Phase 0 — Foundations ✅
- `CorkEngine` target + frozen API (`RecipeApp`, `AppCatalog`, `CrossTieCatalog`,
  `CompatDatabase`, `CrossOverData`).
- `cork-app` SwiftUI target + `cork app` CLI command.
- `docs/` architecture + this roadmap.

## Phase 1 — Recipe catalog (engine) 🟡
- Streaming parser for `crossover.tie` (5,235 `<app>` records) → `RecipeApp`.
- `<appprofile>` / `<installprofile>` extraction: names, description, medals,
  category, `bottletemplate`, `predependency`, associations, installer flags.
- `cork app search` / `cork app show` against a user-supplied catalog.
- Tests on the real `crossover.tie`.

## Phase 2 — Compatibility database ⬜
- Best-effort reader for `compatdb-*.dat`; medal/rating lookup with graceful
  fallback to recipe medals.

## Phase 3 — Install engine ⬜
- Recipe model for install steps (`<downloadurl>`, `<installerwinver>`,
  `<installerdlloverrides>`, `<installersilentoption>`, `<filestocopy>`,
  `<preinstallregistry>`, `<lnkfile>/<shortcut>`, `<postinstallreboot>`).
- Predependency resolution + orchestration into a Cork bottle.

## Phase 4 — Dependencies ⬜
- winetricks-style components (vcrun, dotnet, d3dx, …) with pre/post registry.

## Phase 5 — macOS app bundling ⬜
- Wrap an installed Windows app into a `.app` (Info.plist, icon, launcher),
  Finder/Dock integration.

## Phase 6 — GUI ⬜
- SwiftUI: bottle manager (create/configure/run/logs), catalog browser,
  install wizard, settings, per-bottle graphics backend.

## Phase 7 — Integration ⬜
- File associations (`cxassoc.conf`, `<defaulteassoc>`).
- Diagnostics (`cxdiagcheck`) and `cxfixes.xml` import.
- Multi-Wine-version support.

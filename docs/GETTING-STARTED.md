# Getting started with Cork

A step-by-step guide to installing, running, and using Cork to run Windows
applications and games on macOS.

> Cork is a free, open-source Wine front-end. It never bundles or redistributes
> CodeWeavers (CrossOver) data; the recipe catalog and compatibility database are
> read from a CrossOver install **you** already have on your Mac.

---

## 0. One-time build

```sh
cd ~/cork
swift build -c release      # CLI  → .build/release/cork
swift build                 # GUI  → .build/debug/cork-app
```

Put `.build/release` on your `PATH` (or use the full path to the binary). All
commands below assume `cork` resolves on your `PATH`.

## 1. Health check

```sh
cork doctor                 # Mac, Wine runtime, graphics components, CrossOver fixes
cork runtime status         # which Wine / DXMT / DXVK components are installed
```

Expected, roughly:

```
✓ CPU architecture — arm64
✓ Rosetta 2 — available
✓ Wine runtime — wine-11.18
✓ Runtime component dxmt (0.80) — ok
✓ Runtime component dxvk (1.10.3) — ok
```

If the runtime is missing, install it once:

```sh
cork runtime install
```

## 2. Create a bottle

A *bottle* is an isolated Windows environment (a Wine prefix).

```sh
cork bottle create myapps --backend dxmt --windows win10
cork bottle list
cork bottle info myapps
```

- `--backend` (default `dxmt`):
  - `dxmt` — Direct3D → Metal (best on Apple Silicon)
  - `dxvk` — Direct3D → Vulkan → Metal
  - `wined3d` — Wine's own Direct3D → OpenGL (most compatible, slowest)
- `--windows`: `win10` (default), `win7`, `win8`, `win81`, `winxp`, `win2000`,
  `win98`, `win95`, `winvista`, `nt40`, …

## 3. Find and inspect an app in the catalog

The catalog is read from your CrossOver data automatically.

```sh
cork app search 7-zip
cork app show   com.codeweavers.c4.8843
cork app recipe com.codeweavers.c4.8843     # the ordered install steps
cork app rating com.codeweavers.c4.8843     # compatibility medal / rating
```

Override the catalog with `--catalog /path/to/crossover.tie`.

## 4. Install an app into a bottle

```sh
cork install myapps com.codeweavers.c4.8843 --yes
```

Cork downloads the installer, applies the recipe's reported Windows version, and
runs it.

> **Interactive installers.** If a recipe has no silent switch (7-Zip is one),
> the vendor's installer window opens and **you click through it**, exactly as
> CrossOver does. Cork waits for it to finish.

For a fully automatic install, use a dependency component instead:

```sh
cork deps install myapps vcrun2015
```

## 5. Run Windows programs

```sh
# Run a Windows executable (C:\ path or unix path):
cork run myapps "C:\Program Files\7-Zip\7zFM.exe"

# Launch and return immediately:
cork run myapps "C:\Program Files\Notepad++\notepad++.exe" --detach

# Wine built-ins and commands:
cork exec myapps notepad
cork exec myapps cmd /c "echo hello"
cork exec myapps winecfg
cork exec myapps reg query "HKCU\Software\Wine"

# Stop everything running in a bottle:
cork bottle kill myapps
```

## 6. Dependencies (vcrun, DirectX, .NET, fonts…)

```sh
cork deps list                 # 14 components
cork deps list --category      # filter by category
cork deps install myapps vcrun2022
cork deps install myapps d3dx9
```

Available components: `vcrun6`, `vcrun2015`, `vcrun2017`, `vcrun2019`,
`vcrun2022`, `dotnet48`, `d3dx9`, `d3dx11`, `xact`, `directplay`, `msxml6`,
`riched20`, `corefonts`, `gdiplus`. Components that need a cabinet or per-font
step are marked **manual** and warn instead of pretending to succeed.

## 7. Turn a Windows app into a double-clickable macOS app

```sh
cork bundle myapps "C:\Program Files\7-Zip\7zFM.exe" --name "7-Zip" --to ~/Applications
open ~/Applications/7-Zip.app
```

The generated `.app` is self-contained and delegates to `cork run` at launch. It
finds `cork` on your `PATH` (or set `CORK_BIN=/path/to/cork`). Set file
associations **before** bundling to embed them.

## 8. File associations

```sh
cork assoc list myapps
cork assoc set  myapps .zip "C:\Program Files\7-Zip\7zFM.exe" --name "7-Zip Archive"
cork assoc remove myapps .zip
```

## 9. Diagnostics & logs

```sh
cork doctor                    # the whole Mac
cork doctor --bottle myapps    # include bottle checks
cork bottle logs myapps        # most recent Wine log
cork bottle logs myapps --path-only
```

## 10. Change settings and manage Wine versions

```sh
cork bottle set myapps backend=dxmt windows=win10 msync=true metal-hud=on

cork runtime wine list                 # installed / available Wine versions
cork runtime wine install <version>
cork runtime wine select <version>     # set the global default
cork runtime wine clear                # fall back to the manifest default
```

## 11. The graphical app

```sh
swift run cork-app        # or:  .build/debug/cork-app
```

- **Bottles** (sidebar): create / inspect / delete bottles, launch programs,
  browse the `drive_c` file tree, view logs.
- **Applications**: search the catalog; the **install wizard** shows a live log.
- **⌘4 Dependencies**, **⌘5 Diagnostics**, and a per-bottle **associations**
  section.

## 12. Clean up

```sh
cork bottle delete myapps --yes
```

---

## Copy-paste end-to-end example

```sh
cork doctor
cork bottle create myapps --backend dxmt --windows win10
cork app recipe com.codeweavers.c4.8843
cork install myapps com.codeweavers.c4.8843 --yes   # click through the installer
cork run myapps "C:\Program Files\7-Zip\7zFM.exe"
cork bundle myapps "C:\Program Files\7-Zip\7zFM.exe" --name "7-Zip" --to ~/Applications
open ~/Applications/7-Zip.app
cork bottle kill myapps
```

---

## Good to know

- **Where things live:** `~/Library/Application Support/Cork`
  - `Runtimes/` — Wine, DXMT, DXVK
  - `Bottles/<name>/` — the prefix (`drive_c`, `system.reg`, …, plus `cork/metadata.json`)
  - Set `CORK_HOME` to relocate everything.
- **Catalog & compatibility data** come from a CrossOver install you supply; Cork
  never bundles them.
- **Interactive installers** open their own window and wait for you, the same as
  CrossOver.
- **Dead download URLs.** Some recipe download URLs are controlled by the vendor
  and may rot; Cork reports the failure rather than faking success.
- **Anti-cheat games cannot run** under Wine on macOS (Easy Anti-Cheat, BattlEye,
  Vanguard); Cork says so instead of hanging.
- **`compatdb-*.dat`** is signed/obfuscated and cannot be decoded without
  CodeWeavers' key, so `cork app rating` falls back to the recipe medal.

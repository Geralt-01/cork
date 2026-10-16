import CorkKit
import Foundation

/// Cork's built-in dependency catalog.
///
/// This is authored entirely by Cork — no third-party catalog or manifest is
/// bundled. The recipes mirror the well-known winetricks verbs, but the URLs are
/// limited to official/stable Microsoft or Microsoft-redistributable locations,
/// and the download file names are namespaced per component so the per-bottle
/// cache never collides.
///
/// Components whose payload can only be unpacked with a cabinet extractor
/// (which Cork does not bundle) are marked ``DependencyStep/manual(_:)`` and
/// surface a warning at install time rather than pretending to succeed.
public enum DependencyCatalog {
    /// Every built-in component, sorted by id.
    public static let all: [DependencyDefinition] = buildAll()

    /// Look up a definition by id, case-insensitively.
    public static func definition(id: String) -> DependencyDefinition? {
        let needle = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return all.first { $0.component.id.lowercased() == needle }
    }

    /// The distinct categories present in the catalog, sorted.
    public static func categories() -> [String] {
        Array(Set(all.map(\.component.category))).sorted()
    }

    // MARK: - URLs

    /// Visual C++ 2015 Update 3 redistributable (fixed Microsoft URL).
    private static let vcrun2015x86 =
        "https://download.microsoft.com/download/6/D/F/6DF3FF94-F7F9-4F0B-838C-A328D1A7D0EE/vc_redist.x86.exe"
    private static let vcrun2015x64 =
        "https://download.microsoft.com/download/6/D/F/6DF3FF94-F7F9-4F0B-838C-A328D1A7D0EE/vc_redist.x64.exe"
    /// Visual C++ 2017/2019/2022 share the evergreen 2015-2022 redistributable,
    /// served from the versioned `aka.ms` channels.
    private static let vcrun2017x86 = "https://aka.ms/vs/15/release/vc_redist.x86.exe"
    private static let vcrun2017x64 = "https://aka.ms/vs/15/release/vc_redist.x64.exe"
    private static let vcrun2019x86 = "https://aka.ms/vs/16/release/vc_redist.x86.exe"
    private static let vcrun2019x64 = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
    private static let vcrun2022x86 = "https://aka.ms/vs/17/release/vc_redist.x86.exe"
    private static let vcrun2022x64 = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

    private static let dotnet48URL =
        "https://download.visualstudio.microsoft.com/download/pr/"
        + "7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/"
        + "ndp48-x86-x64-allos-enu.exe"
    private static let dotnet48FileName = "ndp48-x86-x64-allos-enu.exe"

    private static let directXJun2010 =
        "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe"
    private static let directXJun2010FileName = "directx_Jun2010_redist.exe"
    private static let directXFeb2010 =
        "https://web.archive.org/web/20100205000000id_/https://download.microsoft.com/download/"
        + "E/E/1/EE17FF74-6C45-4575-9CF4-7FC2597ACD18/directx_feb2010_redist.exe"
    private static let directXFeb2010FileName = "directx_feb2010_redist.exe"

    private static let msxml6URL =
        "https://download.microsoft.com/download/2/7/7/277681BE-4048-4A58-ABBA-259C465B1699/msxml6-KB2957482-enu-amd64.exe"
    private static let msxml6FileName = "msxml6-KB2957482-enu-amd64.exe"

    // MARK: - Builders

    /// Wine stores per-prefix DLL overrides under this key; `w_override_dlls`
    /// in winetricks writes to the same place.
    private static let dllOverridesKey = #"HKCU\Software\Wine\DllOverrides"#

    private static func override(_ name: String, _ value: String = "native") -> DependencyStep {
        .registry(key: dllOverridesKey, name: name, data: value)
    }

    private static func make(
        id: String,
        name: String,
        summary: String,
        category: String,
        steps: [DependencyStep],
        windowsVersions: [WindowsVersion] = [],
        requiresReboot: Bool = false,
        notes: [String] = []
    ) -> DependencyDefinition {
        var verbs: [String] = []
        for step in steps where !verbs.contains(step.verb) {
            verbs.append(step.verb)
        }
        let component = DependencyComponent(
            id: id,
            name: name,
            summary: summary,
            category: category,
            verbs: verbs,
            windowsVersions: windowsVersions.map(\.rawValue),
            requiresDownload: steps.contains(where: \.isDownload)
        )
        return DependencyDefinition(
            component: component,
            steps: steps,
            requiresReboot: requiresReboot,
            notes: notes
        )
    }

    /// A Visual C++ redistributable: download the x86 and x64 `vc_redist`
    /// payloads and run each quietly.
    private static func vcrun(
        id: String,
        name: String,
        summary: String,
        x86: String,
        x64: String
    ) -> DependencyDefinition {
        make(
            id: id,
            name: name,
            summary: summary,
            category: "Runtimes",
            steps: [
                .download(url: x86, fileName: "\(id)-vc_redist.x86.exe"),
                .runInstaller(command: "\(id)-vc_redist.x86.exe", arguments: ["/q", "/norestart"]),
                .download(url: x64, fileName: "\(id)-vc_redist.x64.exe"),
                .runInstaller(command: "\(id)-vc_redist.x64.exe", arguments: ["/q", "/norestart"]),
            ],
            windowsVersions: [.win7, .win8, .win81, .win10],
            notes: [
                "installs both the 32-bit and 64-bit runtimes; the 64-bit installer "
                + "fails harmlessly on a 32-bit-only prefix"
            ]
        )
    }

    /// A DirectX 9c component: extract the redistributable into the prefix and
    /// run its bundled `DXSETUP.exe` silently, then apply DLL overrides.
    private static func directX(
        id: String,
        name: String,
        summary: String,
        redistURL: String,
        redistFileName: String,
        overrides: [String],
        notes: [String]
    ) -> DependencyDefinition {
        make(
            id: id,
            name: name,
            summary: summary,
            category: "DirectX",
            steps: directXSteps(
                id: id,
                redistURL: redistURL,
                redistFileName: redistFileName,
                overrides: overrides
            ),
            notes: notes
        )
    }

    private static func manual(
        id: String,
        name: String,
        summary: String,
        category: String,
        reason: String
    ) -> DependencyDefinition {
        make(
            id: id,
            name: name,
            summary: summary,
            category: category,
            steps: [.manual(reason)]
        )
    }

    // MARK: - The catalog

    private static func buildAll() -> [DependencyDefinition] {
        let entries: [DependencyDefinition] = [
            vcrun(
                id: "vcrun2015",
                name: "Visual C++ 2015 Redistributable",
                summary: "Microsoft Visual C++ 2015 (VC14) runtime, both x86 and x64.",
                x86: vcrun2015x86,
                x64: vcrun2015x64
            ),
            vcrun(
                id: "vcrun2017",
                name: "Visual C++ 2017 Redistributable",
                summary: "Microsoft Visual C++ 2017 (VC15) runtime via the 2015-2022 redist.",
                x86: vcrun2017x86,
                x64: vcrun2017x64
            ),
            vcrun(
                id: "vcrun2019",
                name: "Visual C++ 2019 Redistributable",
                summary: "Microsoft Visual C++ 2019 (VC16) runtime via the 2015-2022 redist.",
                x86: vcrun2019x86,
                x64: vcrun2019x64
            ),
            vcrun(
                id: "vcrun2022",
                name: "Visual C++ 2022 Redistributable",
                summary: "Microsoft Visual C++ 2022 (VC17) runtime via the 2015-2022 redist.",
                x86: vcrun2022x86,
                x64: vcrun2022x64
            ),

            make(
                id: "dotnet48",
                name: "Microsoft .NET Framework 4.8",
                summary: "Microsoft .NET Framework 4.8 offline installer (ndp48, ~110 MB); "
                    + "best-effort, requires an existing .NET 4.x runtime and a reboot.",
                category: "Runtimes",
                steps: [
                    .setWindowsVersion("win7"),
                    .download(url: dotnet48URL, fileName: dotnet48FileName),
                    .runInstaller(
                        command: dotnet48FileName,
                        arguments: ["/sfxlang:1027", "/q", "/norestart"]
                    ),
                    override("mscoree"),
                ],
                windowsVersions: [.win7],
                requiresReboot: true,
                notes: [
                    "requires an existing .NET Framework 4.x runtime; on a bare prefix "
                    + "the installer may refuse to run",
                    "restart the bottle afterwards; WPF apps may also need LC_ALL=C",
                    "winetricks sets fusion=b for the installer process only, which Cork "
                    + "cannot do through BottleManager"
                ]
            ),

            directX(
                id: "d3dx9",
                name: "DirectX 9 d3dx9 libraries",
                summary: "DirectX 9c (June 2010) d3dx9_24…d3dx9_43 helper DLLs, extracted "
                    + "from the DirectX 9c redistributable (~96 MB).",
                redistURL: directXJun2010,
                redistFileName: directXJun2010FileName,
                overrides: (24...43).map { "d3dx9_\($0)" },
                notes: [
                    "runs the DirectX 9c redistributable's DXSETUP, which installs the "
                    + "whole DirectX 9 runtime (a superset of d3dx9)"
                ]
            ),
            directX(
                id: "d3dx11",
                name: "DirectX 11 d3dx11 libraries",
                summary: "DirectX SDK d3dx11_42/d3dx11_43 helper DLLs, extracted from the "
                    + "DirectX 9c redistributable (~96 MB).",
                redistURL: directXJun2010,
                redistFileName: directXJun2010FileName,
                overrides: ["d3dx11_42", "d3dx11_43"],
                notes: [
                    "runs the DirectX 9c redistributable's DXSETUP, which installs the "
                    + "whole DirectX 9 runtime (a superset of d3dx11)"
                ]
            ),
            make(
                id: "xact",
                name: "Microsoft XACT Engine",
                summary: "XACT/XAudio2/X3DAudio/xapofx DLLs (32-bit) from the DirectX 9c "
                    + "redistributable (~96 MB).",
                category: "DirectX",
                steps: directXSteps(
                    id: "xact",
                    redistURL: directXJun2010,
                    redistFileName: directXJun2010FileName,
                    overrides: xactOverrides
                ),
                notes: [
                    "32-bit DLLs only; the 64-bit XACT DLLs are broken in Wine and are "
                    + "deliberately not installed",
                    "runs the DirectX 9c redistributable's DXSETUP, which installs the "
                    + "whole DirectX 9 runtime (a superset of XACT)"
                ]
            ),
            directX(
                id: "directplay",
                name: "Microsoft DirectPlay",
                summary: "DirectPlay network/multiplayer DLLs from the DirectX 9 "
                    + "(February 2010) redistributable (~48 MB).",
                redistURL: directXFeb2010,
                redistFileName: directXFeb2010FileName,
                overrides: ["dplayx", "dpnet", "dpnhpast", "dpnhupnp", "dpmodemx", "dpwsockx"],
                notes: [
                    "DXSETUP installs the DirectX runtime, but DirectPlay registration can "
                    + "fail; if a game still reports a missing dplayx.dll, register it with "
                    + "'wine regsvr32 dplayx.dll' inside the bottle"
                ]
            ),

            make(
                id: "msxml6",
                name: "Microsoft XML Core Services 6.0 (SP2)",
                summary: "MSXML 6.0 SP2 (msxml6.dll/msxml6r.dll) from Microsoft update "
                    + "KB2957482 (~1.7 MB); Cork runs the hotfix directly instead of "
                    + "unpacking it.",
                category: "Libraries",
                steps: [
                    .download(url: msxml6URL, fileName: msxml6FileName),
                    .runInstaller(command: msxml6FileName, arguments: ["/quiet", "/norestart"]),
                    override("msxml6", "native,builtin"),
                ],
                notes: [
                    "winetricks extracts msxml6.dll/msxml6r.dll from this hotfix with "
                    + "cabextract; Cork does not bundle a cabinet extractor, so it runs "
                    + "the hotfix, which does not install on every prefix"
                ]
            ),

            manual(
                id: "vcrun6",
                name: "Visual C++ 6 SP4 Runtime",
                summary: "Visual C++ 6.0 SP4 runtime (mfc42, msvcp60, msvcirt, …). "
                    + "Requires manual installation.",
                category: "Runtimes",
                reason: "Visual C++ 6 SP4 ships as a nested self-extracting installer "
                    + "(VC6RedistSetup) that must be unpacked with a cabinet extractor, "
                    + "which Cork does not bundle. Install it with 'winetricks vcrun6' in "
                    + "the prefix, or copy mfc42.dll/msvcp60.dll/msvcirt.dll into "
                    + "drive_c/windows/system32 manually."
            ),
            manual(
                id: "riched20",
                name: "Microsoft RichEdit 2.0",
                summary: "RichEdit 2.0 control (riched20.dll). Requires manual installation.",
                category: "Libraries",
                reason: "RichEdit 2.0 (riched20.dll) is only distributed inside the Windows "
                    + "2000 Service Pack 4 archive (W2KSP4_EN.EXE), which requires cabinet "
                    + "extraction. Extract riched20.dll with cabextract and copy it into "
                    + "drive_c/windows/system32."
            ),
            manual(
                id: "corefonts",
                name: "Microsoft Core Fonts",
                summary: "Arial, Times New Roman, Courier New and the other Andale core "
                    + "fonts. Requires manual installation.",
                category: "Fonts",
                reason: "The Core fonts ship as per-font self-extracting cabinet archives "
                    + "(arial32.exe, times32.exe, …) that must be unpacked and registered "
                    + "with the font system. Install with 'winetricks corefonts', or copy "
                    + "the .ttf files into drive_c/windows/Fonts."
            ),
            manual(
                id: "gdiplus",
                name: "Microsoft GDI+",
                summary: "GDI+ (gdiplus.dll) as shipped with Windows 7 SP1. Requires manual "
                    + "installation.",
                category: "Libraries",
                reason: "GDI+ for Windows 7 is only distributed inside the Windows 7 SP1 "
                    + "update package (windows6.1-KB976932-X86.exe), which requires cabinet "
                    + "extraction. Extract gdiplus.dll with cabextract and copy it into "
                    + "drive_c/windows/system32, then set a native override for gdiplus."
            ),
        ]

        return entries.sorted { $0.component.id < $1.component.id }
    }

    /// The shared "extract DirectX redistributable + DXSETUP" step sequence.
    private static func directXSteps(
        id: String,
        redistURL: String,
        redistFileName: String,
        overrides: [String]
    ) -> [DependencyStep] {
        let directory = #"C:\cork\"# + id
        var steps: [DependencyStep] = [
            .download(url: redistURL, fileName: redistFileName),
            .createDirectory(directory),
            .runCommand(command: redistFileName, arguments: ["/Q", "/T:\(directory)"]),
            .runInstaller(command: "\(directory)\\DXSETUP.exe", arguments: ["/silent"]),
        ]
        steps.append(contentsOf: overrides.map { override($0, "native,builtin") })
        return steps
    }

    private static var xactOverrides: [String] {
        (0...7).map { "xaudio2_\($0)" }
            + (0...7).map { "x3daudio1_\($0)" }
            + (1...5).map { "xapofx1_\($0)" }
            + (0...10).map { "xactengine2_\($0)" }
            + (0...7).map { "xactengine3_\($0)" }
    }
}

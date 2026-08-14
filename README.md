# nix-binary-base-packing-creator

**English** | [中文](README.zh-CN.md)

A portable **Agent Skill** that turns *"build locally → package with Nix → usable in seconds"* into a repeatable workflow. Core principle: **Nix packages, it doesn't compile.**

Language-agnostic (Rust / Go / Node / Python / C / C++ / Tauri ...) — as long as your machine can produce an **executable artifact**: a single-file binary, or an interpreter-based app you've already "single-filed" locally (`bun compile`, Node SEA, PyInstaller onedir, ...).

## What it does

Given a request like *"nix打包"*, *"write a default.nix"*, *"pack this binary into my system"*, the agent generates a **binary-base** `default.nix` — a `stdenv.mkDerivation` that skips every build phase and copies your locally built artifact into `$out` via a path literal:

```nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.stdenv.mkDerivation {
  pname = "myapp";
  version = "0.1.0";

  src = null;
  unpackPhase = "true";
  buildPhase = "true";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${./target/release/myapp} $out/bin/myapp
    runHook postInstall
  '';
}
```

Then `nix-build && nix profile install ./result` puts the command on your PATH in seconds — no compilation, no dependency hashes, no source builds.

## Highlights

- **Artifact triage first** — `file` + `readelf -l | grep interp` + `ldd`, then pick from four artifact types (static / store-linked / foreign dynamic / interpreted). The template is chosen by **ELF shape, not by language**.
- **4 battle-tested templates**: basic, GUI (`wrapGAppsHook3`), foreign/prebuilt (`autoPatchelfHook`), interpreted scripts (`patchShebangs` + `wrapProgram`).
- **Real-incident troubleshooting guide** — every entry from actual failures (ldd not found, GLIBC mismatch, bun artifacts can't be stripped, PyInstaller `--onefile`, NSS fallback, `dlopen`-ed libs, non-ASCII paths, ...).
- **Honest, scoped positioning** — a *fast-and-dirty local tool*: not reproducible builds, not nixpkgs material. If you need those, the skill says so and points you to the source-build functions.

## Install

Clone (or copy) the repo into your agent's **skills directory**:

```bash
git clone https://github.com/PAKIKNOWLEDGE/skill-nix-binary-base-packing-creator
```

Then place the folder per your tool's convention. The `SKILL.md` convention is agent-agnostic — anything that supports `SKILL.md` can use it:

| Tool | Typical location |
|---|---|
| Claude Code | `~/.claude/skills/<name>/` |
| Cline / Roo Code / OpenCode / Zed / Cursor / Codex / Windsurf | `SKILL.md`-compatible; see each tool's docs for its skills directory |

## Repository layout

```
.
├── SKILL.md                     # Skill instructions — the full workflow the agent follows
├── README.md                    # This file (English)
├── README.zh-CN.md              # 中文版
├── LICENSE                      # MIT
└── references/
    ├── template-basic.nix       # static / store-linked binaries (CLI/TUI)
    ├── template-gui.nix         # GUI apps (GTK/Qt/Tauri/webview)
    ├── template-patchelf.nix    # foreign / prebuilt / closed-source binaries
    ├── template-interpreter.nix # interpreted scripts & multi-file artifacts
    └── troubleshooting.md       # symptom → fix, all from real incidents
```

## Requirements

- Nix (NixOS, or any distro with nix) with a local `nixpkgs`
- The artifact **already built on this machine** (`cargo build --release` / `go build` / `bun build --compile` ...) — the skill packages what you have; rebuilding after a machine switch or a clean checkout is on you
- Intended for personal, local, single-architecture use

## Full instructions

The complete workflow — artifact triage, template decision tree, language cheat-sheet, key rules, install guidance — lives in [`SKILL.md`](SKILL.md) and [`references/troubleshooting.md`](references/troubleshooting.md). This README only introduces the skill; the agent reads `SKILL.md` for the how-to.

## License

MIT — see [LICENSE](LICENSE).

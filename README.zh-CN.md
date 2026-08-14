# nix-binary-base-packing-creator

[English](README.md) | **中文**

一个可移植的 **Agent Skill**：把"本机构建产物 → Nix 纯打包 → 秒级进系统"固化成一个可复现的工作流。核心原则：**Nix 不编译，只打包**。

语言无关（Rust / Go / Node / Python / C / C++ / Tauri ...），前提是本机能产出**可执行产物**——包括单文件二进制，也包括先在本机"单文件化"过的解释型应用（`bun compile` / Node SEA / PyInstaller onedir 等）。

## 它能做什么

收到"nix打包"、"写个default.nix"、"把这个二进制打包进系统"这类请求时，Agent 会生成一个 **binary-base** 风格的 `default.nix` —— 一个跳过所有构建阶段、用路径字面量把本机产物拷进 `$out` 的 `stdenv.mkDerivation`：

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

然后 `nix-build && nix profile install ./result` 几秒内命令就进 PATH —— 不编译、不写依赖 hash、不搞源码构建。

## 亮点

- **先做产物体检** —— `file` + `readelf -l | grep interp` + `ldd`，按四个类型（静态 / store 内动态 / 外来动态 / 解释型）选模板。**按 ELF 形态选，不按语言选**。
- **4 个实战模板**：basic、GUI（`wrapGAppsHook3`）、外来/预编译（`autoPatchelfHook`）、解释型脚本（`patchShebangs` + `wrapProgram`）。
- **真实踩坑排障手册** —— 每条都来自实际事故（ldd not found、GLIBC 版本不匹配、bun 产物不能 strip、PyInstaller `--onefile`、NSS 降级、`dlopen` 缺库、非 ASCII 路径……）。
- **定位诚实有边界** —— 这是"快而脏的本地工具"：不做可复现构建、不适合进 nixpkgs。需要那些能力时，skill 会明说并指引你用源码构建函数。

## 安装

把仓库克隆（或复制）到你的 Agent 的 **skills 目录**：

```bash
git clone https://github.com/PAKIKNOWLEDGE/skill-nix-binary-base-packing-creator
```

然后按所用工具的约定放置。`SKILL.md` 规范与厂商无关，任何支持 `SKILL.md` 的 Agent 都能用：

| 工具 | 常见位置 |
|---|---|
| Claude Code | `~/.claude/skills/<name>/` |
| Cline / Roo Code / OpenCode / Zed / Cursor / Codex / Windsurf | 兼容 `SKILL.md`；目录路径见各工具文档 |

## 仓库结构

```
.
├── SKILL.md                     # Skill 主指令 —— Agent 执行的完整工作流
├── README.md                    # 英文版
├── README.zh-CN.md              # 本文件（中文版）
├── LICENSE                      # MIT
└── references/
    ├── template-basic.nix       # 静态 / store 内动态二进制（CLI/TUI）
    ├── template-gui.nix         # GUI 应用（GTK/Qt/Tauri/webview）
    ├── template-patchelf.nix    # 外来 / 预编译 / 闭源二进制
    ├── template-interpreter.nix # 解释型脚本 & 多文件产物
    └── troubleshooting.md       # 症状 → 修复，全部来自真实事故
```

## 使用前提

- Nix（NixOS 或任意装有 nix 的发行版）且有本地 `nixpkgs`
- 产物**已在本机构建好**（`cargo build --release` / `go build` / `bun build --compile` ...）—— skill 只打包你已有的东西；换机器 / clean 后重新构建是你自己的事
- 面向个人、本地、单架构使用

## 完整指令

完整工作流 —— 产物体检、模板决策树、语言速查表、关键规则、安装引导 —— 都在 [`SKILL.md`](SKILL.md) 和 [`references/troubleshooting.md`](references/troubleshooting.md) 里。本 README 只介绍这个 skill；Agent 干活时读的是 `SKILL.md`。

## License

MIT —— 见 [LICENSE](LICENSE)。

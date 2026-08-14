---
name: nix-binary-base-packing-creator
description: 用"二进制 base"方式为任意语言项目生成/改写 Nix 打包（default.nix）——nix 只负责把本机已构建的产物装进 $out，不负责编译。适用于 Rust/Go/Node(Python(bun/SEA)/Python/C/C++/Tauri 等一切本机能产出可执行产物的语言。核心判据不是语言，而是"产物体检"：file + readelf -l | grep interp + ldd，据此分四型（静态直拷 / 动态-store 直拷 / 动态外来需 autoPatchelf / 解释型需 wrapper 或单文件化）。Use when the user says "nix打包"、"写个default.nix"、"打包进系统"、"nix profile install"、"弄进系统可用"、"二进制打包"、"go build 产物塞进系统"、"bun compile 打包"、"python 打包 nix"，mentions a project needing Nix packaging, wants to convert a buildRustPackage/srcs-build derivation to binary-base, or needs GUI/CLI app packaging with runtime libs, icons, desktop files. Covers: 产物体检四型、basic 模板、GUI 应用 (wrapGAppsHook3)、外来二进制 (autoPatchelfHook)、解释型脚本 (patchShebangs+wrapProgram)、install & config guidance (nix profile install, systemPackages, config templates)。定位：快而脏的本地工具。Do NOT use for building from source inside nix (use buildRustPackage/buildGoModule/buildNpmPackage etc.), for reproducible CI builds, or for publishing to nixpkgs.
---

# nix-binary-base-packing-creator

把"本机构建产物 → nix 纯打包 → 秒级进系统"这个思路固化成可复现的工作流。核心原则：**nix 不编译，只打包**。适用于任何语言（Rust / Go / Node / Python / C/C++ / Tauri ...），前提是本机能产出**可执行产物**——包括单文件二进制，也包括先在本机"单文件化"过的解释型应用（bun compile / Node SEA / PyInstaller onedir 等）。

## 定位（先说清楚，免得期望错位）

这是**"快而脏的本地工具"**：本机个人使用、不想维护 derivation、产物只在本机架构跑。它不做可复现构建、不保证跨机器/跨架构、不适合进 nixpkgs——那是 `buildRustPackage` / `buildGoModule` / `buildNpmPackage` 等源码构建函数的职责。它的价值是**秒级进系统 + 复用打包经验**，代价是产物与"本机怎么构建的"绑定。

## 核心思想（先理解，再动手）

二进制 base 打包 = `stdenv.mkDerivation` + 跳过所有构建阶段 + 路径字面量把本机产物拷进 `$out`：

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

- `src = null` + `unpackPhase/buildPhase = "true"`：跳过解压、配置、编译
- `${./path/to/artifact}` 是**路径字面量**：nix 构建时把该文件作为输入拷进 store。文件不存在 → 求值直接报错
- 安装后 `nix-build && nix profile install ./result`，命令即入 PATH
- 使用前提：**先在本机构建好产物**（`cargo build --release` / `go build` / `npm run build` / `bun build --compile` ...）。换机器/clean 后要重新构建

## 第一步：产物体检（语言无关，任何语言都先做这个）

**不要按"这是什么语言"选模板，按产物的 ELF 形态选。** 用三个命令体检：

```bash
file <产物>                              # statically / dynamically linked
readelf -l <产物> | grep interp          # ELF 解释器(interpreter)指向哪
ldd <产物>                               # 动态库依赖
```

按体检结果分四型：

| 类型 | 判据 | 处理 | 典型 |
|---|---|---|---|
| **A 静态** | `ldd` 报 `not a dynamic executable`，无 PT_INTERP | 直接 cp，闭包零外部依赖 | Go 纯静态（`CGO_ENABLED=0`）、Rust musl target、`gcc -static` |
| **B 动态·store 内** | interpreter/RUNPATH 指向 `/nix/store/...` | 直接 cp，闭包自动补齐 | 在 NixOS / nix shell 里构建的任何语言产物 |
| **C 动态·外来** | interpreter 是 `/lib64/ld-linux-...`（NixOS 上没有） | autoPatchelfHook 补库 | 在 Ubuntu 等非 nix 环境构建的动态二进制 |
| **D 解释型/多文件** | 不是单 ELF：脚本、目录、需要解释器 | 见"解释型语言"一节 | Node/Python 纯脚本、PyInstaller onedir |

**注意 A 型和 B 型的区别不是"静态 vs 动态"，而是"闭包要不要管"**：
- A 型闭包只有自己（严格零依赖）；
- B 型二进制的 RUNPATH/解释器里写着 `/nix/store/<hash>-glibc-...` 这样的字符串，**Nix 引用扫描器会自动扫描输出文件字节、把这些 store 路径补进闭包**（实测验证：零 buildInputs 的动态二进制，闭包自动含 glibc + libgcc，`nix-collect-garbage` 不会删掉它们）。所以你什么都不用写，直接 cp 就能跑且 GC 安全。

## 决策树：选哪个模板

| 产物类型 | 模板 | 说明 |
|---|---|---|
| A 静态 / B 动态·store 内（CLI/TUI/无 GUI） | `template-basic.nix` | 直接拷二进制，需要时加配置文件模板 |
| B 且是 GUI（GTK/Qt/Tauri/webview） | `template-gui.nix` | basic + wrapGAppsHook3 + 图标 + desktop |
| C 动态·外来 / 预编译 / 闭源 | `template-patchelf.nix` | autoPatchelfHook 自动补 rpath/解释器 |
| D 解释型脚本（需要运行时解释器） | `template-interpreter.nix` | patchShebangs + wrapProgram 注入解释器 |
| D 多文件产物（PyInstaller onedir / Nuitka standalone） | `template-patchelf.nix` 拷目录 | autoPatchelfHook 扫目录里所有 ELF |
| Electron / AppImage | **不适用** | 走 `appimageTools.wrapType2` 或 nix 原生构建，binary-base 救不了 |

## 语言速查表（本机构建命令 → 类型 → 注意点）

| 语言 | 本机构建命令 | 类型 | 注意 |
|---|---|---|---|
| **Go** 纯静态 | `CGO_ENABLED=0 go build -trimpath` | A | NSS 降级：net/os/user 走纯 Go 解析器，绕 /etc/nsswitch.conf；DNS 依赖 systemd-resolved、用户查询只读 /etc/passwd |
| **Go** 带 cgo | NixOS 原生 `go build` | B | 闭包自动补 glibc；外来构建则 C |
| **Rust** 无 C 依赖 | `cargo build --release --target x86_64-unknown-linux-musl` | A | 显式开 crt-static；静态只能走 musl，glibc 不能静态链进 Rust |
| **Rust** 带 C 依赖/Tauri | NixOS 原生 `cargo build --release` | B | 别尝试 musl 静态化 GTK 全家桶，不现实 |
| **C/C++** | NixOS 原生编译 | B | 外来构建则 C |
| **Node** 单文件 | `bun build --compile ./main.ts --outfile app` | A/B | 产物动态链 glibc、**不能 strip**（内嵌 JS）；interpreter 硬编码 store 路径时可能需 patchelf |
| **Node** SEA | 在 nix 里用 nixpkgs `nodejs` 做 base 跑 SEA 流程 | B | 见 troubleshooting；SEA 只支持内置模块 require，第三方依赖先 bundle |
| **Python** 目录式 | `pyinstaller --onedir dist/` / `nuitka --standalone` | C | 拷整个目录 + autoPatchelfHook 扫全部 ELF；**`--onefile` 不可行** |
| **解释型脚本** | 无（产物就是脚本） | D | 见"解释型语言"一节 |

## 工作流（按顺序执行）

### Step 0: 产物体检
- 找到产物路径（Rust: `target/release/<name>`；Tauri: `src-tauri/target/release/<name>`；Go: `./<name>`；Node: `dist/` 或 bun compile 的 outfile；Python: `dist/`）
- `file` + `readelf -l ... | grep interp` + `ldd` 判断类型（A/B/C/D）
- 产物不存在 → 先让用户构建，或提示"换机器需先构建"

### Step 1: 确认运行时依赖
- **A 型（静态）**：无，跳过
- **B 型（store 内动态）**：一般零配置；`ldd` 有 not found 说明漏库 → 补 `buildInputs`
- **C 型（外来动态）**：`ldd` 的每个 not found 加进 `buildInputs`（用 `search.nixos.org` / `nix-locate` 找包名）
- **D 型（解释型）**：确认解释器（node/python）版本和依赖

### Step 2: 选模板并填充
- 从 references/ 复制对应模板到项目 `default.nix`（或按模板改造已有的）
- 填 `pname`、`version`、产物路径、资源文件
- GUI 应用：见 gui 模板的 buildInputs 与桌面集成步骤
- 配置文件/资源模板：拷到 `$out/share/<pname>/` 随包分发（**供参考，勿引导用户从这里拷**，见关键规则 6）

### Step 3: 构建验证
```bash
nix-build            # 秒级（不编译），生成 ./result
ls result/bin/       # 确认二进制
```
- 报错先看错误类型（见 references/troubleshooting.md）

### Step 4: 运行验证
- `result/bin/<name>` 直接跑，或伪终端跑 TUI/交互程序
- GUI 应用：确认图标、desktop 集成正常；`ldd result/bin/<name>` 无"not found"
- 静态 Go/musl 二进制：确认 DNS/用户查询行为符合预期（NSS 降级）
- 配置文件读取：确认程序从正确路径读配置（XDG/家目录/工作目录）

### Step 5: 安装引导
- 用户级：`nix profile install ./result`（现代机制；`nix-env` 与 nix profile 的 profile 互不兼容，报 incompatible 时改用 nix profile）
- 系统级：`environment.systemPackages = [ (import /path/to/repo {}) ];`（default.nix 直接返回 derivation 时不需要 `.attr`）
- 配置文件：README 引导用户 `mkdir -p ~/.config/<pname> && cp config.toml ~/.config/<pname>/` —— **从源码目录拷，不要从 `$out/share` 拷**（nix store 文件是 0444 只读，`cp` 会保留只读位，用户无法编辑；从源码拷是 644）

## 解释型语言（D 型）怎么处理

解释型脚本（`#!/usr/bin/env node` / `#!/usr/bin/env python3` 的 CLI）**没有单二进制**，binary-base 不能"纯 cp"。三条路，按需求选：

1. **先单文件化再走 binary-base**（最贴合本 skill 精神）：
   - Node：`bun build --compile`（把 Bun 运行时打进单文件）；Node 官方 SEA 流程；`deno compile`
   - Python：`pyinstaller --onedir` / `nuitka --standalone`（目录式，配合 autoPatchelfHook）
   - 产物就变成 A/B 型，按对应模板处理
2. **nix 提供解释器 + wrapper**（`template-interpreter.nix`）：把脚本拷进 `$out/bin`，`patchShebangs` 把 shebang 改写成 store 里的解释器绝对路径，再用 `wrapProgram` 注入运行时依赖（PATH / NODE_PATH / PYTHONPATH）。**这不是自包含，$out 里没有解释器本体，解释器和依赖必须进闭包（buildInputs）**
3. **直接 nix 原生构建**（放弃 binary-base）：Node 用 `buildNpmPackage`，Python 用 `buildPythonApplication`——可复现、可 override，但要联网构建依赖、写依赖 hash，适合要长期维护的东西

**为什么必须 patchShebangs**：NixOS 上解释器没有标准位置（`/usr/bin/python` 不存在）；构建沙箱里连 `/usr/bin/env` 都没有。patchShebangs 把 shebang 改写成 store 绝对路径，让脚本**独立于用户的 PATH** 也能跑。（注：NixOS 宿主机的 `/usr/bin/env` 其实是存在的，由 `environment.usrbinenv` 创建，但解释器本身不存在。）

## 关键规则（实战验证 + 研究确认）

1. **路径字面量必须存在**：`${./target/release/x}` 不存在 → nix 求值期报错，错误信息指向该路径。这是二进制 base 的固有特性，不是 bug。**中文/非 ASCII 路径在路径字面量里会解析失败**（实测），把产物放 ASCII 路径或用 `builtins.path { name = "x"; path = ./.; }` 固定 store 路径名（否则 store 路径名取自父目录名，目录改名 → 路径变 → 触发无谓重建）。
2. **installPhase 建议用 `runHook preInstall/postInstall`**：保持 stdenv hook 机制兼容，别人 override 你的 derivation 时才不会断。（注：这是建议，不是从本项目提炼的强制规则。）
3. **`meta.mainProgram` 必须填**：`nix run` 依赖它。（desktop 文件不依赖它——desktop 的 Exec 用绝对路径。）
4. **`meta.platforms` 要收敛**：产物只在本机构建过，别写 `platforms.all`。
5. **strip 由 stdenv 自动做**：fixupPhase 默认 strip。**但 bun compile / Node SEA 产物不能 strip**（会删掉内嵌的 JS/runtime），要设 `dontStrip = true`。
6. **不要教条**：模板是起点不是终点。产物特殊（需要额外资源目录、需要 setuid、需要 wrapper 参数）就按需加 `postInstall`、`preFixup`，不改变"本机产物 → 纯打包"的本质。
7. **`.gitignore` 加 `result` / `result-*`**：避免误提交构建 symlink。
8. **静态 ≠ 无环境依赖**：静态二进制的"零依赖"只是不依赖库文件；运行时仍读 `/etc/resolv.conf`、`/etc/passwd`、`/etc/nsswitch.conf`。凡涉及 DNS 和用户查询的程序，注明环境前提（systemd-resolved 是否在跑等）。
9. **GC 与闭包**：引用扫描器自动追踪二进制 RUNPATH/解释器里的 store 路径，B 型产物 GC 安全。但**运行时才 dlopen 的库**（`ctypes.CDLL("libfoo.so")`、gstreamer 插件）不写在二进制里，扫不到 → 用 `buildInputs` 加库或用 `runtimeDependencies`（autoPatchelf 模板已示范）。

## 案例参考（本项目实战提炼 + 研究核实）

- **Oscivoid（Rust TUI）**：basic 模板。产物是**动态链接**的（NEEDED 仅 libc/libgcc，interpreter 指向 nix store 的 glibc），但因为在本机 nix 环境构建，引用扫描器自动把 glibc/libgcc 补进闭包——零 buildInputs 也能跑且 GC 安全（实测验证）。字体用 `include_str!` 内嵌，配置从 `~/.config/oscivoid/config.toml` 读（缺失回退默认值）→ 打包只需 `cp` 二进制 + 配置模板进 `$out/share/`。
- **Sleephat（Tauri GUI）**：gui 模板。`webkitgtk_4_1 gtk3 librsvg gsettings-desktop-schemas glib-networking dconf gst_all_1.gst-plugins-base` 进 `buildInputs`，`wrapGAppsHook3` 进 `nativeBuildInputs`，`preFixup` 里 `gappsWrapperArgs+=(--unset http_proxy --unset https_proxy --unset all_proxy)` 清代理防 502，图标进 `share/icons/hicolor/128x128/apps/`，desktop 文件用 `substituteAll` 从 `.desktop.in` 生成。

## Troubleshooting

见 `references/troubleshooting.md`（按症状查找：ldd not found、interpreter 不存在、GLIBC 版本、nix-env incompatible、attribute not found、store 0444、autoPatchelf 缺失库、bun 不能 strip、PyInstaller onefile、NSS 行为、dlopen 缺库、中文路径等）。

# skill-nix-binary-base-packing-creator

一个通用 Agent **Skill**：把"本机构建产物 → Nix 纯打包 → 秒级进系统"固化成一个可复现的工作流。核心原则：**Nix 不编译，只打包**。

适用于任何语言（Rust / Go / Node / Python / C/C++ / Tauri ...），前提是本机能产出**可执行产物**——包括单文件二进制，也包括先在本机"单文件化"过的解释型应用（`bun compile` / Node SEA / PyInstaller onedir 等）。

## 这是什么

这是**通用 Agent Skill**（遵循业界通用的 `SKILL.md` + `references/` 目录规范，由 Anthropic 提出、被 Claude Code / Cline / Roo Code / OpenCode / Zed / Cursor / Codex / Windsurf 等众多 Agent 工具采用），不是 Nix 库。把它装进任意支持 skill 的 Agent 的 skills 目录后，Agent 在收到"nix打包"、"写个default.nix"、"打包进系统"、"二进制打包"这类请求时，会自动按这套流程帮你生成二进制 base 风格的 `default.nix`。格式本身与具体厂商无关，只依赖 Agent 是否支持 `SKILL.md` 约定。

## 核心思想

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
- `${./path/to/artifact}` 是**路径字面量**：Nix 构建时把该文件作为输入拷进 store，文件不存在 → 求值期直接报错
- 安装后 `nix-build && nix profile install ./result`，命令即入 PATH
- 使用前提：**先在本机构建好产物**（`cargo build --release` / `go build` / `npm run build` / `bun build --compile` ...）

## 定位与边界

这是**"快而脏的本地工具"**：本机个人使用、不想维护 derivation、产物只在本机架构跑。它**不做**可复现构建、不保证跨机器/跨架构、不适合进 nixpkgs——那是 `buildRustPackage` / `buildGoModule` / `buildNpmPackage` 等源码构建函数的职责。它的价值是**秒级进系统 + 复用打包经验**，代价是产物与"本机怎么构建的"绑定。

## 安装

把本仓库克隆（或复制）到你的 Agent 的 **skills 目录**即可。各工具目录不同，最通用的方式：

```bash
git clone https://github.com/PAKIKNOWLEDGE/skill-nix-binary-base-packing-creator
# 然后把整个目录放进你的 Agent 的 skills 目录，例如：
#   Claude Code：  ~/.claude/skills/skill-nix-binary-base-packing-creator
#   Cline：        ~/.cline/skills/...   或项目内 .cline/skills/
#   Roo Code：     ~/.roo/skills/...
#   OpenCode/Zed/Cursor/Codex 等：按各自工具的 skill 目录约定放置
# 具体路径以所用工具的官方文档为准；也可以直接用工具自带的 skill 管理命令安装
```

要求目录里包含 `SKILL.md`（Agent 读取的指令）与 `references/`（模板与排障资料）。目录结构见下文。

## 仓库结构

```
.
├── SKILL.md                    # Skill 主指令：Agent 读取的完整工作流
├── README.md                   # 本文件
└── references/
    ├── template-basic.nix      # 模板 A：静态 / store 内动态二进制（CLI/TUI）
    ├── template-gui.nix        # 模板 B：GUI 应用（GTK/Qt/Tauri/webview）
    ├── template-patchelf.nix   # 模板 C：外来动态二进制 / 预编译 / 闭源
    ├── template-interpreter.nix# 模板 D：解释型脚本 / 多文件产物
    └── troubleshooting.md      # 按症状排障（全部来自真实踩坑）
```

## 工作流速览

### Step 0: 产物体检（语言无关）

**不要按"这是什么语言"选模板，按产物的 ELF 形态选。** 三个命令：

```bash
file <产物>                              # statically / dynamically linked
readelf -l <产物> | grep interp          # ELF 解释器指向哪
ldd <产物>                               # 动态库依赖
```

| 类型 | 判据 | 处理 | 典型 |
|---|---|---|---|
| **A 静态** | `ldd` 报 `not a dynamic executable`，无 PT_INTERP | 直接 cp，闭包零外部依赖 | Go 纯静态（`CGO_ENABLED=0`）、Rust musl target |
| **B 动态·store 内** | interpreter/RUNPATH 指向 `/nix/store/...` | 直接 cp，闭包自动补齐 | 在 NixOS / nix shell 里构建的任何语言产物 |
| **C 动态·外来** | interpreter 是 `/lib64/ld-linux-...`（NixOS 上没有） | autoPatchelfHook 补库 | 在 Ubuntu 等非 nix 环境构建的动态二进制 |
| **D 解释型/多文件** | 不是单 ELF：脚本、目录、需要解释器 | patchShebangs + wrapProgram / 先单文件化 | Node/Python 纯脚本、PyInstaller onedir |

### Step 1–5: 选模板 → 填充 → 构建 → 运行验证 → 安装

1. **确认运行时依赖**：A 型无；B 型一般零配置；C 型把 `ldd` 每个 not found 加进 `buildInputs`；D 型确认解释器版本
2. **选模板并填充**：从 `references/` 复制对应模板为项目的 `default.nix`，填 `pname`/`version`/产物路径/资源
3. **构建验证**：`nix-build`（秒级，不编译）→ `ls result/bin/`
4. **运行验证**：直接跑二进制；GUI 确认图标/desktop 集成；静态二进制确认 DNS/用户查询行为
5. **安装引导**：用户级 `nix profile install ./result`；系统级 `environment.systemPackages = [ (import /path/to/repo {}) ];`

### 决策树：选哪个模板

| 产物类型 | 模板 | 说明 |
|---|---|---|
| A 静态 / B 动态·store 内（CLI/TUI） | `template-basic.nix` | 直接拷二进制，需要时加配置文件模板 |
| B 且是 GUI（GTK/Qt/Tauri/webview） | `template-gui.nix` | basic + wrapGAppsHook3 + 图标 + desktop |
| C 动态·外来 / 预编译 / 闭源 | `template-patchelf.nix` | autoPatchelfHook 自动补 rpath/解释器 |
| D 解释型脚本 | `template-interpreter.nix` | patchShebangs + wrapProgram 注入解释器 |
| D 多文件产物（PyInstaller onedir / Nuitka） | `template-patchelf.nix` 拷目录 | autoPatchelfHook 扫目录里所有 ELF |
| Electron / AppImage | **不适用** | 走 `appimageTools.wrapType2` 或 Nix 原生构建 |

## 语言速查

| 语言 | 本机构建命令 | 类型 | 注意 |
|---|---|---|---|
| **Go** 纯静态 | `CGO_ENABLED=0 go build -trimpath` | A | NSS 降级：DNS 依赖 systemd-resolved、用户查询只读 /etc/passwd |
| **Rust** 无 C 依赖 | `cargo build --release --target x86_64-unknown-linux-musl` | A | 静态只能走 musl，glibc 不能静态链进 Rust |
| **Rust** 带 C 依赖/Tauri | NixOS 原生 `cargo build --release` | B | 别尝试 musl 静态化 GTK 全家桶 |
| **Node** 单文件 | `bun build --compile ./main.ts --outfile app` | A/B | 产物**不能 strip**（内嵌 JS） |
| **Node** SEA | 在 Nix 里用 nixpkgs `nodejs` 做 base | B | SEA 只支持内置模块 require，第三方依赖先 bundle |
| **Python** 目录式 | `pyinstaller --onedir dist/` / `nuitka --standalone` | C | 拷整个目录 + autoPatchelfHook；**`--onefile` 不可行** |
| **解释型脚本** | 无（产物就是脚本） | D | patchShebangs + wrapProgram，解释器进 buildInputs |

## 解释型语言（D 型）三条路

1. **先单文件化再走 binary-base**（最贴合本 skill 精神）：`bun build --compile` / Node SEA / `deno compile` / `pyinstaller --onedir` / `nuitka --standalone`，产物变成 A/B 型
2. **Nix 提供解释器 + wrapper**（`template-interpreter.nix`）：patchShebangs 改写 shebang + wrapProgram 注入 PATH/NODE_PATH/PYTHONPATH。**不是自包含**，解释器和依赖必须进闭包
3. **直接 Nix 原生构建**（放弃 binary-base）：`buildNpmPackage` / `buildPythonApplication`，可复现但要联网构建、写依赖 hash

## 关键规则（实战验证）

- 路径字面量必须存在，且**不能含中文/非 ASCII 路径**（用 `builtins.path` 固定 store 路径名）
- `meta.mainProgram` 必须填（`nix run` 依赖它）；`meta.platforms` 要收敛（别写 `platforms.all`）
- **bun compile / Node SEA 产物不能 strip** → `dontStrip = true`
- 静态 ≠ 无环境依赖：仍读 `/etc/resolv.conf`、`/etc/passwd`、`/etc/nsswitch.conf`
- 运行时才 dlopen 的库引用扫描器扫不到 → 用 `buildInputs` 或 `runtimeDependencies`
- 配置模板随包分发仅供查看，**引导用户从源码目录拷**（store 里是 0444 只读）
- `.gitignore` 加 `result` / `result-*`

## 排障

按症状查找 `references/troubleshooting.md`：ldd not found、interpreter 不存在、GLIBC 版本不匹配、nix-env incompatible、PyInstaller onefile、bun 0 字节、NSS 行为、dlopen 缺库、中文路径等——全部来自真实踩坑。

## License

MIT（模板内的 `meta.license` 请按实际项目调整）。

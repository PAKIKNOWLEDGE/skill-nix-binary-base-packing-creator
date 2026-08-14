# Troubleshooting

按症状查找。所有条目来自真实踩坑，不是理论。

## nix-build 报 "path ... does not exist"（路径字面量）
`${./target/release/xxx}` 引用的文件在本机不存在。
原因：二进制 base 的固有特性——nix 求值期检查路径存在性。
修复：先在本机构建产物（`cargo build --release` 等）。换机器/clean 后同样要先构建。

## 运行报 `error while loading shared libraries: libX not found`
动态链接的二进制缺运行时库。
排查：`ldd result/bin/xxx` 看哪些库 not found。
修复：把对应 nix 包加进 `buildInputs`（用 `search.nixos.org` 或 `nix-locate` 找包名）。

## `nix-env -f . -iA xxx` 报 `attribute 'xxx' ... not found`
两种可能：
1. 运行命令的目录不对（`.` 指向了没有 default.nix 或不同项目的目录）——在项目目录运行。
2. 系统 profile 已被 `nix profile`（新机制）占用，nix-env 与其不兼容——报错会说 `profile ... is incompatible with 'nix-env'; please use 'nix profile'`。改用 `nix profile install ./result`。

## `nix profile install .` 报 `not part of a flake`
项目没有 flake.nix。`nix profile install` 只接受 flake 引用或 store path。
修复：先 `nix-build` 生成 `./result`，再 `nix profile install ./result`（或 `nix profile install "$(nix-build --no-out-link 2>/dev/null)"`，两者等价）。

## 从包内拷配置模板后文件只读（-r--r--r--）
nix store 文件全是 0444，`cp` 默认保留源权限位，副本也是只读。
修复（根治）：README 引导用户从**源码目录**拷（源码文件是 644）：
```bash
mkdir -p ~/.config/myapp
cp config.toml ~/.config/myapp/
```
应急：`chmod u+w ~/.config/myapp/config.toml`。

## GUI 应用白屏 / 图标不显示 / 主题异常
缺少 wrapGAppsHook3 或运行时库。
修复：`nativeBuildInputs = [ wrapGAppsHook3 ]` + `buildInputs` 补全（gtk3、gsettings-desktop-schemas、glib-networking 等）。图标必须放在 `share/icons/hicolor/<size>x<size>/apps/`。

## autoPatchelf 报缺失依赖失败
`autoPatchelf` 默认遇到无法解析的依赖会整体失败。
修复：把库加进 `buildInputs`；对永远找不到的（闭源驱动），设 `autoPatchelfIgnoreMissingDeps = [ "libxxx.so.1" ];`。

## `nix run` 报找不到主程序
`meta.mainProgram` 没填。补上：`mainProgram = "myapp";`。（desktop 文件不依赖它，Exec 用的是绝对路径。）

## 运行报 `No such file or directory`，但文件明明在（外来动态二进制）
二进制是**外来构建**的（interpreter 硬编码 `/lib64/ld-linux-x86-64.so.2`，NixOS 上不存在）。
排查：`readelf -l result/bin/xxx | grep interp` 看解释器是不是 `/lib64/...`。
修复：走 `template-patchelf.nix`（autoPatchelfHook 会把解释器改成 nix store 里的 ld-linux）。

## 运行报 `version 'GLIBC_2.xx' not found`（glibc 版本不匹配）
产物是在 glibc 更新的系统上构建的。NixOS 上排查：`ldd result/bin/xxx`。
修复：在本机 NixOS / 相同 nixpkgs 环境重新构建产物；或对静态二进制用 musl target / `CGO_ENABLED=0` 绕开 glibc。

## 打包静态 Go/Rust 二进制后，DNS / 用户查询行为不对（NSS 降级）
静态二进制的"零依赖"只是不依赖库文件；运行时仍读 `/etc/resolv.conf`、`/etc/passwd`。
纯静态的 Go（CGO_ENABLED=0）/ musl 产物用**纯 Go/musl 解析器，绕过 /etc/nsswitch.conf**：
- DNS 走裸查询（依赖 systemd-resolved 的 127.0.0.53 stub，mDNS、.local 等 NSS 后端能力丢失）
- 用户查询只读 `/etc/passwd`（读不到 LDAP / NSS 后端）
需要 NSS 能力时：改用 cgo 构建（Go）并在 NixOS 上动态链接，或在 README 里写明环境前提。

## 程序运行时 dlopen 缺库（ctypes.CDLL 报 cannot open shared object / GUI 无声音白屏）
运行时 `dlopen` 的库（gstreamer 插件、`ctypes.CDLL("libfoo.so")`）**不写进二进制、引用扫描器扫不到**，ldd 也看不到。
修复：把库加进 `buildInputs`，或 autoPatchelf 模板里用 `runtimeDependencies = [ pkgs.xxx ];` 无条件塞进 rpath。

## bun build --compile 产物 strip 后跑不起来 / 打出来 0 字节
- bun 产物把 JS 运行时内嵌在二进制里，**不能 strip**：`dontStrip = true;`
- Nix 沙箱里 bun 编译可能产出 0 字节二进制（bun ≥1.3.2 已知 bug）：换 bun 版本或在非沙箱构建

## PyInstaller --onefile 产物在 NixOS 上跑不了
`--onefile` 是自解压 zip，运行时才把内部 ELF 解压到 /tmp，构建期磁盘上不存在 → autoPatchelfHook 补不到，patch 了也没用（社区实测）。这是 binary-base 明确不适用的一类。
修复：改用 `--onedir`（目录式，autoPatchelfHook 能扫到所有 .so）；或放弃 binary-base，走 poetry2nix / buildPythonApplication 原生构建。

## 路径字面量里含中文/非 ASCII 路径报 "path has a trailing slash"
nix 路径字面量对非 ASCII 路径解析有问题（实测）。把产物放在 ASCII 路径，或用
`builtins.path { name = "myapp"; path = ./.; }` 固定 store 路径名（否则 store 路径名取自父目录名，目录改名 → 路径变 → 无谓重建）。

## 配置查找行为不符合预期（程序读不到 ~/.config）
程序本身的路径逻辑问题，不是打包问题。检查程序：是否读 `$XDG_CONFIG_HOME` / `~/.config`、是否只读 cwd、缺失时是否回退默认值。二进制 base 不改变程序行为，只负责把二进制放对位置。

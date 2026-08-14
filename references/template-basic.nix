# 模板 A：静态 / store 内动态二进制（CLI、TUI、纯脚本产物）
# 适用：
#   - A 型（静态）：Go CGO_ENABLED=0、Rust musl target、gcc -static → ldd 报 not a dynamic executable
#   - B 型（动态但 interpreter/RUNPATH 指向 /nix/store）：在 NixOS / nix shell 里构建的产物 → 直接 cp，
#     引用扫描器会自动把二进制引用的 glibc/libgcc 等补进闭包，GC 安全，零配置
# 用法：复制为项目 default.nix，替换 pname/version/产物路径/资源，然后 nix-build
{ pkgs ? import <nixpkgs> {} }:

let
  version = "0.1.0";   # 与项目版本号保持一致
in
pkgs.stdenv.mkDerivation {
  pname = "myapp";
  inherit version;

  # 二进制 base：跳过解压/配置/编译，nix 只打包
  src = null;
  unpackPhase = "true";
  buildPhase = "true";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    # 路径字面量：构建前必须已有该产物（如 cargo build --release / go build / bun build --compile）
    # 注意：中文/非 ASCII 路径在路径字面量里解析失败，放 ASCII 路径
    cp ${./target/release/myapp} $out/bin/myapp

    # 配置文件模板随包分发（供用户参考，勿引导用户从这里拷——store 里是 0444）
    mkdir -p $out/share/myapp
    cp ${./config.toml} $out/share/myapp/config.toml
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "My app";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "myapp";   # 让 nix run / desktop 集成可用
  };
}

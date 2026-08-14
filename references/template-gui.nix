# 模板 B：GUI 应用（GTK/Tauri/Qt/webview）
# 适用：B 型（store 内动态）的 GUI 产物。前提：二进制必须在 NixOS / nix shell 里构建
#      （RUNPATH 指向 /nix/store），引用扫描器才能把库补进闭包；外来构建的 GUI 二进制
#      需要海量 buildInputs + autoPatchelf，基本是另一个量级，直接用模板 C 或放弃。
# 用法：复制为项目 default.nix，按 ldd 输出调整 buildInputs
{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "myapp";
  version = "0.1.0";

  src = null;
  unpackPhase = "true";
  buildPhase = "true";

  # bun build --compile / Node SEA 之类的产物：不能 strip（会删内嵌 JS/runtime）
  # dontStrip = true;

  # wrapGAppsHook3 在 fixup 阶段包一层，注入 GSETTINGS_SCHEMA_DIR、GDK_PIXBUF_MODULE_FILE、XDG_DATA_DIRS 等
  nativeBuildInputs = with pkgs; [ wrapGAppsHook3 ];

  # 运行时系统库：从 `ldd 产物` 的输出确定，缺失一个都会运行失败
  buildInputs = with pkgs; [
    # Tauri/WebKit 系（参考 Sleephat）：
    webkitgtk_4_1 gtk3 librsvg
    gsettings-desktop-schemas glib-networking dconf
    gst_all_1.gst-plugins-base
    # GTK 系常见：gtk3 pango cairo glib
    # Qt 系：qt6.qtbase libGL
  ];
  # dlopen 的运行时库（gstreamer 插件、ctypes 库等）不写进二进制的 ldd，
  # 引用扫描器也扫不到 → 要么加进 buildInputs，要么用 runtimeDependencies 无条件塞进 rpath：
  # runtimeDependencies = with pkgs; [ gst_all_1.gstreamer gst_all_1.gst-plugins-good gst_all_1.gst-libav ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${./src-tauri/target/release/myapp} $out/bin/myapp

    # 图标（Freedesktop hicolor 主题路径）
    mkdir -p $out/share/icons/hicolor/128x128/apps
    cp ${./src-tauri/icons/128x128.png} $out/share/icons/hicolor/128x128/apps/myapp.png

    # desktop 文件：.desktop.in 里用 @out@ 占位，substituteAll 替换
    mkdir -p $out/share/applications
    substituteAll ${./myapp.desktop.in} $out/share/applications/myapp.desktop
    runHook postInstall
  '';

  # 可选：清理包装环境里的代理变量（防代理导致网络请求失败）
  preFixup = ''
    gappsWrapperArgs+=(
      --unset http_proxy --unset https_proxy --unset all_proxy
    )
  '';

  meta = with pkgs.lib; {
    description = "My GUI app";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "myapp";
  };
}

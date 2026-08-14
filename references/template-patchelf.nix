# 模板 C：预编译/闭源/第三方二进制（动态链接，不可控产物）
# 适用：C 型（外来动态二进制，interpreter 是 /lib64/ld-linux...）；也用于目录式多文件产物
#      （PyInstaller --onedir / Nuitka --standalone：installPhase 里 cp -r 整个目录，autoPatchelfHook 会扫全部 ELF）
# autoPatchelfHook 在 fixup 阶段自动扫描 ELF、修补 rpath/解释器指向 nix store
# autoPatchelf 也救不了时（闭源自校验 / 硬编码 FHS 路径 / 自解压）：升级到 steam-run 快速测试、
#      nix-ld（不 patch 也能跑）或 buildFHSUserEnv（伪 FHS 沙箱，比 patchelf 重，能不用就不用）
{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "myapp";
  version = "0.1.0";

  src = null;
  unpackPhase = "true";
  buildPhase = "true";

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];

  # 缺失的动态库：从 `ldd 产物` 输出逐个确定，加到 buildInputs
  # 例：ldd 显示 libssl.so.3 not found → 加 openssl
  buildInputs = with pkgs; [
    # openssl zlib glibc ...
  ];

  # dlopen 运行时加载的库（不会出现在 ldd 里）：无条件加进所有可执行文件 rpath
  # runtimeDependencies = [ pkgs.somePluginLib ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${./vendor/myapp} $out/bin/myapp
    runHook postInstall
  '';

  # 个别库永远找不到（如闭源驱动 libcuda.so.1）：忽略而非失败
  # autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" ];
  # 想手动控制 patch 时机：dontAutoPatchelf = true; 然后 installPhase 里跑 autoPatchelf

  meta = with pkgs.lib; {
    description = "My prebuilt app";
    license = licenses.unfreeRedistributable;   # 按实际许可证调整
    platforms = [ "x86_64-linux" ];
    mainProgram = "myapp";
  };
}

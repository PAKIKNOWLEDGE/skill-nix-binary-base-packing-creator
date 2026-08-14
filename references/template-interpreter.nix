# 模板 D：解释型脚本/多文件产物（需要运行时解释器的 CLI 脚本）
# 适用：#!/usr/bin/env node、#!/usr/bin/env python3 等纯脚本 CLI，或含 node_modules/site-packages 的目录产物
# 这不是"自包含二进制"：$out 里没有解释器本体，解释器和依赖必须进 buildInputs（闭包）
# 用法：复制为项目 default.nix，替换 pname/version/脚本路径/解释器，然后 nix-build
{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "mycli";
  version = "0.1.0";

  src = null;
  unpackPhase = "true";
  buildPhase = "true";

  # 解释器与运行时依赖：必须进闭包，否则脚本能拷进去但跑不起来
  # Node CLI：用 pkgs.nodejs_22（版本按脚本需要）；Python CLI：用 pkgs.python3
  nativeBuildInputs = with pkgs; [ makeWrapper ];
  buildInputs = with pkgs; [
    nodejs_22           # ← 按语言改：python3 / nodejs / bun ...
    # 脚本运行时依赖的命令也加进 PATH（见 wrapProgram 的 --prefix PATH）
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    # 脚本本体（#!/usr/bin/env node 那行会被 fixup 的 patchShebangs 自动改写）
    cp ${./mycli.js} $out/bin/mycli
    chmod +x $out/bin/mycli

    # 如果脚本有 node_modules / site-packages 目录，整个拷进 $out/lib
    # mkdir -p $out/lib
    # cp -r ${./node_modules} $out/lib/node_modules
    runHook postInstall
  '';

  # patchShebangs：stdenv fixupPhase 默认把可执行文件的 shebang 改写为 store 里解释器的绝对路径。
  # 它只在"解释器在构建 PATH 里"（nativeBuildInputs）时生效；找不到会静默失败，注意验证。
  # 若脚本带了依赖目录，用 wrapProgram 注入查找路径（NODE_PATH / PYTHONPATH）：
  postFixup = ''
    wrapProgram $out/bin/mycli \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs_22 ]} \
      --set NODE_PATH $out/lib/node_modules
    # Python 版：--prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.python3 ]} \
    #            --set PYTHONPATH $out/lib/python3.12/site-packages
  '';

  meta = with pkgs.lib; {
    description = "My CLI script";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "mycli";
  };
}

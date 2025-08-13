# shell.nix
let
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
    sha256 = "sha256:0wiimn8mw83g7gd7zysmfqzvkh88010fvpyv1ryclws1gzdysmr1"; # fill after first run
  }) { config.allowUnfree = true; };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.foundry
    pkgs.act
    pkgs.lcov
    pkgs.python3
    pkgs.poetry
  ];
}

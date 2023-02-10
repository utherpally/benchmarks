{
  description = "Zig development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
    zig.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlay = _: prev: {
          zigpkgs = inputs.zig.packages.${system};
        };
        pkgs = import nixpkgs {
          inherit system;
          overlays = [overlay];
        };
      in rec {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            zigpkgs.master
            clang
            gdb
            valgrind
          ];
          # PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig"
          # LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with pkgs;[SDL2 SDL2_image stdenv.cc.cc.lib])}";
        };
      }
    );
}

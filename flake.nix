# flake.nix
{
  description = "Reusable NixOS/Home Manager library for declarative system configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    {
      nixpkgs,
      systems,
      ...
    }:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      # The main lib constructor - users call this with their inputs and root
      lib = import ./lib { inherit (nixpkgs) lib; };

      # Formatter for the lib itself
      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}

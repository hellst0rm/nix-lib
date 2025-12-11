# lib/packages.nix
#
# Package discovery and overlay utilities.
#
{
  lib,
  paths,
  pathFromRoot,
}:
rec {
  # Discover packages in directory
  discoverPackages =
    dir:
    let
      entries = if builtins.pathExists dir then builtins.readDir dir else { };
    in
    lib.attrsets.filterAttrs (
      name: type:
      (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"))
      || (name != "default.nix" && lib.strings.hasSuffix ".nix" name && type == "regular")
    ) entries;

  # Build package set from directory
  buildPackageSet =
    pkgs: dir:
    let
      packageDirs = discoverPackages dir;
      stripNixSuffix = name: if lib.hasSuffix ".nix" name then lib.removeSuffix ".nix" name else name;
    in
    lib.mapAttrs' (
      name: _type: lib.nameValuePair (stripNixSuffix name) (pkgs.callPackage (dir + "/${name}") { })
    ) packageDirs;

  # Import all packages from directory as an overlay
  mkOverlay =
    dir: final: _prev:
    buildPackageSet final dir;

  # Get default overlays from consumer's overlays directory
  mkDefaultOverlays =
    {
      inputs,
      customOverlays,
      customPaths,
    }:
    let
      overlaysPath = paths.overlays;
      # Build a lib with the custom functions accessible
      libWithCustom = lib // {
        nix-lib = {
          overlays = customOverlays;
          paths = customPaths;
          packages = { inherit buildPackageSet; };
        };
      };
    in
    if builtins.pathExists overlaysPath then
      lib.attrValues (
        import overlaysPath {
          inherit inputs;
          lib = libWithCustom;
        }
      )
    else
      [ ];

  # Combine default and custom overlays
  combineOverlays =
    {
      inputs,
      custom ? [ ],
    }:
    let
      customOverlayFns = {
        mkChannelOverlay = name: src: final: _prev: {
          ${name} = import src {
            inherit (final.stdenv.hostPlatform) system;
            config.allowUnfree = true;
            config.nvidia.acceptLicense = true;
          };
        };
      };
    in
    mkDefaultOverlays {
      inherit inputs;
      customOverlays = customOverlayFns;
      customPaths = paths;
    }
    ++ custom;

  # Build pkgs with overlays
  mkPkgs =
    {
      system,
      overlays ? [ ],
      inputs,
      extendedLib ? null,
    }:
    let
      # If extendedLib is provided, add an overlay to replace pkgs.lib with it
      libOverlay =
        if extendedLib != null then
          [
            (_final: _prev: {
              lib = extendedLib;
            })
          ]
        else
          [ ];
    in
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays =
        combineOverlays {
          inherit inputs;
          custom = overlays;
        }
        ++ libOverlay;
    };
}

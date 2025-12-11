# lib/modules.nix
#
# Module discovery and loading utilities.
#
{
  lib,
  inputs,
  paths,
  pathFromRoot,
}:
rec {
  # System utilities
  forEachSystem = f: lib.genAttrs (import inputs.systems) (system: f pkgsFor.${system});

  # Import overlays from consumer's overlays directory
  overlays =
    if builtins.pathExists paths.overlays then
      import paths.overlays { inherit inputs lib; }
    else
      { default = _: _: { }; };

  pkgsFor = lib.genAttrs (import inputs.systems) (
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ overlays.default ];
    }
  );

  # Scan directory for direct .nix files and subdirectories with default.nix
  scanModules =
    path:
    if !builtins.pathExists path then
      [ ]
    else
      builtins.map (f: (path + "/${f}")) (
        builtins.attrNames (
          lib.attrsets.filterAttrs (
            name: type:
            (type == "directory" && builtins.pathExists (path + "/${name}/default.nix"))
            || (name != "default.nix" && lib.strings.hasSuffix ".nix" name)
          ) (builtins.readDir path)
        )
      );

  # Recursively find all .nix files
  findModules =
    searchPaths:
    let
      expandPath =
        path:
        if !builtins.isPath path || builtins.readFileType path != "directory" then
          [ path ]
        else
          lib.filesystem.listFilesRecursive path;
    in
    lib.filter (elem: !builtins.isPath elem || lib.hasSuffix ".nix" (toString elem)) (
      lib.concatMap expandPath (lib.toList searchPaths)
    );

  # Recursive scan (uses findModules)
  scanModulesDeep = path: if !builtins.pathExists path then [ ] else findModules [ path ];

  # Import all modules from directory (non-recursive)
  importModules = dir: if !builtins.pathExists dir then [ ] else map import (scanModules dir);

  # Import all modules recursively
  importModulesDeep = searchPaths: map import (findModules searchPaths);

  # Safe import if path exists
  importIfExists = path: if builtins.pathExists path then [ path ] else [ ];
}

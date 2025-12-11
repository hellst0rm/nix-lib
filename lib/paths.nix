# lib/paths.nix
#
# Path utilities bound to a specific root directory.
#
{ lib, root }:
rec {
  relativeToRoot = lib.path.append root;
  pathFromRoot = relativeToRoot;
}

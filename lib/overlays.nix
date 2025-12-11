# lib/overlays.nix
#
# Overlay utility functions.
#
{ lib }:
{
  # Create channel overlay for accessing different nixpkgs versions
  mkChannelOverlay = name: src: final: _prev: {
    ${name} = import src {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
      config.nvidia.acceptLicense = true;
    };
  };
}

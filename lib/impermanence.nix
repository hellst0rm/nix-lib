# lib/impermanence.nix
#
# Helper functions for working with impermanence configurations.
#
{ lib }:
{
  # Helper to create a persistence directory configuration with proper structure
  # Usage: mkPersistDir "/var/lib/foo" "root" "root" "0755"
  mkPersistDir = path: user: group: mode: {
    directory = path;
    inherit user group mode;
  };

  # Helper to create a persistence file configuration
  # Usage: mkPersistFile "/etc/foo.conf" "root" "root" "0644"
  mkPersistFile = path: user: group: mode: {
    file = path;
    parentDirectory = {
      inherit user group mode;
    };
  };

  # Helper to add multiple directories to persistence with the same ownership
  # Usage: mkPersistDirs "root" "root" "0755" [ "/var/lib/foo" "/var/lib/bar" ]
  mkPersistDirs =
    user: group: mode: paths:
    map (path: {
      directory = path;
      inherit user group mode;
    }) paths;

  # Helper to safely extend persistence configuration
  extendPersistence =
    config:
    lib.mkMerge [
      {
        directories = [ ];
        files = [ ];
      }
      config
    ];

  # Helper to create home persistence configuration
  # Usage: mkHomePersistence username [ ".ssh" ".gnupg" ]
  mkHomePersistence = username: dirs: {
    "/persist/home/${username}" = {
      directories = dirs;
      allowOther = true;
    };
  };
}

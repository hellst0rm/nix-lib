# lib/builders.nix
#
# System and Home Manager configuration builders.
#
{
  lib,
  inputs,
  features,
  modules,
  packages,
  overlays,
  paths,
  pathFromRoot,
}:
let
  featuresLib = features;

  # Build the nix-config attrset that gets passed to all modules via specialArgs
  # This provides access to all custom lib functions in modules
  mkNixConfigAttr = {
    # Module utilities (flattened for convenience)
    inherit (modules) scanModules importModules importIfExists;

    # Feature system
    inherit features;

    # Impermanence helpers - will be added when impermanence is passed
    # inherit impermanence;

    # Package utilities (flattened for convenience)
    inherit (packages) buildPackageSet discoverPackages;

    # Overlay utilities (flattened for convenience)
    inherit (overlays) mkChannelOverlay;

    # Path utilities (flattened for convenience)
    inherit pathFromRoot;
  };
in
rec {
  # Build base specialArgs common to both NixOS and Home Manager
  mkBaseSpecialArgs =
    {
      inputs,
      extraSpecialArgs ? { },
    }:
    let
      inputsWithoutSelf = builtins.removeAttrs inputs [ "self" ];
    in
    {
      inputs = inputsWithoutSelf;
      # Pass nix-config to all modules
      nix-config = mkNixConfigAttr;
    }
    // extraSpecialArgs;

  # Build NixOS-specific specialArgs
  mkSystemSpecialArgs =
    {
      inputs,
      secrets ? null,
      extraSpecialArgs ? { },
    }:
    mkBaseSpecialArgs {
      inherit inputs extraSpecialArgs;
    }
    // (if secrets != null then { inherit secrets; } else { });

  # Build Home Manager-specific extraSpecialArgs
  mkHomeExtraSpecialArgs =
    {
      inputs,
      secrets ? null,
      extraSpecialArgs ? { },
    }:
    let
      inputsWithoutSelf = builtins.removeAttrs inputs [ "self" ];
    in
    {
      inputs = inputsWithoutSelf;
      # Pass nix-config to all modules
      nix-config = mkNixConfigAttr;
    }
    // (if secrets != null then { inherit secrets; } else { })
    // extraSpecialArgs;

  # Collect NixOS system modules
  mkSystemModules =
    {
      hostname,
      users,
      stateVersion,
      domain ? null,
      secrets ? null,
      featuresBasePath,
      enabledFeatures,
      overlays,
      extraModules ? [ ],
      standaloneHM ? true,
    }:
    let
      hostConfigDir = pathFromRoot "${paths.hostsDir}/${hostname}";
      hostConfigFile = hostConfigDir + "/default.nix";
      hostModules = if builtins.pathExists hostConfigFile then [ hostConfigFile ] else [ ];
      featureModules = featuresLib.resolveFeatureModules featuresBasePath enabledFeatures;

      # Home Manager as NixOS module (integrated mode)
      homeManagerModule =
        if !standaloneHM then
          [
            inputs.home-manager.nixosModules.home-manager
            (_: {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                verbose = true;
                extraSpecialArgs = {
                  inputs = builtins.removeAttrs inputs [ "self" ];
                  # Pass nix-config to integrated Home Manager modules
                  nix-config = mkNixConfigAttr;
                };
                users = builtins.listToAttrs (
                  map (user: {
                    name = user;
                    value = {
                      imports = [
                        (pathFromRoot "${paths.modulesDir}/home-manager")
                        {
                          userSpec = {
                            username = user;
                            inherit hostname stateVersion;
                            enabledFeatures = [ ];
                          };
                          home = {
                            username = user;
                            inherit stateVersion;
                            homeDirectory = if user == "root" then "/root" else "/home/${user}";
                          };
                          programs.home-manager.enable = true;
                        }
                      ]
                      ++ modules.importIfExists (pathFromRoot "${paths.homeDir}/${user}/${hostname}.nix");
                    };
                  }) users
                );
              };
            })
          ]
        else
          [ ];

      # Auto-configure user passwords from secrets
      sopsModule = if secrets != null then [ inputs.sops-nix.nixosModules.sops ] else [ ];

      userPasswordModule =
        if secrets != null && users != [ ] then
          [
            (
              { config, ... }:
              {
                sops.secrets = builtins.listToAttrs (
                  map (user: {
                    name = "${user}-password";
                    value = {
                      sopsFile = secrets + "/users/${user}/secrets.yaml";
                      key = "password";
                      neededForUsers = true;
                    };
                  }) users
                );

                users.users = builtins.listToAttrs (
                  map (user: {
                    name = user;
                    value = {
                      hashedPasswordFile = config.sops.secrets."${user}-password".path;
                    };
                  }) users
                );
              }
            )
          ]
        else
          [ ];

      # Disable root password if root is not in users list
      rootPasswordModule =
        if !(builtins.elem "root" users) then
          [
            {
              users.users.root.hashedPassword = "!";
            }
          ]
        else
          [ ];
    in
    [
      # Import the hostSpec module
      (pathFromRoot "${paths.modulesDir}/nixos")
      # Set hostSpec configuration
      {
        hostSpec = {
          inherit
            hostname
            users
            stateVersion
            domain
            enabledFeatures
            ;
        };
      }
      # Set traditional options from hostSpec
      {
        networking.hostName = hostname;
        system.stateVersion = stateVersion;
      }
      {
        nixpkgs.overlays = overlays;
        nixpkgs.config.allowUnfree = true;
      }
    ]
    ++ (if domain != null then [ { networking.domain = domain; } ] else [ ])
    ++ sopsModule
    ++ userPasswordModule
    ++ rootPasswordModule
    ++ hostModules
    ++ featureModules
    ++ homeManagerModule
    ++ extraModules;

  # Collect Home Manager modules
  mkHomeModules =
    {
      username,
      hostname,
      stateVersion,
      secrets ? null,
      featuresBasePath,
      enabledFeatures,
      overlays,
      extraModules ? [ ],
    }:
    let
      userConfigDir = pathFromRoot "${paths.homeDir}/${username}";
      userConfigFile = userConfigDir + "/default.nix";
      userModules = if builtins.pathExists userConfigFile then [ userConfigFile ] else [ ];
      featureModules = featuresLib.resolveFeatureModules featuresBasePath enabledFeatures;

      # Auto-configure user SSH key from secrets
      sopsModule = if secrets != null then [ inputs.sops-nix.homeManagerModules.sops ] else [ ];

      sshKeyModule =
        if secrets != null then
          [
            (
              { config, ... }:
              {
                sops.secrets."${username}-ssh-key" = {
                  sopsFile = secrets + "/users/${username}/secrets.yaml";
                  key = "ssh/private_key";
                  path = "${config.home.homeDirectory}/.ssh/id_ed25519";
                  mode = "0600";
                };
              }
            )
          ]
        else
          [ ];
    in
    [
      # Import the userSpec module
      (pathFromRoot "${paths.modulesDir}/home-manager")
      # Set userSpec configuration
      {
        userSpec = {
          inherit
            username
            hostname
            stateVersion
            enabledFeatures
            ;
        };
      }
      # Set traditional options from userSpec
      {
        home = {
          inherit username stateVersion;
          homeDirectory = if username == "root" then "/root" else "/home/${username}";
        };
        programs.home-manager.enable = true;
        nixpkgs.overlays = overlays;
      }
    ]
    ++ sopsModule
    ++ sshKeyModule
    ++ userModules
    ++ featureModules
    ++ extraModules;

  # System builder (thin wrapper)
  mkSystem =
    {
      hostname,
      users ? [ ],
      system ? "x86_64-linux",
      stateVersion ? "25.05",
      domain ? null,
      secrets ? null,
      features ? { },
      extraModules ? [ ],
      extraSpecialArgs ? { },
      overlays ? [ ],
      standaloneHM ? true,
    }:
    let
      featuresBasePath = paths.hostFeatures;
      featureSet = featuresLib.processFeatures features (
        featuresLib.mkFeatureSetFromDirs featuresBasePath
      );

      allOverlays = packages.combineOverlays {
        inherit inputs;
        custom = overlays;
      };

      specialArgs = mkSystemSpecialArgs {
        inherit inputs secrets extraSpecialArgs;
      };

      systemModules = mkSystemModules {
        inherit
          hostname
          users
          stateVersion
          domain
          secrets
          extraModules
          standaloneHM
          featuresBasePath
          ;
        enabledFeatures = featureSet.enabled;
        overlays = allOverlays;
      };
    in
    lib.nixosSystem {
      inherit system specialArgs;
      modules = systemModules;
    };

  # Home builder (thin wrapper)
  mkHome =
    {
      username,
      hostname,
      system ? "x86_64-linux",
      stateVersion ? "25.05",
      secrets ? null,
      features ? { },
      extraModules ? [ ],
      extraSpecialArgs ? { },
      overlays ? [ ],
    }:
    let
      featuresBasePath = paths.homeFeatures;
      featureSet = featuresLib.processFeatures features (
        featuresLib.mkFeatureSetFromDirs featuresBasePath
      );

      allOverlays = packages.combineOverlays {
        inherit inputs;
        custom = overlays;
      };
      pkgs = packages.mkPkgs {
        inherit system inputs;
        overlays = allOverlays;
        extendedLib = lib;
      };

      homeExtraSpecialArgs = mkHomeExtraSpecialArgs {
        inherit inputs secrets extraSpecialArgs;
      };

      homeModules = mkHomeModules {
        inherit
          username
          hostname
          stateVersion
          secrets
          extraModules
          featuresBasePath
          ;
        enabledFeatures = featureSet.enabled;
        overlays = allOverlays;
      };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = homeExtraSpecialArgs;
      modules = homeModules;
    };

  # Batch create multiple systems
  mkSystems = systemSpecs: lib.mapAttrs (_: mkSystem) systemSpecs;

  # Batch create multiple homes
  mkHomes = homeSpecs: lib.mapAttrs (_: mkHome) homeSpecs;

  # Utility to check if feature is enabled
  hasFeature = feature: enabledFeatures: lib.elem feature enabledFeatures;

  # Conditional module import based on feature
  withFeature =
    feature: module: enabledFeatures:
    lib.optional (hasFeature feature enabledFeatures) module;
}

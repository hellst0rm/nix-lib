# lib/features.nix
#
# Feature discovery and resolution for opt-in/opt-out feature system.
#
{ lib }:
rec {
  # Extract feature names recursively with path structure
  getFeatureNamesRecursive =
    basePath: prefix:
    let
      entries = if builtins.pathExists basePath then builtins.readDir basePath else { };

      stripNixSuffix = name: if lib.hasSuffix ".nix" name then lib.removeSuffix ".nix" name else name;

      buildFeatureName =
        name: if prefix == "" then stripNixSuffix name else "${prefix}/${stripNixSuffix name}";

      # Process files
      files = lib.attrsets.filterAttrs (
        name: type: type == "regular" && name != "default.nix" && lib.hasSuffix ".nix" name
      ) entries;

      fileFeatures = map buildFeatureName (builtins.attrNames files);

      # Process directories
      dirs = lib.attrsets.filterAttrs (
        name: type: type == "directory" && builtins.pathExists (basePath + "/${name}/default.nix")
      ) entries;

      dirFeatures = map buildFeatureName (builtins.attrNames dirs);

      # Recurse into directories
      nestedFeatures = lib.flatten (
        lib.mapAttrsToList (
          name: _: getFeatureNamesRecursive (basePath + "/${name}") (buildFeatureName name)
        ) dirs
      );
    in
    fileFeatures ++ dirFeatures ++ nestedFeatures;

  # Extract feature names from directory structure
  getFeatureNames = featuresDir: getFeatureNamesRecursive featuresDir "";

  # Build feature set from directory structure
  mkFeatureSetFromDirs =
    basePath:
    let
      defaultFeatures = getFeatureNames (basePath + "/default");
    in
    {
      default = defaultFeatures;
      opt-in = getFeatureNames (basePath + "/opt-in");
      opt-out = getFeatureNames (basePath + "/opt-out");
      enabled = defaultFeatures;
    };

  # Check if feature matches pattern (implicit wildcard)
  matchesPattern = pattern: feature: pattern == feature || lib.hasPrefix (pattern + "/") feature;

  # Check if feature exists in any category
  featureExists =
    featureSet: feature:
    let
      allFeatures = featureSet.default ++ featureSet.opt-in ++ featureSet.opt-out;
    in
    lib.any (f: matchesPattern feature f) allFeatures;

  # Process features with warnings for missing features
  processFeatures =
    {
      opt-in ? [ ],
      opt-out ? [ ],
    }:
    featureSet:
    let
      # Warn about missing opt-in features
      missingOptIn = lib.filter (f: !featureExists featureSet f) opt-in;
      missingOptOut = lib.filter (f: !featureExists featureSet f) opt-out;

      # Filter to only existing features
      validOptIn = lib.filter (f: featureExists featureSet f) opt-in;
      validOptOut = lib.filter (f: featureExists featureSet f) opt-out;

      # Add opt-in features and their nested children
      allFeatures = featureSet.opt-in ++ featureSet.opt-out ++ featureSet.default;
      withOptIn = lib.unique (
        featureSet.enabled
        ++ (lib.filter (f: lib.any (pattern: matchesPattern pattern f) validOptIn) allFeatures)
      );

      # Remove opt-out features and their nested children
      withOptOut =
        builtins.seq
          (lib.forEach missingOptIn (
            f: builtins.trace "WARNING: opt-in feature '${f}' not found in feature set, ignoring" null
          ))
          (
            builtins.seq (lib.forEach missingOptOut (
              f: builtins.trace "WARNING: opt-out feature '${f}' not found in feature set, ignoring" null
            )) (lib.filter (f: !lib.any (pattern: matchesPattern pattern f) validOptOut) withOptIn)
          );
    in
    featureSet // { enabled = withOptOut; };

  # Resolve feature path by checking default/opt-in/opt-out directories
  resolveFeaturePath =
    basePath: feature:
    let
      tryPaths = [
        (basePath + "/default/${feature}.nix")
        (basePath + "/default/${feature}/default.nix")
        (basePath + "/opt-in/${feature}.nix")
        (basePath + "/opt-in/${feature}/default.nix")
        (basePath + "/opt-out/${feature}.nix")
        (basePath + "/opt-out/${feature}/default.nix")
      ];
      validPaths = lib.filter builtins.pathExists tryPaths;
    in
    if validPaths == [ ] then
      throw "Feature '${feature}' not found in ${toString basePath}"
    else
      builtins.head validPaths;

  # Resolve multiple feature modules
  resolveFeatureModules = basePath: features: map (f: resolveFeaturePath basePath f) features;
}

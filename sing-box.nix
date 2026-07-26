{ config, lib, pkgs, user, ... }:

let
  templatePath = ./home/.config/sing-box/config.json;
  secretMap =
    builtins.fromJSON
      (builtins.readFile ./home/.config/sing-box/secrets-map.json);
  markers = builtins.attrNames secretMap;
  secretPaths = lib.unique (map (marker: secretMap.${marker}) markers);
  replacements =
    map (marker: config.sops.placeholder.${secretMap.${marker}}) markers;
  candidate = config.sops.templates.sing-box-candidate.path;
  stateDir = "/Users/${user}/.local/state/sing-box";
  finalConfig = "${stateDir}/config.json";
in
{
  sops = {
    defaultSopsFile = ./secrets/sing-box.yaml;
    defaultSopsFormat = "yaml";
    age = {
      keyFile = "/Users/${user}/Library/Application Support/sops/age/keys.txt";
      generateKey = false;
    };
    secrets = lib.genAttrs secretPaths (_: { });
    templates.sing-box-candidate = {
      content = builtins.replaceStrings
        markers
        replacements
        (builtins.readFile templatePath);
      path = "/run/secrets/rendered/sing-box-candidate.json";
      mode = "0400";
    };
  };

  system.activationScripts.postActivation.text = lib.mkOrder 2000 ''
    echo "validating sing-box configuration..."
    state_dir=${lib.escapeShellArg stateDir}
    final_config=${lib.escapeShellArg finalConfig}
    candidate=${lib.escapeShellArg candidate}

    ${pkgs.coreutils}/bin/install -d \
      -m 0700 \
      -o ${lib.escapeShellArg user} \
      -g staff \
      "$state_dir"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$state_dir/.config.json.XXXXXX")"
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.coreutils}/bin/install \
      -m 0600 \
      -o ${lib.escapeShellArg user} \
      -g staff \
      "$candidate" \
      "$tmp"
    ${pkgs.jq}/bin/jq -e . "$tmp" >/dev/null
    ${pkgs.sing-box}/bin/sing-box check -c "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$final_config"
    trap - EXIT
  '';
}

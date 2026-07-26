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

    ${pkgs.jq}/bin/jq -e . "$candidate" >/dev/null
    ${pkgs.sing-box}/bin/sing-box check -c "$candidate"
    ${pkgs.coreutils}/bin/cat "$candidate" \
      | /usr/bin/sudo -u ${lib.escapeShellArg user} -- \
          ${pkgs.bash}/bin/bash ${./scripts/publish-sing-box-config.sh} \
            "$state_dir" "$final_config" ${pkgs.coreutils}/bin
  '';
}

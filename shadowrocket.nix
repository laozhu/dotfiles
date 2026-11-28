{
  config,
  lib,
  pkgs,
  user,
  ...
}:

# Shadowrocket node share links, rendered from the same SOPS secrets as sing-box.nix
# (which declares them). The rules (.conf) are public and imported from GitHub.
let
  secretMap = builtins.fromJSON (builtins.readFile ./home/.config/sing-box/secrets-map.json);
  markers = builtins.attrNames secretMap;
  replacements = map (marker: config.sops.placeholder.${secretMap.${marker}}) markers;
  # The checker imports the sing-box renderer, so both files must share a directory.
  checkerDir = lib.fileset.toSource {
    root = ./scripts;
    fileset = lib.fileset.unions [
      ./scripts/shadowrocket-config.mjs
      ./scripts/render-sing-box-config.mjs
    ];
  };
in
{
  sops.templates.shadowrocket-nodes-candidate = {
    content = builtins.replaceStrings markers replacements (
      builtins.readFile ./home/.config/shadowrocket/nodes.txt
    );
    path = "/run/secrets/rendered/shadowrocket-nodes-candidate";
    owner = user;
    group = "staff";
    mode = "0400";
  };

  system.activationScripts.postActivation.text = lib.mkOrder 2001 ''
    echo "validating Shadowrocket node links..."
    /usr/bin/sudo -u ${lib.escapeShellArg user} -- \
      ${pkgs.bash}/bin/bash ${./scripts/publish-shadowrocket-config.sh} \
        ${lib.escapeShellArg "/Users/${user}/.local/state/shadowrocket"} \
        ${lib.escapeShellArg config.sops.templates.shadowrocket-nodes-candidate.path} \
        ${./home/.config/shadowrocket/shadowrocket.conf} \
        ${pkgs.coreutils}/bin \
        ${pkgs.nodejs_26}/bin/node \
        ${checkerDir}/shadowrocket-config.mjs
  '';
}

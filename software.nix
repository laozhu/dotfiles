# One catalog supplies both installation declarations and the read-only inventory.
{ lib, profile }:
let
  catalog = builtins.fromJSON (builtins.readFile ./software.json);
  selected = builtins.filter (item: item.group == "shared" || item.group == profile) catalog;
  packagesFor =
    manager:
    map (item: item.package) (
      builtins.filter (item: item.manager == manager && item ? package) selected
    );
in
assert builtins.elem profile [
  "home"
  "work"
];
{
  brews = packagesFor "Homebrew";
  casks = packagesFor "Homebrew Cask";
  packages =
    pkgs: agents:
    map (name: lib.attrByPath (lib.splitString "." name) (throw "Unknown package ${name}") pkgs) (
      packagesFor "Nix"
    )
    ++ map (name: agents.${name}) (packagesFor "llm-agents.nix");
}

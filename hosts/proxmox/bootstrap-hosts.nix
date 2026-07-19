# Map sticky bootstrap IP → hostname "server0" for join URLs that still use the name.
# Import from agent / joining control-plane hosts when settings.bootstrapHost is an IPv4.
{ lib, ... }:
let
  settings = import ./settings.nix;
  bootstrapIsIp =
    builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" settings.bootstrapHost != null;
in
{
  networking.extraHosts = lib.mkIf bootstrapIsIp ''
    ${settings.bootstrapHost} server0
  '';
}

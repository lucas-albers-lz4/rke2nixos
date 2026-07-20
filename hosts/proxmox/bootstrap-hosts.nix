# Map sticky bootstrap IP → bootstrap hostname for join URLs that still use the name.
# Import from agent / joining control-plane hosts when bootstrapHost is an IPv4.
{
  lib,
  bootstrapHost,
  bootstrapName ? "server0",
}:
let
  bootstrapIsIp = builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" bootstrapHost != null;
in
{
  networking.extraHosts = lib.mkIf bootstrapIsIp ''
    ${bootstrapHost} ${bootstrapName}
  '';
}

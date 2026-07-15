# install Nix, then:
cd ~/gitroot/rke2nixos
nix flake update
nix flake show
nix build .#checks.x86_64-linux.server-agent   # needs a Linux builder

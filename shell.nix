# The legacy entrypoint delegates to the locked flake's exact dependency/Qt set.
# Enable flakes in Nix (or pass --extra-experimental-features 'nix-command flakes').
(builtins.getFlake (toString ./.)).devShells.${builtins.currentSystem}.default

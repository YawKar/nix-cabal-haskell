{
  description = "nix-cabal-haskell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.git-hooks-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        let
          # Nix only provides the toolchain; cabal resolves Haskell dependencies.
          # After bumping, run `just freeze`: cabal.project.freeze pins GHC's
          # built-in libraries (base, ...), so a stale one fails to resolve.
          # Also bump the GHC image in static/Containerfile for `just build-static`.
          ghcVersion = "ghc910";
          hpkgs = pkgs.haskell.packages.${ghcVersion};

          # Tools that must match the project GHC (ghc itself is added per shell:
          # with a Hoogle database for development, plain for CI).
          toolchain = [
            pkgs.cabal-install
            hpkgs.doctest # uses the GHC API, so it must match ghcVersion
          ];
          languageservers = [ hpkgs.haskell-language-server ];

          # Tools that don't depend on the project GHC.
          runners = with pkgs; [ just ];
          formatters = with pkgs; [
            nixfmt
            yamlfmt
            fourmolu
            haskellPackages.cabal-fmt
          ];
          linters = with pkgs; [
            statix
            hlint
          ];
          # Viewers for `just core/asm` and `just prof-*`; they read files,
          # so they don't need to match ghcVersion.
          inspectors = with pkgs; [
            bat
            haskellPackages.profiteur
            haskellPackages.eventlog2html
            haskellPackages.threadscope
          ];

          # Runs the justfile recipe with its tools pinned, so the hook works
          # outside the dev shell too (IDE commits, plain `git commit`).
          codeStyleHook = pkgs.writeShellApplication {
            name = "code-style-hook";
            runtimeInputs = runners ++ formatters ++ linters;
            text = "just pre-commit-hook";
          };
        in
        {
          pre-commit = {
            # CI runs the justfile recipes as separate steps instead.
            check.enable = false;
            settings.hooks.code-style = {
              enable = true;
              name = "code style";
              entry = lib.getExe codeStyleHook;
              pass_filenames = false;
            };
          };

          devShells.default = pkgs.mkShell {
            name = "nix-cabal-haskell-devenv";
            packages =
              let
                flakeMachinery = with pkgs; [ bashInteractive ];
                repoMachinery = [ config.pre-commit.settings.package ];
              in
              flakeMachinery
              ++ repoMachinery
              ++ [ (hpkgs.ghcWithHoogle (_: [ ])) ]
              ++ toolchain
              ++ languageservers
              ++ runners
              ++ formatters
              ++ linters
              ++ inspectors;

            shellHook = ''
              ${config.pre-commit.installationScript}
              echo "[FLAKE] DevShell for nix-cabal-haskell is loaded!"
            '';
          };

          # Only what `just ci` needs: no language server, Hoogle or viewers, and no git hooks.
          devShells.ci = pkgs.mkShell {
            name = "nix-cabal-haskell-ci";
            packages = [ hpkgs.ghc ] ++ toolchain ++ runners ++ formatters ++ linters;
          };
        };
    };
}

{
  description = "Keystone dev environment";

  nixConfig = {
    allow-import-from-derivation = true;
    extra-substituters = ["https://nix-community.cachix.org"];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    sandbox = "relaxed";
    use-registry = false;
  };

  outputs = {
    fenix,
    flake-utils,
    nixpkgs,
    pyproject,
    self,
    systems,
  }:
    flake-utils.lib.eachSystem (import systems) (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      apps =
        builtins.mapAttrs (_: drv: flake-utils.lib.mkApp {inherit drv;}) self.packages.${system};

      packages = let
        simulator = import ./nix/packages/simulator.nix {
          inherit (nixpkgs) lib;
          inherit fenix pkgs pyproject;
        };
      in
        {default = self.packages.${system}.multi-coins-simulator;}
        // nixpkgs.lib.mapAttrs'
        (name: arg: nixpkgs.lib.nameValuePair "${name}-simulator" (simulator name arg))
        ## These are the `FEATURE_VARIANT`s from ./rust/CMakeLists.txt.
        {
          btc-only = "btc_only";
          cypherpunk = "cypherpunk";
          multi-coins = "general";
        };

      devShells.default = pkgs.mkShell {
        inputsFrom = nixpkgs.lib.attrValues self.packages.${system};
        packages = [
          pkgs.alejandra
          pkgs.rust-analyzer
        ];
        ## TODO: This is because we can’t bypass a submodule with the flake’s
        ##       `submodules = true`.
        shellHook = ''
          ${nixpkgs.lib.getExe pkgs.git} \
            -c submodule.keystone3-firmware-release.update=none \
            submodule update --init --recursive
        '';
      };

      formatter = pkgs.alejandra;
    });

  inputs = {
    fenix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/fenix";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    pyproject = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:pyproject-nix/pyproject.nix";
    };
    ## FIXME: Currently need to manually update the submodules (see NixOS/nix#14245).
    ##     > git -c submodule.keystone3-firmware-release.update=none submodule update --init --recursive
    # self.submodules = true; # ["external/ctaes" "rust-crypto-core"];
    systems.follows = "flake-utils/systems";
  };
}

{
  fenix,
  lib,
  pkgs,
  pyproject,
}: let
  projectRoot = ../..;
  ## Read Python environment from requirements.txt.
  pythonEnv =
    pkgs.python3.withPackages
    ((pyproject.lib.project.loadRequirementsTxt {inherit projectRoot;}).renderers.withPackages {
      python = pkgs.python3;
    });
  ## Read Rust environment from rust-toolchain.
  ##
  ## TODO: I think this can only build for the simulator, because `thumbv7em-none-eabihf` is not
  ##       a supported target for Fenix.
  rustEnv = fenix.packages.${pkgs.system}.fromToolchainFile {
    file = "${projectRoot}/rust-toolchain";
    sha256 = "yN9i4c4NJ69YywO3PxRJ/HtB5IWjDUzH/UWSOSLq29A=";
  };
in
  name: firmware: let
    pname = "keystone-${name}-simulator";
  in
    pkgs.stdenv.mkDerivation {
      inherit pname;
      version = "2.2.14";
      src = projectRoot;

      ## This can’t be sandboxed, because it uses Cargo to fetch dependencies.
      __noChroot = true;

      buildInputs =
        [pkgs.SDL2]
        ++ lib.optional pkgs.stdenv.isLinux pkgs.xorg.libxcb;

      nativeBuildInputs = [
        pkgs.cacert ## SSL certificates (wouldn’t need if this were sandboxed)
        pkgs.cmake
        pkgs.makeWrapper
        pythonEnv
        rustEnv
      ];
      # ## This contains the `codesign` utility.
      # ++ lib.optional pkgs.stdenv.isDarwin pkgs.darwin.security_systemkeychain;

      patches = [
        ## TODO: This should only apply to the C build, I think.
        ./reformat-darwin-settings.patch
        ## TODO: Split this patch – I _think_ some of it only affects the Rust, and other parts only
        ##       affect the C, so if we adopt cargo2nix or something, it would be good to apply only
        ##       the relevant parts to each package.
        ./nix-only.patch
      ];

      LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.xorg.libxcb];
      
      dontConfigure = true;

      buildPhase = ''
        echo ==============================
        echo $LD_LIBRARY_PATH
        echo ==============================
        runHook preBuild
        ## Since it calls Cargo directly, we have to give it someplace to put everything.
        CARGO_HOME=$TMPDIR/.cargo \
          python3 build.py --options simulator --type ${lib.escapeShellArg firmware}
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/bin"
        cp build/simulator "$out/bin/${pname}"
        mkdir -p "$out/share/ui_simulator"
        cp -r ui_simulator/assets "$out/share/ui_simulator"
        runHook postInstall
      '';

      postFixup = ''
        ## So it sees ui_simulator/ in the package, rather than looking for it in the directory it
        ## was run from.
        wrapProgram "$out/bin/${pname}" --chdir "$out/share"
      '';

      meta.mainProgram = pname;
    }

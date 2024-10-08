{
  description = "clevor's packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    llvm-ez80 = {
      url = "github:jacobly0/llvm-project";
      flake = false;
    };
    toolchain = {
      flake = false;
      type = "git";
      url = "https://github.com/CE-Programming/toolchain";
      submodules = true;
    };
    convbin = {
      flake = false;
      type = "git";
      url = "https://github.com/mateoconlechuga/convbin";
      submodules = true;
    };
    decbot4Src = {
      url = "gitlab:cemetech/decbot4";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, llvm-ez80, toolchain, convbin, self, decbot4Src, flake-utils }@inputs:
    nixpkgs.lib.recursiveUpdate (flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system:
      let pkgsSelf = self.packages.${system}; in
    with import nixpkgs { inherit system; }; {
      templates.ce-toolchain = {
        path = ./template;
        description = "A Hello World program for the TI-84 Plus CE";
      };
      packages = {
        fasmg-patch = pkgs.fasmg.overrideAttrs (final: old: {
          version = "kd3c";
          src = fetchzip {
            url = "https://flatassembler.net/fasmg.${final.version}.zip";
            sha256 = "sha256-duxune/UjXppKf/yWp7y85rpBn4EIC6JcZPNDhScsEA=";
            stripRoot = false;
          };
        });
        convbin-unstable = pkgs.convbin.overrideAttrs {
          src = inputs.convbin;
          version = "unstable";
        };
        llvm-ez80 = stdenv.mkDerivation (final: {
          pname = "llvm-ez80";
          version = "0-unstable";

          src = llvm-ez80;

          configurePhase = ''
            mkdir build
            cd build
            cmake ../llvm -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD= -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Z80
            cd ..
          '';

          buildPhase = ''
            cd build
            cmake --build . --target clang llvm-link -j $NIX_BUILD_CORES
            cd ..
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp build/bin/clang $out/bin/ez80-clang
            cp build/bin/llvm-link $out/bin/ez80-link
          '';

          meta = {
            description = "A compiler and linker for (e)Z80 targets.";
            longDescription = ''
              This package provides a compiler and linker for (e)Z80 targets
              based on the LLVM toolchain.
              Originally designed for the TI-84 Plus CE, this also works for the Agon Light.

              This does not provide fasmg or any include files to build the programs.
              Please install a toolchain, such as the CE C toolchain.
            '';
            homepage = "https://github.com/jacobly0/llvm-project";
            license = lib.licenses.asl20-llvm;
            maintainers = with lib.maintainers; [ clevor ];
            platforms = lib.platforms.unix;
          };

          doCheck = false;

          nativeBuildInputs = [ cmake python3 ];
        });
        ce-libs = pkgsSelf.ce-toolchain.overrideAttrs {
          name = "clibs.8xg";
          postBuild = ''
            make libs $makeFlags
          '';
          installPhase = ''
            cp clibs.8xg $out
          '';
        };
        ce-toolchain = stdenv.mkDerivation {
          src = toolchain;
          name = "ce-toolchain";
          patchPhase = ''
            substituteInPlace src/common.mk --replace-fail \
              "INSTALL_DIR := \$(DESTDIR)\$(PREFIX)" "INSTALL_DIR := $out"
            substituteInPlace makefile --replace-fail \
              "TOOLS := fasmg convbin convimg convfont cedev-config" \
              "TOOLS := fasmg cedev-config" --replace-fail \
              "	\$(Q)\$(call COPY,\$(call NATIVEEXE,tools/convfont/convfont),\$(INSTALL_BIN))
          	\$(Q)\$(call COPY,\$(call NATIVEEXE,tools/convimg/bin/convimg),\$(INSTALL_BIN))
          	\$(Q)\$(call COPY,\$(call NATIVEEXE,tools/convbin/bin/convbin),\$(INSTALL_BIN))" "" \
              --replace-fail "tools/convbin/bin/" ""
            substituteInPlace tools/convimg/Makefile tools/cedev-config/Makefile \
              --replace-fail "-static" ""
            substituteInPlace src/makefile.mk \
              --replace-fail "\$(call NATIVEPATH,\$(BIN)/fasmg)" "${pkgsSelf.fasmg-patch}/bin/fasmg" \
              --replace-fail "\$(call NATIVEPATH,\$(BIN)/convbin)" "${pkgsSelf.convbin-unstable}/bin/convbin" \
              --replace-fail "\$(call NATIVEPATH,\$(BIN)/convimg)" "${convimg}/bin/convimg" \
              --replace-fail "\$(call NATIVEPATH,\$(BIN)/cemu-autotester)" "cemu-autotester" \
              --replace-fail "\$(call NATIVEPATH,\$(BIN)/ez80-clang)" "${pkgsSelf.llvm-ez80}/bin/ez80-clang" \
              --replace-fail "\$(call NATIVEPATH,\$(BIN)/ez80-link)" "${pkgsSelf.llvm-ez80}/bin/ez80-link" \
              --replace-fail "CONVBINFLAGS += -b \$(call QUOTE_ARG,\$(COMMENT))" ""
          '';
          doCheck = true;
          enableParallelBuilding = true;

          buildInputs = with pkgs; [
            convimg convfont
            pkgsSelf.llvm-ez80
            pkgsSelf.fasmg-patch
            pkgsSelf.convbin-unstable
          ];
          meta = {
            description = "Toolchain and libraries for C/C++ programming on the TI-84+ CE calculator series ";
            maintainers = with lib.maintainers; [ clevor ];
            mainProgram = "cedev-config";
            platforms = [ "x86_64-linux" "x86_64-darwin" ];
          };
        };
        mkDerivation = attrs: stdenv.mkDerivation (attrs // {
          buildPhase = if attrs? buildPhase then attrs.buildPhase else ''
            runHook preBuild
            make gfx $makeFlags || true
            make $makeFlags
            runHook postBuild
          '';
          enableParallelBuilding = true;
          installPhase = if attrs ? installPhase then attrs.installPhase else ''
            runHook preInstall
            mkdir -p $out/
            cp *.8x* */*.8x* */*/*.8x* */*/*/*.8x* $out/
            cp README* readme* license* LICENSE* LISEZMOI* lisezmoi* $out
            runHook postInstall
          '';
          nativeBuildInputs = let
            toolchain = with pkgsSelf; [
              ce-toolchain
              convbin-unstable
              pkgs.convimg
              pkgs.convfont
              pkgsSelf.llvm-ez80
              fasmg
            ];
          in
            if attrs ? nativeBuildInputs then attrs.nativeBuildInputs ++ toolchain else toolchain;
        });
      };
    })) (flake-utils.lib.eachDefaultSystem (system: with import nixpkgs { inherit system; }; {
      packages.decbot4 = buildDotnetModule rec {
        name = "decbot4";
        src = "${decbot4Src}/Cemetech.DecBot4";
        patchPhase = ''
          substituteInPlace Program.cs --replace-fail "decbot.json" "$out/lib/decbot.json"
        '';
        selfContainedBuild = true;
        dotnet-sdk = dotnetCorePackages.sdk_8_0;
        dotnet-runtime = dotnetCorePackages.runtime_8_0;
        nugetDeps = ./decbot4-deps.nix;
        meta.mainProgram = "Cemetech.DecBot4.ConsoleApp";
      };
    }));
}

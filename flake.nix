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
  };

  outputs = { nixpkgs, llvm-ez80, toolchain, convbin, self }@inputs: let pkgsSelf = self.packages.x86_64-linux; in
    with import nixpkgs { system = "x86_64-linux"; }; {
      templates.ce-toolchain = {
        path = ./template;
        description = "A Hello World program for the TI-84 Plus CE";
      };
      packages.x86_64-linux = {
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
          	\$(Q)\$(call COPY,\$(call NATIVEEXE,tools/convbin/bin/convbin),\$(INSTALL_BIN))" ""
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
          installPhase = if attrs ? installPhase then attrs.installPhase else ''
            runHook preInstall
            mkdir -p $out/
            cp --recursive bin $out
            runHook postInstall
          '';
          nativeBuildInputs = with pkgsSelf; [ ce-toolchain ];
        });
      };
    };
}

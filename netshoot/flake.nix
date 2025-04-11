{
  description = "foMM Netshoot image";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
    }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f system);
      imageName = "fomm/netshoot";
      imageTag = "1.0.2";
      mkDockerImage =
        pkgs: targetSystem:
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";
        in
        pkgs.dockerTools.buildLayeredImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
          enableFakechroot = true;
          fakeRootCommands = ''
            mkdir -p /data
            mkdir -p /.config/helix
            mkdir -p /.config/micro
            echo 'DISABLE_AUTO_UPDATE=true' | cat - ${pkgs.oh-my-zsh}/share/oh-my-zsh/templates/zshrc.zsh-template > /.zshrc
            # Remove omz git plugin
            sed -i 's/git//g' /.zshrc

            cat >> /.zshrc << EOF
            source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
            source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
            source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
            POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
            EOF

            cat > /.config/helix/config.toml << EOF
            theme = "rose_pine_moon"
            [editor]
            bufferline = "multiple"
            color-modes = true
            cursorline = true
            idle-timeout = 0
            true-color = true

            [editor.cursor-shape]
            insert = "bar"
            normal = "block"
            select = "block"

            [editor.soft-wrap]
            enable = true
            wrap-indicator = ""

            [editor.statusline]
            center = ["position-percentage"]

            [editor.whitespace.characters]
            newline = "↴"
            tab = "⇥"
            EOF

            cat > /.config/micro/settings.json << EOF
            {
              "clipboard": "external",
              "colorscheme": "monokai-dark",
              "mkparents": true,
              "softwrap": true,
              "tabmovement": true,
              "tabsize": 2,
              "tabstospaces": true
            }
            EOF
          '';
          contents = with pkgs; [
            unixtools.ping
            busybox
            libiconvReal
            helix
            jq
            xh
            curl
            dig
            openssl
            micro
          ];
          config = {
            EntryPoint = [ "${pkgs.zsh}/bin/zsh" ];
            WorkingDir = "/data";
            Env = [
              "USER=root"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "TZDIR=${pkgs.tzdata}/share/zoneinfo"
            ];
            Volumes = {
              "/data" = { };
            };
          };
        };
    in
    {
      packages = forEachSupportedSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          buildForLinux =
            targetSystem:
            if system == targetSystem then
              mkDockerImage pkgs targetSystem
            else
              mkDockerImage (import nixpkgs {
                localSystem = system;
                crossSystem = targetSystem;
              }) targetSystem;
        in
        {
          "amd64" = buildForLinux "x86_64-linux";
          "arm64" = buildForLinux "aarch64-linux";
        }
      );
      apps = forEachSupportedSystem (system: {
        default = {
          type = "app";
          program = toString (
            nixpkgs.legacyPackages.${system}.writeScript "build-and-load-multi-arch" ''
              #!${nixpkgs.legacyPackages.${system}.bash}/bin/bash
              set -e
              echo "Building x86_64-linux image..."
              nix build .#amd64 --out-link result-${system}-amd64
              echo "Building aarch64-linux image..."
              nix build .#arm64 --out-link result-${system}-arm64
              echo "Loading and pushing new images:"
              docker load < result-${system}-amd64
              docker load < result-${system}-arm64
              docker push ${imageName}:${imageTag}-amd64
              docker push ${imageName}:${imageTag}-arm64

              echo "Removing any existing manifest (safe cleanup)..."
              docker manifest rm ${imageName}:${imageTag} || true
              docker manifest rm ${imageName}:latest || true

              echo "Creating new multi-arch ${imageTag} manifest..."
              docker manifest create ${imageName}:${imageTag} \
                ${imageName}:${imageTag}-amd64 \
                ${imageName}:${imageTag}-arm64
              docker manifest annotate ${imageName}:${imageTag} ${imageName}:${imageTag}-amd64 --arch amd64
              docker manifest annotate ${imageName}:${imageTag} ${imageName}:${imageTag}-arm64 --arch arm64
              docker manifest push ${imageName}:${imageTag}

              echo "Creating new multi-arch latest manifest..."
              docker manifest create ${imageName}:latest \
                ${imageName}:${imageTag}-amd64 \
                ${imageName}:${imageTag}-arm64
              docker manifest annotate ${imageName}:latest ${imageName}:${imageTag}-amd64 --arch amd64
              docker manifest annotate ${imageName}:latest ${imageName}:${imageTag}-arm64 --arch arm64
              docker manifest push ${imageName}:latest
            ''
          );
        };
      });
    };
}

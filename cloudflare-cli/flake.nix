{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
    }:
    let
      lib = nixpkgs.lib;

      forEachSupportedSystem = f: lib.genAttrs (import systems) (system: f system);
      imageName = "fomm/cloudflare-cli";
      imageTag = "4.2.0";

      mkDockerImage =
        pkgs: targetSystem:
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";
          cfcli = pkgs.callPackage ./default.nix { };
        in
        pkgs.dockerTools.buildLayeredImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
          contents = [ cfcli ];
          config = {
            Entrypoint = [ "cfcli" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

      mkPackages =
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
        };
    in
    {
      packages = forEachSupportedSystem (system: mkPackages system);

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

              echo "Creating multi-arch manifest:"
              docker manifest push --purge ${imageName}:${imageTag}
              docker manifest push --purge ${imageName}:latest
              docker manifest create ${imageName}:${imageTag} ${imageName}:${imageTag}-amd64 ${imageName}:${imageTag}-arm64
              docker manifest annotate ${imageName}:${imageTag} ${imageName}:${imageTag}-amd64 --arch amd64
              docker manifest annotate ${imageName}:${imageTag} ${imageName}:${imageTag}-arm64 --arch arm64
              docker manifest create ${imageName}:latest ${imageName}:${imageTag}-amd64 ${imageName}:${imageTag}-arm64
              docker manifest annotate ${imageName}:latest ${imageName}:${imageTag}-amd64 --arch amd64
              docker manifest annotate ${imageName}:latest ${imageName}:${imageTag}-arm64 --arch arm64

              echo "Push multi-arch manifest:"
              docker manifest push ${imageName}:${imageTag}
              docker manifest push ${imageName}:latest
            ''
          );
        };
      });
    };
}

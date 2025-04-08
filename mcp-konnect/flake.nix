{
  description = "flake to build docker image for Kong konnect MCP";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f system);
      imageName = "fomm/mcp-konnect";
      imageTag = "latest";
      
      buildKonnectMCP = pkgs:
        pkgs.buildNpmPackage {
          name = "mcp-konnect";
          src = pkgs.fetchFromGitHub {
            owner = "Kong";
            repo = "mcp-konnect";
            rev = "main"; 
            hash = "sha256-k2c3ajcCZdbXZVwHgL02VwPbEAC6CaPB3fhXUIHivoQ=";
          };
          
          npmDepsHash = "sha256-Gpj0tSZdeKFzz9mHIYuVPUO5Kd9IH6YVHXsL7xEUWh0=";
          
          buildInputs = [ pkgs.nodejs ];
          
          buildPhase = ''
            npm run build
          '';
          
          installPhase = ''
            mkdir -p $out
            cp -r build $out/
            cp -r node_modules $out/
            cp package.json $out/
          '';
        };

      mkDockerImage = pkgs: targetSystem: 
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";
          mcpApp = buildKonnectMCP pkgs;
        in
        pkgs.dockerTools.buildImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
          
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [
              mcpApp
              pkgs.nodejs
            ];
            pathsToLink = [ "/bin" "/build" "/node_modules" ];
          };
          
          config = {
            Cmd = [ "${pkgs.nodejs}/bin/node" "/build/index.js" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "TZDIR=${pkgs.tzdata}/share/zoneinfo"
            ];
            WorkingDir = "/";
          };
        };
    in
    {
      packages = forEachSupportedSystem (
        system:
        let
          pkgs = import nixpkgs { 
            inherit system; 
            config = {
              allowUnfree = true;
            };
          };

          buildForLinux =
            targetSystem:
            if system == targetSystem then
              mkDockerImage pkgs targetSystem
            else
              mkDockerImage (import nixpkgs {
                localSystem = system;
                crossSystem = targetSystem;
                config = {
                  allowUnfree = true;
                };
              }) targetSystem;
        in
        {
          "amd64" = buildForLinux "x86_64-linux";
          "arm64" = buildForLinux "aarch64-linux";
          default = buildForLinux system;
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

              echo "Creating multi-arch manifest:"
              docker manifest push --purge ${imageName}:${imageTag}
              docker manifest create ${imageName}:${imageTag} ${imageName}:${imageTag}-amd64 ${imageName}:${imageTag}-arm64
              docker manifest annotate ${imageName}:${imageTag} ${imageName}:${imageTag}-amd64 --arch amd64
              docker manifest annotate ${imageName}:${imageTag} ${imageName}:${imageTag}-arm64 --arch arm64

              echo "Push multi-arch manifest:"
              docker manifest push ${imageName}:${imageTag}
              docker manifest push ${imageName}:latest
            ''
          );
        };
      });
    };
}
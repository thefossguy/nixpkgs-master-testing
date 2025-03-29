{
  description = "CI testing for prathams-nixos using the master branch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    prathams-nixos = {
      url = "github:thefossguy/prathams-nixos/master";
      inputs = {
        nixpkgsStable.follows = "nixpkgs";
        nixpkgsStableSmall.follows = "nixpkgs";
        nixpkgsUnstable.follows = "nixpkgs";
        nixpkgsUnstableSmall.follows = "nixpkgs";
      };
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      prathams-nixos,
      ...
    }:
    let
      lib = nixpkgs.lib;
      mkForEachSupportedSystem =
        supportedSystems: f:
        lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs { inherit system; };
          }
        );

      linuxSystems = {
        aarch64 = "aarch64-linux";
        riscv64 = "riscv64-linux";
        x86_64 = "x86_64-linux";
      };

      darwinSystems = {
        aarch64 = "aarch64-darwin";
        x86_64 = "x86_64-darwin";
      };

      supportedLinuxSystems = builtins.attrValues linuxSystems;
      supportedDarwinSystems = builtins.attrValues darwinSystems;
      supportedUnixSystems = supportedLinuxSystems ++ supportedDarwinSystems;

      forEachSupportedLinuxSystem = mkForEachSupportedSystem supportedLinuxSystems;
      forEachSupportedDarwinSystem = mkForEachSupportedSystem supportedDarwinSystems;
      forEachSupportedUnixSystem = mkForEachSupportedSystem supportedUnixSystems;

      zeInputs = builtins.map (name: "all_flake_inputs['${name}'] = '${prathams-nixos.inputs.${name}}'") (
        builtins.attrNames prathams-nixos.inputs
      );

    in
    prathams-nixos.outputs
    // {
      appsOverlay = forEachSupportedUnixSystem (
        { pkgs, system, ... }:
        {
          assertNixpkgsInputsPointToMaster = "${pkgs.writeScript "assert-nixpkgs-inputs-point-to-master.py" ''
            #!${pkgs.python3}/bin/python3

            import sys

            all_flake_inputs = {}
            ${builtins.concatStringsSep "\n" zeInputs}
            all_flake_inputs['master_nixpkgs'] = '${nixpkgs}'

            if __name__ == '__main__':
              for ze_key in all_flake_inputs:
                if not ze_key.startswith('nixpkgs'):
                  print('Skipped input `inputs.prathams-nixos.{}`'.format(ze_key))
              print()

              exit_code=0
              mismatched_inputs = []
              for ze_key in all_flake_inputs:
                if ze_key.startswith('nixpkgs'):
                  print('Checking input `inputs.prathams-nixos.{}`'.format(ze_key))
                  if not all_flake_inputs[ze_key] == all_flake_inputs['master_nixpkgs']:
                    mismatched_inputs.append("--------------------------------------------------------------------------------\nERROR: {} != {}\nERROR: `inputs.prathams-nixos.{}` != `nixpkgs`".format(all_flake_inputs[ze_key], all_flake_inputs['master_nixpkgs'], ze_key))
                    exit_code=1
              print()

              for mismatched_input in mismatched_inputs:
                print(mismatched_input)
              print('--------------------------------------------------------------------------------')
              sys.exit(exit_code)
          ''}";

          runPrathamsNixOSCI = "${pkgs.writeScript "run-prathams-nixos-ci.sh" ''
            #!${pkgs.bash}/bin/bash
            set -xeuf -o pipefail

            PATH=${pkgs.nix}/bin:$PATH
            export PATH

            ${pkgs.coreutils-full}/bin/timeout 1h \
                ${pkgs.python3}/bin/python3 ${prathams-nixos.outPath}/scripts/nix-ci/builder.py \
                --nixosConfigurations --homeConfigurations --devShells --packages
          ''}";
        }
      );
    };
}

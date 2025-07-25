{

  # https://github.com/pyproject-nix/uv2nix

  description = "a uv2nix devshell";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = {
    nixpkgs,
    pyproject-build-systems,
    pyproject-nix,
    uv2nix,
    ...
  }:
  let

    venvName = "venv";
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    python = pkgs.python313;


    # build system overrides for problem libraries
    # see also:
    #   - https://pyproject-nix.github.io/uv2nix/patterns/overriding-build-systems.html
    #   - https://github.com/pyproject-nix/uv2nix/issues/117
    pyprojectOverrides = final: prev:
    let
      inherit (final) resolveBuildSystem;
      inherit (builtins) mapAttrs;

      overrides = {
        pyperclip = { setuptools = []; };
      };

    in
      mapAttrs ( name: spec:
        prev.${name}.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ resolveBuildSystem spec;
        })
      ) overrides;


    # build the venv
    workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
    overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

    baseSet = pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    };

    pythonSet = baseSet.overrideScope (
      pkgs.lib.composeManyExtensions [
        pyproject-build-systems.overlays.default
        overlay
        pyprojectOverrides
      ]
    );

    venv = pythonSet.mkVirtualEnv "${venvName}" workspace.deps.default;

  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {

      packages = [ pkgs.uv venv ];

      env = {
        UV_NO_SYNC = "1";
        UV_PYTHON = "${venv}/bin/python";
        UV_PYTHON_DOWNLOADS = "never";
        VIRTUAL_ENV = "${venv}";
        VENV_NAME = "${venvName}";
      };

      shellHook = ''
        ln -sfn ${venv} .venv

        # ensure ipykernel is available
        uv add ipykernel

        # start the kernel
        export KERNEL_NAME=$(basename ${venv})
        python -m ipykernel install --user --name $KERNEL_NAME --display-name $VENV_NAME

        # set environment variable to display devshell name
        ds=$(git rev-parse --show-toplevel 2>/dev/null)

        if [[ -z "$ds" ]]; then
            ds=$VENV_NAME
        fi

        export DEVSHELL="$ds"

        # cleanup
        trap "unset DEVSHELL" EXIT
        trap "jupyter kernelspec remove -f $KERNEL_NAME" EXIT
      '';

    };
  };

}

{ lib, python3 }:

python3.pkgs.buildPythonApplication {
  pname = "tesmart-ctl";
  version = "0.1.0";
  src = ./.;
  format = "pyproject";
  nativeBuildInputs = [ python3.pkgs.setuptools ];
  meta = {
    description = "CLI tool for TESmart KVM switch control";
    license = lib.licenses.mit;
    mainProgram = "tesmart-ctl";
  };
}

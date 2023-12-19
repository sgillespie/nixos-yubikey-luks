{ nixpkgs ? import <nixpkgs> {} }:

let
  inherit (nixpkgs) callPackage pkgs stdenv;

  pbkdf2Sha512 = callPackage ./pbkdf2-sha512 { };
  rbtohex = pkgs.writeShellScriptBin
    "rbtohex"
    ''( od -An -vtx1 | tr -d ' \n' )'';
  hextorb = pkgs.writeShellScriptBin
    "hextorb"
    ''( tr '[:lower:]' '[:upper:]' | sed -e 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/gI'| xargs printf )'';
in
  stdenv.mkDerivation {
    name = "yubikey-luks-setup";
    buildInputs = with pkgs; [
      cryptsetup
      openssl
      parted
      pbkdf2Sha512
      yubikey-personalization
      rbtohex
      hextorb
    ];
  }

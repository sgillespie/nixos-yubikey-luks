{ nixpkgs ? import <nixpkgs> {} }:

let
  inherit (nixpkgs) callPackage pkgs stdenv;
  pbkdf2Sha512 = callPackage ./pbkdf2-sha512 { };
in
  stdenv.mkDerivation {
    name = "yubikey-luks-setup";
    buildInputs = with pkgs; [
      cryptsetup
      openssl
      parted
      pbkdf2Sha512
      yubikey-personalization
    ];
    
    shellHook = ''
      rbtohex() {
        ( od -An -vtx1 | tr -d ' \n' )
      }

      hextorb() {
        ( tr '[:lower:]' '[:upper:]' | sed -e 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/gI'| xargs printf )
      }
    '';

    
    inherit (pkgs) cryptsetup openssl yubikey-personalization;
  }

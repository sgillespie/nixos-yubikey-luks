{ stdenv, fetchurl, openssl }:

stdenv.mkDerivation rec {
  name = "pbkdf2-sha512";
  version = "latest";
  buildInputs = [openssl];
    
  src = fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/system/boot/pbkdf2-sha512.c";
    sha256 = "0pn5hh78pyh4q6qjp3abipivkgd8l39sqg5jnawz66bdzicag4l7";
  };

  unpackPhase = ":";
  buildPhase = "cc -O3 -I${openssl.dev}/include -L${openssl.out}/lib ${src} -o pbkdf2-sha512 -lcrypto";
  installPhase = ''
    mkdir -p $out/bin
    install -m755 pbkdf2-sha512 $out/bin/pbkdf2-sha512
  '';
}

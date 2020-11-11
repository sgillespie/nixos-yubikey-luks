{ stdenv, fetchurl, openssl }:

stdenv.mkDerivation rec {
  name = "pbkdf2-sha512";
  version = "latest";
  buildInputs = [openssl];
    
  src = fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/system/boot/pbkdf2-sha512.c";
    sha256 = "0ky414spzpndiifk7wca3q3l9gzs1ksn763dmy48xdn3q0i75s9r";
  };

  unpackPhase = ":";
  buildPhase = "cc -O3 -I${openssl.dev}/include -L${openssl.out}/lib ${src} -o pbkdf2-sha512 -lcrypto";
  installPhase = ''
    mkdir -p $out/bin
    install -m755 pbkdf2-sha512 $out/bin/pbkdf2-sha512
  '';
}

# LUKS-Encrypted Filesystem with Yubikey PBA
In this guide, we describe how to set up an encrypted filesystem with Yubikey pre-boot authentication (PBA) on NixOS. While the focus is on NixOS, the same techniques should be able to be used on any Linux system where Linux Unified Key Setup (LUKS) is available.

This guide is inspired by and based on [Yubikey based Full Disk Encryption (FDE) on NixOS](https://nixos.wiki/wiki/Yubikey_based_Full_Disk_Encryption_(FDE)_on_NixOS).

Other methods exist for other Linux distributions:

 * ArchLinux: [Yubikey Full Disk Encryption](https://github.com/agherzan/yubikey-full-disk-encryption)
 * Debian: [Yubikey for Luks](https://github.com/cornelinux/yubikey-luks)

## Design
We have the option of using either one (1FA) or two (2FA) factors for authentication. Using 1FA, the Yubikey must be inserted to open the LUKS device, but no extra passphrase is required. With 2FA, once the Yubikey is inserted, we'll be asked to enter a passphrase in order to open the LUKS device.

We'll program the Yubikey in Challenge-Response (HMAC-SHA1) mode in an alternate slot. Then we'll calculare the `salt` and `iterations` and store them on an unencrypted partition. These values will be used to calculate the challenge for the Yubikey. The response, along with a user-entered passphrase in 2FA, will be used to calculate the LUKS key.

At boot time, NixOSs Yubikey PBA will read the `salt` and `iterations`, which is again used to calculate the challenge. The Yubikey's response will be used to calculate the LUKS key. If we're using 2FA, we'll enter a passphrase which will be combined with the challenge-response key. If the key is successfully unlocked, NixOS will recalculate the `salt` and `iterations` values, and the expected Yubikey response. It will use the response to update the LUKS key so the passphrase is different at each time the machine is booted.

## Requirements
Before beginning the process, it's assumed that you have

 * An unencrypted partition (Here we use ESP, but any partition is fine)
 * A Yubikey with a free configuration slot
 * A running NixOS system
 
### Setup
For convenience, I've created a Nix expression that includes all dependencies. Enter the nix-shell:

    nix-shell https://github.com/sgillespie/nixos-yubikey-luks/archive/master.tar.gz

## Setup - Manual
If you don't want to use the nix expression, we can set up the same environment manually.

You'll need the following software dependencies:

 * cryptsetup
 * gcc
 * openssl
 * pbkdf2-sha512
 * yubikey-personalization
 
`pkdf2-sha512` is a simple program included in nixpkgs that exposes OpenSSLs PKDF2 implementation. Grap the source file at https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/system/boot/pbkdf2-sha512.c and compile it.

Finally, we need a couple of bash helper functions.

    rbtohex() {
        ( od -An -vtx1 | tr -d ' \n' )
    }

    hextorb() {
        ( tr '[:lower:]' '[:upper:]' | sed -e 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/gI'| xargs printf )
    }

Add these to a shell file and source it.

## Procedure
### Step 1 - Program the Yubikey Free Slot
Program the Yubikey's free slot challenge-response mode (HMAC-SHA1). We let the Yubikey generate a key for us.

    ykpersonalize -2 -ochal-resp -ochal-hmac

### Step 2 - Create a New Partition
Create a new partition. As an example, we'll create a new 100G partition on sdb starting at 208G.

    parted /dev/sdb -- mkpart primary 208G 308G

### Step 3 - Calculate the LUKS Passphrase
Generate the initial salt. It can be any integer value between 16 and 64.

    SALT_LENGTH=16
    SALT="$(dd if=/dev/random bs=1 count=$SALT_LENGTH 2>/dev/null | rbtohex)"
    
Enter the 2FA passphrase, if desired

    read -s USER_PASSPHRASE
    
Calculate the initial challenge and response

    CHALLENGE="$(echo -n $SALT | openssl dgst -binary -sha512 | rbtohex)"
    RESPONSE=$(ykchalresp -2 -x $CHALLENGE 2>/dev/null)
    
Calculate the LUKS slot key from the desired factors

    KEY_LENGTH=512
    ITERATIONS=1000000
    
If you want to use 2FA

    LUKS_KEY="$(echo -n $USER_PASSPHRASE | pbkdf2-sha512 $(($KEY_LENGTH / 8)) $ITERATIONS $RESPONSE | rbtohex)"

Otherwise
    
    LUKS_KEY="$(echo | pbkdf2-sha512 $(($KEY_LENGTH / 8)) $ITERATIONS $RESPONSE | rbtohex)"

### Step 4 - Create the LUKS device
Create the LUKS device. 

    CIPHER=aes-xts-plain64
    HASH=sha512
    
As an example, we'll use the partition we created in Step 1: `/dev/sdb5`.
    
    echo -n "$LUKS_KEY" | hextorb | cryptsetup luksFormat --cipher="$CIPHER" \ 
      --key-size="$KEY_LENGTH" --hash="$HASH" --key-file=- /dev/sdb5

### Step 5 - Store Salt and Iterations
Store the salt and iterations on an unencrypted partition. Here, we use the `ESP` partition mounted on `/boot`

    mkdir -p /boot/crypt-storage
    echo -ne "$SALT\n$ITERATIONS" > /boot/crypt-storage/default
  
### Step 6 - Open the LUKS device
Open the LUKS device. As an example, we again use /dev/sdb5.

    echo -n "$LUKS_KEY" | hextorb | cryptsetup open /dev/sdb5 encrypted --key-file=-
    
We can now access the volume at `/dev/mapper/encrypted`. For example, to format it as ext4

    mkfs.ext4 /dev/mapper/encrypted

### Step 7 - Update NixOS Configuration
Open up your hardware configuration at `/etc/nixos/hardware-configuration.nix` and set up the new LUKS-encrypted disk

    boot.initrd = {
      # Required to open the EFI partition and Yubikey
      kernelModules = ["vfat" "nls_cp437" "nls_iso8859-1" "usbhid"];
      
      luks = {
        # Support for Yubikey PBA
        yubikeySupport = true;
        
        devices."encrypted" = {
          device = "/dev/sdb5"; # Be sure to update this to the correct volume
          
          yubikey = {
            slot = 2;
            twoFactor = true; # Set to false for 1FA
            gracePeriod = 30; # Time in seconds to wait for Yubikey to be inserted
            keyLength = 64; # Set to $KEY_LENGTH/8
            saltLength = 16; # Set to $SALT_LENGTH
            
            storage = {
              device = "/dev/sdb1"; # Be sure to update this to the correct volume
              fsType = "vfat";
              path = "/crypt-storage/default";
            };
          };
        };
      };
    };
   
### Step 8 - Reboot
Rebuild your NixOS configuration and reboot

    nixos-rebuild boot # Rebuild NixOS configs and set as the default for next boot
    reboot

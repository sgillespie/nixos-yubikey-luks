#!/usr/bin/env bash

function usage {
    cat >&2 <<EOF
Usage: yk-luks-open.sh [OPTIONS] DEVICE

Mount a LUKS encrypted filesystem with Yubikey on NixOS

Options:

  -c, --storage=file       Path of the salt on and iterations on the unencrypted device
  -l, --key-length=number  Length of the LUKS slot key
  -p, --passphrase         Prompt for 2FA passphrase
  -s, --slot=number        Which slot on the YubiKey to challenge.
  -h, --help               Show this help
EOF
}

# Get CLI options
options=$(getopt --options "c:l:ps:h" --long "key-length:,passphrase,slot:,storage:,help" -- "$@")

# Inspect CLI options
eval set -- "$options"
while true; do
    case $1 in
        -c|--storage)
            STORAGE=$2
            shift 2
            ;;
        -l|--key-length)
            KEY_LENGTH=$2
            shift 2
            ;;
        -p|--passphrase)
            PROMPT_PHRASE=
            shift
            ;;
        -s|--slot)
            SLOT=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo -e "Unhandled option '$1'"
            exit 2
    esac
done

# Inspect the device
DEVICE=$1
if [[ -z "$DEVICE" ]]; then
    echo -e "Missing required option: DEVICE"

    usage
    exit 1
fi

# Set defaults from specified options
: ${STORAGE:=/mnt/boot/crypt-storage/default}
: ${KEY_LENGTH:=512}
: ${SLOT:=1}

# Prompt for the passphrase
if [[ "${PROMPT_PHRASE+DEFINED}" ]]; then
    read -s -p "Passphrase: " USER_PASSPHRASE
    echo
else
    USER_PASSPHRASE=
fi

# Look up salt and iterations
SALT=$(awk 'NR == 1 { print }' < "$STORAGE")
ITERATIONS=$(awk 'NR == 2 { print }' < "$STORAGE")

# Calculate LUKS key
CHALLENGE=$(echo -n $SALT | openssl dgst -binary -sha512 | rbtohex)
RESPONSE=$(ykchalresp -2 -x $CHALLENGE 2>/dev/null)
LUKS_KEY="$(echo "$USER_PASSPHRASE" | pbkdf2-sha512 $(($KEY_LENGTH / 8)) $ITERATIONS $RESPONSE | rbtohex)"

# Open the LUKS device
echo -n "$LUKS_KEY" \
    | hextorb \
    | cryptsetup open "$DEVICE" encrypted --key-file=-

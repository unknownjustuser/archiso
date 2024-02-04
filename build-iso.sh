#!/usr/bin/env bash

set -e

WORKDIR="/tmp/work"

show_help() {
  echo "Usage: $0 [-o OUTPUT_DIR] [-p PROFILE_DIR]"
  echo "Options:"
  echo "  -o, --output     Specify the output directory (default: ./out)"
  echo "  -p, --profile    Specify the Archiso profile directory (default: ./profile)"
  echo "  -h, --help       Show this help message"
}

# Default values
output_dir="./out"
profile_dir="./profile"

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -o | --output)
    output_dir="$2"
    shift
    ;;
  -p | --profile)
    profile_dir="$2"
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
  shift
done

echo -e "\n################\nCreating dir\n################\n"
mkdir -p "$WORKDIR" "$output_dir"

echo -e "\n################\nInstalling needed pkgs\n################\n"
sudo pacman --noconfirm --needed -S archiso mkinitcpio-archiso

echo -e "\n################\nBuilding\n################\n"
for dir in "$profile_dir"/*/; do
  sudo mkarchiso -v -w "$WORKDIR" -o "$output_dir" "$dir"
  # sudo rm -rf "$WORKDIR"/.*
done

echo -e "\n################\nDone!\n################\n"
ls -ahl "$output_dir"
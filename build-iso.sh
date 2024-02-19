#!/usr/bin/env bash

# Script name: build-iso.sh
# Description: Automate archiso build script.
# Contributors: unknownjustuser

# Set flags to make robust
set -euo pipefail

WORKDIR="./work"
output_dir="./out"
profile_dir="./profile"
xfce="$profile_dir/xfce4"

# Directories to be used within the script
declare -a dirs=(
  "$WORKDIR"
  "$output_dir"
)

# Create needed dirs
create_directories() {
  mkdir -p "${dirs[@]}"
}

# Function to cleanup directories on script exit or interrupt
cleanup() {
  echo "Cleaning up..."
  rm -rf "$WORKDIR"
  exit 1
}

trap cleanup INT

INP() {
  echo "Installing needed pkgs"
  if ! pacman -Qq archiso; then
    echo "archiso package is not installed. Installing..."
    pacman --noconfirm --needed -S archiso
  fi
}

build() {
  echo "Building"
  mkarchiso -v -w "$WORKDIR" -o "$output_dir" "$xfce"
}

# Main execution flow
create_directories
INP
build
cleanup

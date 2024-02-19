#!/usr/bin/env bash

# This script is run within a virtual environment to build the available archiso profiles and their available build
# modes and create checksum files for the resulting images.
# The script needs to be run as root and assumes $PWD to be the root of the repository.
#
# Dependencies:
# * all archiso dependencies
# * coreutils
# * gnupg
# * openssl
# * zsync
#
# $1: profile
# $2: buildmode

# Set flags to make robust
set -euo pipefail
shopt -s extglob

readonly orig_pwd="${PWD}"
readonly output="${orig_pwd}/output"
readonly tmpdir_base="${orig_pwd}/tmp"
readonly profile="${1}"
readonly buildmode="${2}"

tmpdir=""
tmpdir="$(mktemp --dry-run --directory --tmpdir="${tmpdir_base}")"

cleanup() {
  # clean up temporary directories
  if [[ -n "${tmpdir_base:-}" ]]; then
    rm -fr "${tmpdir_base}"
  fi
}

run_mkarchiso() {
  # run mkarchiso
  mkdir -p "${output}/" "${tmpdir}/"
  ./archiso/mkarchiso -o "${output}/" -w "${tmpdir}/" -m "${buildmode}" -v "configs/${profile}"

  if [[ -n "${SUDO_UID:-}" ]] && [[ -n "${SUDO_GID:-}" ]]; then
    chown -Rv "${SUDO_UID}:${SUDO_GID}" -- "${output}"
  fi
}

trap cleanup EXIT

run_mkarchiso

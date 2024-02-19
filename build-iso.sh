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
readonly install_dir="arch"

tmpdir=""
tmpdir="$(mktemp --dry-run --directory --tmpdir="${tmpdir_base}")"

print_section_start() {
  # gitlab collapsible sections start: https://docs.gitlab.com/ee/ci/jobs/#custom-collapsible-sections
  local _section _title
  _section="${1}"
  _title="${2}"

  printf "\e[0Ksection_start:%(%s)T:%s\r\e[0K%s\n" '-1' "${_section}" "${_title}"
}

print_section_end() {
  # gitlab collapsible sections end: https://docs.gitlab.com/ee/ci/jobs/#custom-collapsible-sections
  local _section
  _section="${1}"

  printf "\e[0Ksection_end:%(%s)T:%s\r\e[0K\n" '-1' "${_section}"
}

cleanup() {
  # clean up temporary directories
  print_section_start "cleanup" "Cleaning up temporary directory"

  if [[ -n "${tmpdir_base:-}" ]]; then
    rm -fr "${tmpdir_base}"
  fi

  print_section_end "cleanup"
}

run_mkarchiso() {
  # run mkarchiso
  print_section_start "mkarchiso" "Running mkarchiso"
  mkdir -p "${output}/" "${tmpdir}/"
  ./archiso/mkarchiso \
    -D "${install_dir}" \
    -o "${output}/" \
    -w "${tmpdir}/" \
    -m "${buildmode}" \
    -v "configs/${profile}"

  print_section_end "mkarchiso"

  print_section_start "ownership" "Setting ownership on output"

  if [[ -n "${SUDO_UID:-}" ]] && [[ -n "${SUDO_GID:-}" ]]; then
    chown -Rv "${SUDO_UID}:${SUDO_GID}" -- "${output}"
  fi
  print_section_end "ownership"
}

trap cleanup EXIT

run_mkarchiso

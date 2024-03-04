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
gnupg_homedir=""
codesigning_dir=""
codesigning_cert=""
codesigning_key=""
ca_cert=""
ca_key=""
pgp_key_id=""
transfer_url="https://transfer.sh"

print_section_start() {
  # Print start of a collapsible section for GitLab CI
  local _section _title
  _section="${1}"
  _title="${2}"

  printf "\e[0Ksection_start:%(%s)T:%s\r\e[0K%s\n" '-1' "${_section}" "${_title}"
}

print_section_end() {
  # Print end of a collapsible section for GitLab CI
  local _section
  _section="${1}"

  printf "\e[0Ksection_end:%(%s)T:%s\r\e[0K\n" '-1' "${_section}"
}

cleanup() {
  # Clean up temporary directories
  print_section_start "cleanup" "Cleaning up temporary directory"

  if [[ -n "${tmpdir_base:-}" ]]; then
    rm -fr "${tmpdir_base}"
  fi

  print_section_end "cleanup"
}

create_checksums() {
  # Create checksums for files
  # $@: files
  local _file_path _file_name _current_pwd
  _current_pwd="${PWD}"

  print_section_start "checksums" "Creating checksums"

  for _file_path in "$@"; do
    cd "$(dirname "${_file_path}")"
    _file_name="$(basename "${_file_path}")"
    b2sum "${_file_name}" >"${_file_name}.b2"
    md5sum "${_file_name}" >"${_file_name}.md5"
    sha1sum "${_file_name}" >"${_file_name}.sha1"
    sha256sum "${_file_name}" >"${_file_name}.sha256"
    sha512sum "${_file_name}" >"${_file_name}.sha512"
    ls -lah "${_file_name}."{b2,md5,sha{1,256,512}}
    cat "${_file_name}."{b2,md5,sha{1,256,512}}
  done
  cd "${_current_pwd}"

  print_section_end "checksums"
}

create_zsync_delta() {
  # Create zsync control files for files
  # $@: files
  local _file

  print_section_start "zsync_delta" "Creating zsync delta"

  for _file in "$@"; do
    if [[ "${buildmode}" == "bootstrap" ]]; then
      # zsyncmake fails on 'too long between blocks' with default block size on bootstrap image
      zsyncmake -v -b 512 -C -u "${_file##*/}" -o "${_file}".zsync "${_file}"
    else
      zsyncmake -v -C -u "${_file##*/}" -o "${_file}".zsync "${_file}"
    fi
  done

  print_section_end "zsync_delta"
}

create_ephemeral_pgp_key() {
  # Create an ephemeral PGP key for signing the rootfs image
  print_section_start "ephemeral_pgp_key" "Creating ephemeral PGP key"

  gnupg_homedir="$tmpdir/.gnupg"
  mkdir -p "${gnupg_homedir}"
  chmod 700 "${gnupg_homedir}"

  cat <<__EOF__ >"${gnupg_homedir}"/gpg.conf
quiet
batch
no-tty
no-permission-warning
export-options no-export-attributes,export-clean
list-options no-show-keyring
armor
no-emit-version
__EOF__

  gpg --homedir "${gnupg_homedir}" --gen-key <<EOF
%echo Generating ephemeral ArchFiery release engineering key pair...
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: ArchFiery Release Engineering
Name-Comment: Ephemeral Signing Key
Name-Email: unknown.just.user@proton.me
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

  pgp_key_id="$(
    gpg --homedir "${gnupg_homedir}" \
      --list-secret-keys \
      --with-colons |
      awk -F':' '{if($1 ~ /sec/){ print $5 }}'
  )"

  print_section_end "ephemeral_pgp_key"
}

pgp_sender="ArchFiery Release Engineering (Ephemeral Signing Key) <unknown.just.user@proton.me>"

create_ephemeral_codesigning_keys() {
  # Create ephemeral certificates used for codesigning
  print_section_start "ephemeral_codesigning_key" "Creating ephemeral codesigning keys"

  codesigning_dir="${tmpdir}/.codesigning/"
  local ca_dir="${codesigning_dir}/ca/"

  local ca_conf="${ca_dir}/certificate_authority.cnf"
  local ca_subj='/C=DE/ST=Berlin/L=Berlin/O=ArchFiery/OU=Release Engineering/emailAddress=unknown.just.user@proton.me/CN=ArchFiery Release Engineering (Ephemeral Certificate Authority)'
  ca_cert="${ca_dir}/cacert.pem"
  ca_key="${ca_dir}/private/cakey.pem"

  local codesigning_conf="${codesigning_dir}/code_signing.cnf"
  local codesigning_subj='/C=DE/ST=Berlin/L=Berlin/O=ArchFiery/OU=Release Engineering/emailAddress=unknown.just.user@proton.me/CN=ArchFiery Release Engineering (Ephemeral Signing Key)'
  codesigning_cert="${codesigning_dir}/codesign.crt"
  codesigning_key="${codesigning_dir}/codesign.key"

  mkdir -p "${ca_dir}/"{private,newcerts,crl}
  mkdir -p "${codesigning_dir}"
  cp -- /etc/ssl/openssl.cnf "${codesigning_conf}"
  cp -- /etc/ssl/openssl.cnf "${ca_conf}"
  touch "${ca_dir}/index.txt"
  echo "1000" >"${ca_dir}/serial"

  # Prepare the ca configuration for the change in directory
  sed -i "s#/etc/ssl#${ca_dir}#g" "${ca_conf}"

  # Create the Certificate Authority
  openssl req \
    -newkey rsa:4096 \
    -nodes \
    -x509 \
    -new \
    -sha256 \
    -keyout "${ca_key}" \
    -config "${ca_conf}" \
    -subj "${ca_subj}" \
    -days 2 \
    -out "${ca_cert}"

  local extension_text
  IFS='' read -r -d '' extension_text <<EOF || true
[codesigning]
keyUsage=digitalSignature
extendedKeyUsage=codeSigning, clientAuth, emailProtection
EOF

  printf '%s' "${extension_text}" >>"${ca_conf}"
  printf '%s' "${extension_text}" >>"${codesigning_conf}"

  openssl req \
    -newkey rsa:4096 \
    -keyout "${codesigning_key}" \
    -nodes \
    -sha256 \
    -out "${codesigning_cert}.csr" \
    -config "${codesigning_conf}" \
    -subj "${codesigning_subj}" \
    -extensions codesigning

  # Sign the code signing certificate with the CA
  openssl ca \
    -batch \
    -config "${ca_conf}" \
    -extensions codesigning \
    -days 2 \
    -notext \
    -md sha256 \
    -keyfile "${ca_key}" \
    -cert "${ca_cert}" \
    -in "${codesigning_cert}.csr" \
    -out "${codesigning_cert}"

  print_section_end "ephemeral_codesigning_key"
}

transfer() {
  local file
  declare -a file_array
  file_array=("${@}")

  if [[ "${#file_array[@]}" -eq 0 || "${1}" == "--help" || "${1}" == "-h" ]]; then
    echo "${0} - Upload arbitrary files to \"transfer.sh\"."
    echo ""
    echo "Usage: ${0} [options] [<file>]..."
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help"
    echo "      show this message"
    echo ""
    echo "EXAMPLES:"
    echo "  Upload a single file from the current working directory:"
    echo "      ${0} \"image.img\""
    echo ""
    echo "  Upload multiple files from the current working directory:"
    echo "      ${0} \"image.img\" \"image2.img\""
    echo ""
    echo "  Upload a file from a different directory:"
    echo "      ${0} \"/tmp/some_file\""
    echo ""
    echo "  Upload all files from the current working directory. Be aware of the webserver's rate limiting!:"
    echo "      ${0} *"
    echo ""
    echo "  Upload a single file from the current working directory and filter out the delete token and download link:"
    echo "      ${0} \"image.img\" | awk --field-separator=\": \" '/Delete token:/ { print \$2 } /Download link:/ { print \$2 }'"
    echo ""
    echo "  Show help text from \"transfer.sh\":"
    echo "      curl --request GET \"https://transfer.sh\""
    return 0
  else
    for file in "${file_array[@]}"; do
      if [[ ! -f "${file}" ]]; then
        echo -e "\e[01;31m'${file}' could not be found or is not a file.\e[0m" >&2
        return 1
      fi
    done
    unset file
  fi

  local upload_files
  local curl_output
  local awk_output

  du -c -k -L "${file_array[@]}" >&2
  # be compatible with "bash"
  if [[ "${ZSH_NAME}" == "zsh" ]]; then
    read $'upload_files?\e[01;31mDo you really want to upload the above files ('"${#file_array[@]}"$') to "transfer.sh"? (Y/n): \e[0m'
  elif [[ "${BASH}" == *"bash"* ]]; then
    read -p $'\e[01;31mDo you really want to upload the above files ('"${#file_array[@]}"$') to "transfer.sh"? (Y/n): \e[0m' upload_files
  fi

  case "${upload_files:-y}" in
  "y" | "Y")
    # for the sake of the progress bar, execute "curl" for each file.
    # the parameters "--include" and "--form" will suppress the progress bar.
    for file in "${file_array[@]}"; do
      curl_output=$(curl --request PUT --progress-bar --dump-header - --upload-file "${file}" "${transfer_url}")
      awk_output=$(awk \
        'gsub("\r", "", $0) && tolower($1) ~ /x-url-delete/ \
                                {
                                    delete_link=$2;
                                    print "Delete command: curl --request DELETE " "\""delete_link"\"";

                                    gsub(".*/", "", delete_link);
                                    delete_token=delete_link;
                                    print "Delete token: " delete_token;
                                }

                                END{
                                    print "Download link: " $0;
                                }' <<<"${curl_output}")

      echo -e "${awk_output}\n"

      if ((${#file_array[@]} > 4)); then
        sleep 5
      fi
    done
    ;;

  "n" | "N")
    return 1
    ;;

  *)
    echo -e "\e[01;31mWrong input: '${upload_files}'.\e[0m" >&2
    return 1
    ;;
  esac
}

upload_zsync_files() {
  print_section_start "upload_zsync_files" "Uploading .zsync files to transfer.sh"

  local zsync_files=("${output}"/*.zsync)
  if [[ ${#zsync_files[@]} -gt 0 ]]; then
    transfer "${zsync_files[@]}"
  fi

  print_section_end "upload_zsync_files"
}

run_mkarchiso() {
  # Run mkarchiso
  print_section_start "mkarchiso" "Running mkarchiso"
  mkdir -p "${output}/" "${tmpdir}/"
  GNUPGHOME="${gnupg_homedir}" mkarchiso \
    -D "${install_dir}" \
    -c "${codesigning_cert} ${codesigning_key} ${ca_cert}" \
    -g "${pgp_key_id}" \
    -G "${pgp_sender}" \
    -o "${output}/" \
    -w "${tmpdir}/" \
    -m "${buildmode}" \
    -v "configs/${profile}"

  print_section_end "mkarchiso"

  if [[ "${buildmode}" =~ "iso" ]]; then
    create_zsync_delta "${output}/"*.iso
    create_checksums "${output}/"*.iso
  fi

  print_section_start "ownership" "Setting ownership on output"

  if [[ -n "${SUDO_UID:-}" ]] && [[ -n "${SUDO_GID:-}" ]]; then
    chown -Rv "${SUDO_UID}:${SUDO_GID}" -- "${output}"
  fi
  print_section_end "ownership"
}

trap cleanup EXIT

run_mkarchiso
upload_zsync_files

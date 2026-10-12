#!/usr/bin/env bash
set -euo pipefail

# Apple Clang rejects -fuse-ld=lld for Linux ELF targets. Compile freestanding
# objects with the selected host Clang, then link them with the selected LLD.
args=("$@")
target_linux_arm64=false
target_linux_x86=false
output=""
assembly=""
source=""
linker_script=""
for ((index = 0; index < ${#args[@]}; index++)); do
  argument="${args[$index]}"
  case "$argument" in
    aarch64-linux-gnu) target_linux_arm64=true ;;
    i386-linux) target_linux_x86=true ;;
    -o)
      index=$((index + 1))
      output="${args[$index]}"
      ;;
    *.S) assembly="$argument" ;;
    *.c) source="$argument" ;;
    -Wl,-T,*) linker_script="${argument#-Wl,-T,}" ;;
  esac
done

if [[ "$target_linux_arm64" != true && "$target_linux_x86" != true ]]; then
  echo "Unsupported use of the iSH VDSO compiler wrapper." >&2
  exit 2
fi

compiler="${OPENMUSE_VDSO_HOST_CLANG:-}"
linker="${OPENMUSE_VDSO_LLD:-}"
if [[ ! -x "$compiler" || ! -x "$linker" ]]; then
  echo "Set OPENMUSE_VDSO_HOST_CLANG and OPENMUSE_VDSO_LLD before building iSH." >&2
  exit 2
fi

# The ARM64 Meson probe only tests compilation; it does not need the ELF linker.
if [[ " ${args[*]} " == *" -c "* ]]; then
  exec "$compiler" "$@"
fi

if [[ "$target_linux_arm64" == true ]]; then
  target="aarch64-linux-gnu"
  linker_emulation="aarch64elf"
else
  target="i386-linux"
  linker_emulation="elf_i386"
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/openmuse-vdso.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

# Meson probes the compiler with an extensionless C file before it creates the
# real VDSO target. Support that probe with the same compiler and linker.
if [[ -z "$assembly" || -z "$source" || -z "$linker_script" ]]; then
  source=""
  for ((index = 0; index < ${#args[@]}; index++)); do
    if [[ "${args[$index]}" == "-x" ]]; then
      source="${args[$((index + 2))]:-}"
      break
    fi
  done
  if [[ -z "$source" || -z "$output" ]]; then
    echo "Could not identify the VDSO compiler probe source and output." >&2
    exit 2
  fi
  "$compiler" -target "$target" -ffreestanding -fPIC -x c -c "$source" -o "$temporary_directory/probe.o"
  "$linker" -m "$linker_emulation" --hash-style=sysv -shared -o "$output" "$temporary_directory/probe.o"
  exit 0
fi

"$compiler" -target "$target" -ffreestanding -fPIC -c "$assembly" -o "$temporary_directory/vdso.S.o"
"$compiler" -target "$target" -ffreestanding -fPIC -c "$source" -o "$temporary_directory/vdso.c.o"
"$linker" -m "$linker_emulation" -T "$linker_script" --hash-style=sysv -shared \
  -o "$output" "$temporary_directory/vdso.S.o" "$temporary_directory/vdso.c.o"

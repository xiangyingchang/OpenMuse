#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ish_root="$repo_root/Vendor/ish-arm64"
build_root="$repo_root/.build/OpenMuse-iSH"
tools_root="$repo_root/.build/ish-tooling"
native_build="$build_root/host-macos"
device_build="$build_root/ios-arm64"
output_libs="$build_root/lib"
alpine_version="3.24.2"
alpine_branch="${alpine_version%.*}"
alpine_arch="aarch64"
alpine_sha256="9bf70a7f18ea44094cbb5f70c58f9af129c8214745743db0e68e5502cc2ce773"
alpine_archive="$build_root/alpine-minirootfs-${alpine_version}-${alpine_arch}.tar.gz"
rootfs_output="$build_root/alpine-rootfs"
package_notice="$build_root/alpine-package-notices.txt"

if [[ "${PLATFORM_NAME:-iphoneos}" != "iphoneos" ]]; then
  echo "iSH device libraries are only built for iphoneos; simulator uses native tools only."
  exit 0
fi

mkdir -p "$build_root" "$output_libs"
if [[ ! -f "$ish_root/.git" && ! -d "$ish_root/.git" ]]; then
  echo "Missing pinned iSH source at $ish_root" >&2
  exit 1
fi

git -C "$ish_root" submodule update --init --recursive

if [[ ! -x "$tools_root/bin/meson" || ! -x "$tools_root/bin/ninja" ]]; then
  python3 -m venv "$tools_root"
  "$tools_root/bin/python" -m pip install --disable-pip-version-check 'meson==1.12.1' 'ninja==1.13.2'
fi

host_clang="$(xcrun --sdk macosx --find clang)"
host_ar="$(xcrun --sdk macosx --find ar)"
host_sdk="$(xcrun --sdk macosx --show-sdk-path)"
host_arch="$(uname -m)"
host_target="${host_arch}-apple-macosx13.0"
if [[ -n "${OPENMUSE_VDSO_LLD:-}" ]]; then
  vdso_lld="$OPENMUSE_VDSO_LLD"
elif command -v ld.lld >/dev/null 2>&1; then
  vdso_lld="$(command -v ld.lld)"
else
  vdso_lld=""
  for candidate in /usr/local/opt/lld/bin/ld.lld /opt/homebrew/opt/lld/bin/ld.lld; do
    if [[ -x "$candidate" ]]; then vdso_lld="$candidate"; break; fi
  done
fi
if [[ ! -x "$vdso_lld" ]]; then
  if [[ "${OPENMUSE_REUSE_CACHED_RUNTIME:-}" == "1" &&
        -x "$tools_root/bin/ninja" &&
        -f "$device_build/build.ninja" &&
        -f "$native_build/build.ninja" &&
        -f "$device_build/vdso/arm64/libvdso.so.elf" &&
        -f "$output_libs/libish.a" &&
        -f "$output_libs/libish_emu.a" &&
        -f "$output_libs/libfakefs.a" &&
        -x "$native_build/tools/fakefsify" &&
        -f "$alpine_archive" &&
        -f "$rootfs_output/meta.db" &&
        -d "$rootfs_output/data" ]]; then
    device_plan="$("$tools_root/bin/ninja" -C "$device_build" -n \
      libish.a libish_emu.a libfakefs.a vdso/arm64/libvdso.so.elf 2>&1)"
    native_plan="$("$tools_root/bin/ninja" -C "$native_build" -n tools/fakefsify 2>&1)"
    if [[ "${device_plan##*$'\n'}" == "ninja: no work to do." &&
          "${native_plan##*$'\n'}" == "ninja: no work to do." ]]; then
      echo "LLD is unavailable; reusing verified up-to-date iSH runtime artifacts under $build_root."
      exit 0
    fi
  fi
  echo "iSH ARM64 VDSO needs LLD. Install LLVM/LLD or set OPENMUSE_VDSO_LLD to an ld.lld executable." >&2
  exit 1
fi
export OPENMUSE_VDSO_HOST_CLANG="$host_clang"
export OPENMUSE_VDSO_LLD="$vdso_lld"
ln -sf "$repo_root/Scripts/ish-vdso-clang.sh" "$tools_root/bin/clang"
export PATH="$tools_root/bin:$PATH"

sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
clang_path="$(xcrun --sdk iphoneos --find clang)"
ar_path="$(xcrun --sdk iphoneos --find ar)"
strip_path="$(xcrun --sdk iphoneos --find strip)"
cross_file="$build_root/ios-arm64.cross"
cat > "$cross_file" <<EOF
[binaries]
c = '$clang_path'
ar = '$ar_path'
strip = '$strip_path'
pkg-config = 'false'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$sdk_path', '-miphoneos-version-min=17.0']
c_link_args = ['-arch', 'arm64', '-isysroot', '$sdk_path', '-miphoneos-version-min=17.0']

[properties]
needs_exe_wrapper = true
sys_root = '$sdk_path'
EOF

if [[ ! -f "$device_build/build.ninja" ]]; then
  meson setup "$device_build" "$ish_root" \
    --cross-file "$cross_file" \
    --buildtype=release \
    -Db_ndebug=true \
    -Dlog= \
    -Dlog_handler=nslog \
    -Dkernel=ish \
    -Dengine=asbestos \
    -Dguest_arch=arm64
else
  meson setup --reconfigure "$device_build" "$ish_root" \
    --cross-file "$cross_file" \
    --buildtype=release \
    -Db_ndebug=true \
    -Dlog= \
    -Dlog_handler=nslog \
    -Dkernel=ish \
    -Dengine=asbestos \
    -Dguest_arch=arm64
fi
ninja -C "$device_build" libish.a libish_emu.a libfakefs.a vdso/arm64/libvdso.so.elf
cp "$device_build/libish.a" "$output_libs/"
cp "$device_build/libish_emu.a" "$output_libs/"
cp "$device_build/libfakefs.a" "$output_libs/"

# Xcode exports the iPhone SDKROOT to build-phase scripts. fakefsify is a
# native macOS build tool, so do not let that iPhone SDK contaminate Meson's
# host-library probes (for example sqlite3).
unset SDKROOT

native_file="$build_root/host-macos.ini"
cat > "$native_file" <<EOF
[binaries]
c = '$host_clang'
ar = '$host_ar'

[built-in options]
c_args = ['-target', '$host_target', '-isysroot', '$host_sdk']
c_link_args = ['-target', '$host_target', '-isysroot', '$host_sdk']
EOF

alpine_url="https://dl-cdn.alpinelinux.org/alpine/v${alpine_branch}/releases/${alpine_arch}/alpine-minirootfs-${alpine_version}-${alpine_arch}.tar.gz"
if [[ ! -f "$alpine_archive" ]]; then
  curl --http1.1 --retry 3 --retry-all-errors --fail --location --silent --show-error "$alpine_url" --output "$alpine_archive.part"
  mv "$alpine_archive.part" "$alpine_archive"
fi
actual_hash="$(shasum -a 256 "$alpine_archive" | awk '{print $1}')"
if [[ "$actual_hash" != "$alpine_sha256" ]]; then
  echo "Alpine rootfs checksum mismatch for $alpine_archive" >&2
  exit 1
fi

if [[ ! -f "$native_build/build.ninja" ]]; then
  env -u SDKROOT -u PLATFORM_NAME -u SDK_NAME -u SDK_DIR -u EFFECTIVE_PLATFORM_NAME \
    -u IPHONEOS_DEPLOYMENT_TARGET -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS \
    meson setup "$native_build" "$ish_root" --native-file "$native_file" \
    --buildtype=release \
    -Dlog= \
    -Dkernel=ish \
    -Dengine=asbestos \
    -Dguest_arch=x86
else
  env -u SDKROOT -u PLATFORM_NAME -u SDK_NAME -u SDK_DIR -u EFFECTIVE_PLATFORM_NAME \
    -u IPHONEOS_DEPLOYMENT_TARGET -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS \
    meson setup --reconfigure "$native_build" "$ish_root" --native-file "$native_file" \
    --buildtype=release \
    -Dlog= \
    -Dkernel=ish \
    -Dengine=asbestos \
    -Dguest_arch=x86
fi
ninja -C "$native_build" tools/fakefsify
rm -rf "$rootfs_output"
"$native_build/tools/fakefsify" "$alpine_archive" "$rootfs_output"
test -f "$rootfs_output/meta.db"
test -d "$rootfs_output/data"

installed="$rootfs_output/data/lib/apk/db/installed"
if [[ -f "$installed" ]]; then
  awk -F: '
    /^P:/ { package=$2 }
    /^V:/ { version=$2 }
    /^L:/ { license=$2 }
    /^$/ { if (package != "") printf "%s %s | %s\n", package, version, license; package=""; version=""; license="" }
  ' "$installed" | sort -f > "$package_notice"
fi

echo "Built iSH ARM64 libraries and fakefs rootfs under $build_root"

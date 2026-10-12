# Third-party notices

## OpenMuse

OpenMuse's original application code and documentation are distributed under GNU GPL version 3. The license text is in the repository root `LICENSE` and is bundled with both apps.

## iSH ARM64 runtime

The iOS app links the `OpenMinis/ish-arm64` source at commit `e6521d9cfe9cd48f19917fc3b23aea622ba358b4` as a Git submodule at `Vendor/ish-arm64`. The upstream `LICENSE.md` and `LICENSE.IOS` are preserved in that submodule and included in the iOS app's legal notices. The upstream license text describes GPL-3.0 licensing, additional GPL-2.0 licensing for specified later contributions, and an iOS distribution statement. The source remains separately identified by its own license files. OpenMuse's iOS host integration reads the active system resolver configuration and refreshes the guest resolver file; it does not patch the iSH source.

## Alpine Linux root filesystem

The iOS app bundles the official Alpine Linux 3.24.2 `aarch64` minirootfs. `Scripts/build-ish-ios.sh` verifies its SHA-256 before producing the iSH filesystem, and the app's legal notice screen includes the exact installed package versions and Alpine license identifiers as `alpine-package-notices.txt`.

| Package | Version | License identifier(s) |
|---|---:|---|
| alpine-baselayout | 3.7.2-r1 | GPL-2.0-only |
| alpine-baselayout-data | 3.7.2-r1 | GPL-2.0-only |
| alpine-keys | 2.6-r0 | MIT |
| alpine-release | 3.24.2-r0 | MIT |
| apk-tools | 3.0.8-r0 | GPL-2.0-only |
| busybox | 1.37.0-r31 | GPL-2.0-only |
| busybox-binsh | 1.37.0-r31 | GPL-2.0-only |
| ca-certificates-bundle | 20260909-r0 | MPL-2.0 AND MIT |
| libapk | 3.0.8-r0 | GPL-2.0-only |
| libcrypto3 | 3.5.8-r0 | Apache-2.0 |
| libssl3 | 3.5.8-r0 | Apache-2.0 |
| musl | 1.2.6-r2 | MIT |
| musl-utils | 1.2.6-r2 | MIT AND BSD-2-Clause AND GPL-2.0-or-later |
| scanelf | 1.3.9-r1 | GPL-2.0-only |
| ssl_client | 1.37.0-r31 | GPL-2.0-only |
| zlib | 1.3.2-r0 | Zlib |

The package list is generated from Alpine's installed-package database during the build and is also copied into the iOS app. The Alpine package sources and their license texts are maintained by the Alpine project; the package database records the license identifiers shown above.

## ZIPFoundation 0.9.20

Used for reading ChatGPT export ZIP files on iOS and macOS. Source: <https://github.com/weichsel/ZIPFoundation>. License: MIT.

MIT License

Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

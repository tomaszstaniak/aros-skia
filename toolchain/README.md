# x86_64-aros GCC 13.4.0 for ABIv11

Skia m154 needs C++20; the stock ABIv11 compiler (GCC 10.5.0) is too old.
The ABIv11 AROS source tree (deadwood2/AROS) carries patches for newer GCC
releases and can build them as cross compilers. `build-gcc13.sh` builds
GCC 13.4.0 with binutils 2.45 that way and applies what this port needed.

```sh
toolchain/build-gcc13.sh <workdir> <prefix>
```

- `<workdir>` must be on a case-sensitive filesystem (on macOS: an APFS
  (Case-sensitive) disk image, for example
  `hdiutil create -size 40g -type SPARSE -fs 'Case-sensitive APFS' -volname aroswork aroswork.sparseimage`).
  About 10 GB.
- `<prefix>` is the install directory, an absolute path. The installed
  `collect-aros` refers to it, so do not move the toolchain afterwards.

Pinned input: deadwood2/AROS commit `e33ca77d6c3b61a8feb641f89072fe0f716fce75`
(AROS diffs `gcc-13.4.0-aros.diff`, `binutils-2.45-aros.diff`); the AROS build
downloads the GCC, binutils, GMP, MPFR, MPC and ISL tarballs itself.

## Corrections applied

| file | why |
|---|---|
| `patches/0001-gcc-13.4.0-aros-libgcc-reg-size-table.patch` | The AROS diff makes `init_dwarf_reg_size_table()` a no-op unless `MD_FALLBACK_FRAME_STATE_FOR` is defined, which it is not on x86_64. The unwinder's register size table stays zero and the first C++ `throw` aborts. The patch removes that hunk from the AROS diff before the build. |
| `patches/0002-host-zlib-zutil-darwin.patch` | macOS hosts only: zlib's `zutil.h` inside the binutils and GCC sources treats `TARGET_OS_MAC` as classic Mac OS and breaks the host build. The script applies it after each tarball is unpacked. |
| `aros-v11.specs` | The 13.4 AROS diff links library names that exist only in mainline AROS (`-lposixc -lstdcio -lstdc -loop`). This specs file restores the ABIv11 library list of the 10.5 compiler, with `-lpthread` inside the link group because libstdc++ uses threads. Pass `-specs=<prefix>/aros-v11.specs` on every link. |

Also pass `-Wl,-u,__cxa_pure_virtual` when linking C++ programs:
libstdc++ refers to that symbol weakly and `collect-aros` refuses any
undefined symbol, weak ones included.

## Verified

On AROS One x86_64: global constructors, `std::format`, ranges, concepts,
`throw`/`catch` of `int` and `std::runtime_error`, `std::thread`,
`std::mutex`; and the whole Skia SDK of this repository. Without patch 0001
a plain `try { throw 7; } catch (int) {}` aborts.

Not verified: other hosts than macOS on Apple Silicon, GCC 12.2 or 15.2
(their AROS diffs target mainline headers and libstdc++ does not build for
ABIv11), mainline AROS.

# Agent Guide: Building the Linux Kernel on Apple Silicon macOS

This guide provides complete instructions and architectural context for autonomous agents (and engineers) to take an **unmodified, upstream Linux kernel source tree** (e.g., `linux-7.2.7`) and successfully build functional kernel images on **Apple Silicon Macs** (macOS Darwin `arm64`) for both **ARM64 (`arm64`)** and **x86_64** targets using our [`build.sh`](file:///Users/jpgoodland/workspace/linux-kernel/build.sh) framework.

---

## 1. Executive Summary & Architecture Overview

The Linux kernel build system (**Kbuild**) assumes a standard Linux host environment:
1. An **ELF** host object format.
2. The **glibc** standard C library (supplying `<elf.h>`, `<byteswap.h>`, `<endian.h>`).
3. **GNU coreutils** (`GNU make` 4+, `GNU sed`, etc.).
4. A **case-sensitive** filesystem (ext4/btrfs).

When cross-compiling on macOS Apple Silicon:
- **Target Code** (the kernel image itself) compiles cleanly using Clang with LLVM integrated assembler and linker (`LLVM=1`).
- **Host Tools** (e.g., `fixdep`, `conf`, `dtc`, `modpost`, `sorttable`, `relacheck`, `gen-hyprel`, `vdsomunge`, `gen_init_cpio`) must be built and run on the **macOS host** as Darwin Mach-O executables.
- **macOS System Quirks** (APFS case-insensitivity, BSD userland tools, Apple Clang custom dialect, missing Linux headers, and `uuid_t` typedef collisions) break the build out-of-the-box.

By pairing **2 minimal in-tree kernel patches** with an external **`host-include/` compatibility shim** and a driver script ([`build.sh`](file:///Users/jpgoodland/workspace/linux-kernel/build.sh)), any unmodified Linux kernel tree can be built on macOS in minutes.

---

## 2. Differential Analysis: Modified (`linux-7.2.X`) vs. Unmodified (`linux-7.2.X`)

A comparative diff between our working `linux-7.2` directory and the clean `linux-7.2.7` baseline reveals that **only 2 files inside the kernel tree require modification**. All other host incompatibilities are resolved externally via `host-include/` and [`build.sh`](file:///Users/jpgoodland/workspace/linux-kernel/build.sh).

### Summary Table of Differences

| Location | Component | Unmodified Baseline (`linux-7.2.7`) | Working Tree (`linux-7.2`) | Reason / Failure Symptom |
| :--- | :--- | :--- | :--- | :--- |
| **In-Tree** | `scripts/Kbuild.include` (line 65) | `kbuild-file = $(or $(wildcard $(src)/Kbuild),$(src)/Makefile)` | `kbuild-file = $(or $(if $(wildcard $(src)/Kbuild/.),,$(wildcard $(src)/Kbuild)),$(src)/Makefile)` | On case-insensitive APFS, `wildcard Documentation/Kbuild` matches the **directory** `Documentation/kbuild/`, breaking `make clean` with `Documentation/Kbuild: Is a directory. Stop.` |
| **In-Tree** | `arch/arm64/tools/gen-kernel-hwcaps.sh` (line 20) | Uses `\+` in `sed 's/...HWCAP\([0-9]*\)_\([A-Z0-9_]\+\).*/...'` | Uses `[A-Z0-9_]*` in `sed 's/...HWCAP\([0-9]*\)_\([A-Z0-9_]*\).*/...'` | BSD `sed` does not recognize `\+` in standard regular expressions, causing silent substitution failure and leaving `KERNEL_HWCAP_EVTSTRM` undeclared in `arch_timer.h`. |
| **External** | `host-include/` | Not present in clean tarball | Provides `host_fix.h`, `elf.h`, `byteswap.h`, `endian.h`, `asm/byteorder.h`, etc. | Supplies missing standard ELF definitions and resolves system header conflicts without modifying dozens of host tool source files. |
| **External** | `build.sh` | Not present in clean tarball | Configures toolchain PATH, injects `HOSTCFLAGS`, auto-detects CPU cores, and traps timing | Automates passing `LLVM=1`, architecture, cores, and compiler flags. |

---

## 3. The 7 macOS Incompatibility Traps (and Solutions)

### Trap 1: APFS Case-Insensitive Filesystem Collision (`Documentation/Kbuild`)
- **Symptom**:
  ```text
  make[2]: *** Documentation/Kbuild: Is a directory.  Stop.
  make[1]: *** [Makefile:2203: _clean_Documentation] Error 2
  ```
- **Root Cause**: macOS default APFS is case-preserving but **case-insensitive**. In `scripts/Kbuild.include`, Make attempts to locate a Makefile or Kbuild file:
  ```makefile
  kbuild-file = $(or $(wildcard $(src)/Kbuild),$(src)/Makefile)
  ```
  When cleaning `Documentation`, `$(wildcard Documentation/Kbuild)` matches the existing directory `Documentation/kbuild/`. Make then tries to `include Documentation/Kbuild` as a makefile, failing immediately.
- **Fix**: Check whether `$(src)/Kbuild/.` exists (which is true only for directories). If it is a directory, evaluate to empty:
  ```makefile
  kbuild-file = $(or $(if $(wildcard $(src)/Kbuild/.),,$(wildcard $(src)/Kbuild)),$(src)/Makefile)
  ```

---

### Trap 2: BSD `sed` Incompatibilities
- **Symptom A**: `arch_timer.h: error: use of undeclared identifier 'KERNEL_HWCAP_EVTSTRM'`.
  - **Root Cause**: `arch/arm64/tools/gen-kernel-hwcaps.sh` executes:
    ```bash
    sed 's/.*HWCAP\([0-9]*\)_\([A-Z0-9_]\+\).*/#define KERNEL_HWCAP_\2\t__khwcap\1_feature(\2)/'
    ```
    BSD `sed` treats `\+` literally rather than as "one or more". The substitution fails silently and outputs `#define HWCAP_EVTSTRM` unchanged instead of defining `KERNEL_HWCAP_EVTSTRM`.
  - **Fix**: Use POSIX-standard `[A-Z0-9_]*` in `gen-kernel-hwcaps.sh`:
    ```bash
    sed 's/.*HWCAP\([0-9]*\)_\([A-Z0-9_]*\).*/#define KERNEL_HWCAP_\2\t__khwcap\1_feature(\2)/'
    ```

- **Symptom B**: `sed: 1: "modules.builtin.modinfo": invalid command code m` during final linking.
  - **Root Cause**: `scripts/Makefile.vmlinux` runs:
    ```makefile
    sed -i 's/\x00\+$$/\x00/g' $@
    ```
    GNU `sed` accepts `-i` with no argument. BSD `sed` requires an extension argument with `-i` (e.g. `sed -i ''`). In BSD `sed`, `'s/...'` is interpreted as the backup file extension and the target file (`modules.builtin.modinfo`) is interpreted as the script expression.
  - **Fix**: Install GNU `sed` via Homebrew (`brew install gnu-sed`) and prepend `/opt/homebrew/opt/gnu-sed/libexec/gnubin` to `PATH` in [`build.sh`](file:///Users/jpgoodland/workspace/linux-kernel/build.sh).

---

### Trap 3: Apple Clang `__counted_by` Compiler Bug
- **Symptom**:
  ```text
  ./include/linux/ring_buffer.h: error: __typeof__ on an expression of type 'unsigned long[] __counted_by(nr_page_va)' (aka 'unsigned long[]') is not yet supported
  ```
- **Root Cause**: The default compiler at `/usr/bin/clang` is Apple Clang. Apple Clang includes experimental bounds-safety extensions that activate on `__counted_by` attributes. When the kernel macros evaluate `__same_type(a, b)` / `__must_be_array()` using `typeof()`, Apple Clang generates a fatal compiler error.
- **Fix**: Do **not** use `/usr/bin/clang`. Install upstream LLVM via Homebrew (`brew install llvm lld`) and prepend `/opt/homebrew/opt/llvm/bin` and `/opt/homebrew/bin` to `PATH`.

---

### Trap 4: Missing `<elf.h>` and Architecture Relocations
- **Symptom**:
  ```text
  fatal error: 'elf.h' file not found
  error: use of undeclared identifier 'R_AARCH64_ABS64'
  error: call to undeclared function 'EF_ARM_EABI_VERSION'
  error: use of undeclared identifier 'R_X86_64_PC32'
  ```
- **Root Cause**: macOS SDK uses the Mach-O binary format and does not provide `<elf.h>`. Host tools compiled during the build (`sorttable`, `modpost`, `relacheck`, `vdsomunge`, `relocs_32`, `relocs_64`) include `<elf.h>` and expect ELF types, ELF machine numbers, and relocation definitions for ARM, ARM64, and x86_64.
- **Fix**: Provide a comprehensive, self-contained [`host-include/elf.h`](file:///Users/jpgoodland/workspace/linux-kernel/host-include/elf.h) defining all standard ELF data structures and relocation constants.

---

### Trap 5: `uuid_t` Collision in `file2alias.c`
- **Symptom**:
  ```text
  scripts/mod/file2alias.c: error: array has incomplete element type 'struct uuid_t'
  ```
- **Root Cause**: macOS system header `<sys/_types/_uuid_t.h>` contains:
  ```c
  typedef __darwin_uuid_t uuid_t; /* unsigned char[16] */
  ```
  The Linux kernel tool `scripts/mod/file2alias.c` declares:
  ```c
  typedef struct { __u8 b[16]; } uuid_t;
  ```
  This causes a conflicting typedef error.
- **Fix**: In [`host-include/host_fix.h`](file:///Users/jpgoodland/workspace/linux-kernel/host-include/host_fix.h), include macOS system headers first (`<sys/types.h>`, `<unistd.h>`, `<stdlib.h>`), then define:
  ```c
  #define uuid_t kernel_uuid_t
  ```

---

### Trap 6: Missing Linux System Calls & Flags (`copy_file_range`, `O_LARGEFILE`)
- **Symptom**:
  ```text
  usr/gen_init_cpio.c: error: call to undeclared function 'copy_file_range'
  usr/gen_init_cpio.c: error: use of undeclared identifier 'O_LARGEFILE'
  ```
- **Root Cause**: `usr/gen_init_cpio.c` uses Linux `copy_file_range()` and 64-bit file flag `O_LARGEFILE`.
- **Fix**: In [`host-include/host_fix.h`](file:///Users/jpgoodland/workspace/linux-kernel/host-include/host_fix.h):
  ```c
  #ifndef O_LARGEFILE
  #define O_LARGEFILE 0
  #endif

  static inline __attribute__((unused)) ssize_t copy_file_range(int fd_in, off_t *off_in, int fd_out, off_t *off_out, size_t len, unsigned int flags) {
      errno = ENOSYS;
      return -1;
  }
  ```
  When `copy_file_range()` returns `-1` with `errno = ENOSYS`, `gen_init_cpio` automatically falls back to standard POSIX `read()`/`write()`.

---

### Trap 7: Missing Byte-Order & Endian Conversion Headers
- **Symptom**:
  ```text
  arch/arm64/kvm/hyp/nvhe/gen-hyprel.c: fatal error: 'endian.h' file not found
  tools/arch/x86/include/asm/orc_types.h: fatal error: 'asm/byteorder.h' file not found
  ```
- **Root Cause**: Linux host tools expect glibc `<endian.h>` and `<asm/byteorder.h>`.
- **Fix**:
  - Provide [`host-include/endian.h`](file:///Users/jpgoodland/workspace/linux-kernel/host-include/endian.h) mapping `htole16`, `htobe32`, `be64toh`, etc., to Darwin's `<libkern/OSByteOrder.h>` built-ins.
  - Provide [`host-include/asm/byteorder.h`](file:///Users/jpgoodland/workspace/linux-kernel/host-include/asm/byteorder.h) defining `__LITTLE_ENDIAN` and `__BYTE_ORDER`.

---

## 4. Step-by-Step Agent Porting Instructions

When setting up any clean Linux kernel source directory (e.g., `linux-7.2.7`), follow these sequential steps:

### Step 1: Install Host Prerequisites via Homebrew
Execute in the terminal:
```bash
brew install make llvm lld gnu-sed openssl flex bison libelf pkg-config
```

Verify that Homebrew binaries are accessible:
```bash
gmake --version           # Must be GNU Make 4.4+
/opt/homebrew/opt/llvm/bin/clang --version  # Upstream Clang (not Apple Clang)
gsed --version            # GNU sed 4.9+
```

---

### Step 2: Apply the 2 In-Tree Patches

Apply these two modifications to the kernel source directory:

#### Patch 1: `scripts/Kbuild.include`
In `<kernel-dir>/scripts/Kbuild.include`, replace line 65:
```diff
--- a/scripts/Kbuild.include
+++ b/scripts/Kbuild.include
@@ -62,7 +62,7 @@ stringify = $(squote)$(quote)$1$(quote)$(squote)
 
 ###
 # The path to Kbuild or Makefile. Kbuild has precedence over Makefile.
-kbuild-file = $(or $(wildcard $(src)/Kbuild),$(src)/Makefile)
+kbuild-file = $(or $(if $(wildcard $(src)/Kbuild/.),,$(wildcard $(src)/Kbuild)),$(src)/Makefile)
 
 ###
 # Read a file, replacing newlines with spaces
```

#### Patch 2: `arch/arm64/tools/gen-kernel-hwcaps.sh`
In `<kernel-dir>/arch/arm64/tools/gen-kernel-hwcaps.sh`, replace line 20:
```diff
--- a/arch/arm64/tools/gen-kernel-hwcaps.sh
+++ b/arch/arm64/tools/gen-kernel-hwcaps.sh
@@ -17,7 +17,7 @@ echo "/* Generated file - do not edit */"
 echo ""
 
 grep -E '^#define HWCAP[0-9]*_[A-Z0-9_]+' $1 | \
-	sed 's/.*HWCAP\([0-9]*\)_\([A-Z0-9_]\+\).*/#define KERNEL_HWCAP_\2\t__khwcap\1_feature(\2)/'
+	sed 's/.*HWCAP\([0-9]*\)_\([A-Z0-9_]*\).*/#define KERNEL_HWCAP_\2\t__khwcap\1_feature(\2)/'
 
 echo ""
 echo "#endif /* __ASM_KERNEL_HWCAPS_H */"
```

---

### Step 3: Verify the `host-include/` Compatibility Layer

Ensure the directory [`host-include/`](file:///Users/jpgoodland/workspace/linux-kernel/host-include/) exists alongside [`build.sh`](file:///Users/jpgoodland/workspace/linux-kernel/build.sh) with the following structure:

```text
host-include/
├── host_fix.h         # Pre-included shim: system headers, uuid_t, copy_file_range, O_LARGEFILE
├── elf.h              # Self-contained 32/64-bit ELF definitions & relocations
├── byteswap.h         # bswap16/32/64 using __builtin_bswap*
├── endian.h           # htobe*/htole* using Darwin OSByteOrder
├── asm/
│   ├── byteorder.h    # __LITTLE_ENDIAN and __BYTE_ORDER
│   ├── types.h        # __u8, __u16, __u32, __u64
│   └── posix_types.h  # __kernel_long_t definitions
```

---

### Step 4: Execute the Build Using `build.sh`

The [`build.sh`](file:///Users/jpgoodland/workspace/linux-kernel/build.sh) script handles toolchain resolution, environment exports, core selection, and execution timing.

#### To build ARM64 (default Apple Silicon target):
```bash
./build.sh --dir linux-7.2.7 --arch arm64 --cores 10 defconfig Image
```

#### To build x86_64:
```bash
./build.sh --dir linux-7.2.7 --arch x86_64 --cores 10 defconfig bzImage
```

#### To clean:
```bash
./build.sh --dir linux-7.2.7 --arch arm64 --cores 10 clean
```

---

## 5. Reference File Specifications

Below are the exact contents required for each `host-include/` compatibility file:

### `host-include/host_fix.h`
```c
#ifndef _HOST_FIX_H
#define _HOST_FIX_H

/* Include macOS system headers first so macOS declarations finish cleanly */
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>

/* Rename uuid_t for kernel host script declarations (e.g. file2alias.c) */
#define uuid_t kernel_uuid_t

#ifndef O_LARGEFILE
#define O_LARGEFILE 0
#endif

static inline __attribute__((unused)) ssize_t copy_file_range(int fd_in, off_t *off_in, int fd_out, off_t *off_out, size_t len, unsigned int flags) {
    errno = ENOSYS;
    return -1;
}

#endif
```

### `host-include/byteswap.h`
```c
#ifndef _HOST_BYTESWAP_H
#define _HOST_BYTESWAP_H

#define bswap_16(x) __builtin_bswap16(x)
#define bswap_32(x) __builtin_bswap32(x)
#define bswap_64(x) __builtin_bswap64(x)

#endif
```

### `host-include/endian.h`
```c
#ifndef _HOST_ENDIAN_H
#define _HOST_ENDIAN_H

#include <libkern/OSByteOrder.h>
#include <sys/endian.h>

#ifndef htobe16
#define htobe16(x) OSSwapHostToBigInt16(x)
#define htole16(x) OSSwapHostToLittleInt16(x)
#define be16toh(x) OSSwapBigToHostInt16(x)
#define le16toh(x) OSSwapLittleToHostInt16(x)

#define htobe32(x) OSSwapHostToBigInt32(x)
#define htole32(x) OSSwapHostToLittleInt32(x)
#define be32toh(x) OSSwapBigToHostInt32(x)
#define le32toh(x) OSSwapLittleToHostInt32(x)

#define htobe64(x) OSSwapHostToBigInt64(x)
#define htole64(x) OSSwapHostToLittleInt64(x)
#define be64toh(x) OSSwapBigToHostInt64(x)
#define le64toh(x) OSSwapLittleToHostInt64(x)
#endif

#endif
```

### `host-include/asm/byteorder.h`
```c
#ifndef _HOST_ASM_BYTEORDER_H
#define _HOST_ASM_BYTEORDER_H

#include <endian.h>

#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN 1234
#endif

#ifndef __BYTE_ORDER
#define __BYTE_ORDER __LITTLE_ENDIAN
#endif

#endif
```

### `host-include/asm/types.h`
```c
#ifndef _HOST_ASM_TYPES_H
#define _HOST_ASM_TYPES_H

#include <stdint.h>

typedef uint8_t  __u8;
typedef uint16_t __u16;
typedef uint32_t __u32;
typedef uint64_t __u64;

typedef int8_t   __s8;
typedef int16_t  __s16;
typedef int32_t  __s32;
typedef int64_t  __s64;

#endif
```

---

## 6. Diagnostic & Troubleshooting Quick Reference

| Error Message | Immediate Cause | Resolution |
| :--- | :--- | :--- |
| `make[2]: *** Documentation/Kbuild: Is a directory. Stop.` | APFS case-insensitive matching on `Documentation/kbuild/` | Apply Patch 1 to `scripts/Kbuild.include`. |
| `arch_timer.h: error: use of undeclared identifier 'KERNEL_HWCAP_EVTSTRM'` | BSD `sed` failed to process `\+` in `gen-kernel-hwcaps.sh` | Apply Patch 2 to `arch/arm64/tools/gen-kernel-hwcaps.sh`. |
| `sed: 1: "modules.builtin.modinfo": invalid command code m` | BSD `sed` does not support `-i` without backup extension | Install `gnu-sed` and prepend its `gnubin` to `PATH`. |
| `error: __typeof__ on an expression of type '... __counted_by(...)'` | Using Apple Clang (`/usr/bin/clang`) | Install Homebrew LLVM and prepend `/opt/homebrew/opt/llvm/bin` to `PATH`. |
| `scripts/elf-parse.h: fatal error: 'elf.h' file not found` | macOS SDK lacks `<elf.h>` | Pass `HOSTCFLAGS="-include .../host_fix.h -I.../host-include"`. |
| `file2alias.c: error: redefinition of 'uuid_t'` | Darwin `uuid_t` typedef conflicts with Linux `struct uuid_t` | Check `#define uuid_t kernel_uuid_t` in `host_fix.h`. |
| `gen-hyprel.c: fatal error: 'endian.h' file not found` | macOS uses `<sys/endian.h>` / `<libkern/OSByteOrder.h>` | Ensure `host-include/endian.h` is present. |
| `relacheck.c: error: use of undeclared identifier 'R_AARCH64_ABS64'` | Missing AArch64 relocations in host ELF header | Verify `R_AARCH64_ABS64` (257) and `R_AARCH64_PREL64` (260) in `host-include/elf.h`. |
| `vdsomunge.c: error: call to undeclared function 'EF_ARM_EABI_VERSION'` | Missing ARM EABI definitions | Verify `EF_ARM_EABI_VERSION` and `EF_ARM_EABI_VER5` in `host-include/elf.h`. |
| `relocs.c: error: use of undeclared identifier 'R_X86_64_NONE'` | Missing x86_64 relocations for x86 build | Verify `R_X86_64_*` definitions in `host-include/elf.h`. |
| `ld64.lld: error: unknown argument '--fatal-warnings'` | Host linker invoked with GNU ld flags against macOS ld64 | Ensure `-Wno-macro-redefined` is passed and `PATH` points to Homebrew `lld`. |

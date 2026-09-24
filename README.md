# Linux Kernel macOS Build Utilities

A suite of utility scripts and compatibility shims for downloading, configuring, patching, and building upstream Linux kernels on macOS (Apple Silicon & LLVM).

## Quick Start

### 1. Configure macOS Host Environment & Dependencies
Run the automated configuration script to assess your system, install missing Homebrew packages, configure compiler PATHs, and verify host toolchain integrity:
```bash
./mac-configure.sh
```

### 2. Download & Extract Linux Kernel Source
Run the interactive utility to pull the desired kernel version from [kernel.org](https://kernel.org):
```bash
./kernel-get.sh
```

Or specify release categories / versions directly via CLI options:
```bash
# Download latest mainline release
./kernel-get.sh -t mainline

# Download latest stable release
./kernel-get.sh -t stable

# Download specific longterm series (e.g. 6.12.x)
./kernel-get.sh -t longterm -M 6 -m 12

# Download specific kernel version
./kernel-get.sh -v 7.2.7
```

### 3. Apply macOS In-Tree Patches
Apply the APFS case-insensitivity and BSD tool compatibility fixes automatically to the extracted kernel tree:
```bash
./kernel-patch.sh linux-7.2.7
```
*(Refer to [MACOS_BUILD_GUIDE.md](file:///Users/jpgoodland/workspace/linux-kernel-mac-build-utils/MACOS_BUILD_GUIDE.md) for full architectural explanations of these patches.)*

### 4. Build Kernel Image with LLVM
Use [build.sh](file:///Users/jpgoodland/workspace/linux-kernel-mac-build-utils/build.sh) to build the kernel using LLVM and macOS host compatibility shims:
```bash
# Interactive mode:
./build.sh

# Or directly targeting ARM64 / x86_64:
./build.sh --dir linux-7.2.7 --arch arm64 defconfig Image
./build.sh --dir linux-7.2.7 --arch x86_64 defconfig bzImage
```

---

## Running Tests

Execute the automated test suite covering host compatibility headers, CLI utilities, and syntax checks:
```bash
./tests/run_tests.sh
```

The test suite includes:
- **`tests/test_host_headers.c`**: Verifies all Darwin `<libkern>` shims, ELF relocations, byte-swapping macros, and integer type definitions under Clang.
- **`tests/test_scripts.sh`**: Validates syntax, command-line arguments, release manifest queries, patching logic, and dry-run flows across `mac-configure.sh`, `kernel-get.sh`, `kernel-patch.sh`, and `build.sh`.

## Continuous Integration (CI)
GitHub Actions CI runs on Apple Silicon runners (`macos-14` / ARM64) configured in [`.github/workflows/macos-ci.yml`](file:///.github/workflows/macos-ci.yml) to automatically validate all builds, unit tests, and kernel configuration (`defconfig`) on every push and pull request.

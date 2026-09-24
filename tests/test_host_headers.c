/*
 * test_host_headers.c - Verification test for host-include headers on macOS
 */

#include <stdio.h>
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "host_fix.h"
#include "elf.h"
#include "byteswap.h"
#include "endian.h"
#include "asm/byteorder.h"
#include "asm/types.h"
#include "asm/posix_types.h"

int main(void) {
    printf("[TEST] Verifying host-include headers on macOS...\n");

    /* 1. Test Byte Swap Macros */
    assert(bswap_16(0x1234) == 0x3412);
    assert(bswap_32(0x12345678) == 0x78563412);
    assert(bswap_64(0x0123456789ABCDEFULL) == 0xEFCDAB8967452301ULL);
    printf("  [PASS] Byte swap macros (bswap_16, bswap_32, bswap_64)\n");

    /* 2. Test Endian Conversion */
    uint16_t val16 = 0x1234;
    uint32_t val32 = 0x12345678;
    uint64_t val64 = 0x0123456789ABCDEFULL;
#if __BYTE_ORDER == __LITTLE_ENDIAN
    assert(htole16(val16) == val16);
    assert(htole32(val32) == val32);
    assert(htole64(val64) == val64);
    assert(htobe16(val16) == bswap_16(val16));
    assert(htobe32(val32) == bswap_32(val32));
    assert(htobe64(val64) == bswap_64(val64));
#endif
    printf("  [PASS] Endian conversion macros and byteorder detection\n");

    /* 3. Test ELF Header Definitions & Constants */
    assert(EI_NIDENT == 16);
    assert(ELFCLASS32 == 1);
    assert(ELFCLASS64 == 2);
    assert(ELFDATA2LSB == 1);
    assert(ELFDATA2MSB == 2);
    assert(EM_ARM == 40);
    assert(EM_X86_64 == 62);
    assert(EM_AARCH64 == 183);

    /* Test Relocation Constants */
    assert(R_AARCH64_ABS64 == 257);
    assert(R_AARCH64_PREL64 == 260);
    assert(R_X86_64_NONE == 0);
    assert(R_X86_64_64 == 1);
    assert(R_X86_64_PC32 == 2);
    assert(R_ARM_PC24 == 1);
    assert(R_ARM_ABS32 == 2);

    /* Test ELF Structure Sizes */
    assert(sizeof(Elf32_Ehdr) == 52);
    assert(sizeof(Elf64_Ehdr) == 64);
    assert(sizeof(Elf32_Shdr) == 40);
    assert(sizeof(Elf64_Shdr) == 64);
    assert(sizeof(Elf32_Sym) == 16);
    assert(sizeof(Elf64_Sym) == 24);
    printf("  [PASS] ELF headers, data structures, and relocation constants\n");

    /* 4. Test Kernel Int Types */
    assert(sizeof(__u8) == 1);
    assert(sizeof(__s8) == 1);
    assert(sizeof(__u16) == 2);
    assert(sizeof(__s16) == 2);
    assert(sizeof(__u32) == 4);
    assert(sizeof(__s32) == 4);
    assert(sizeof(__u64) == 8);
    assert(sizeof(__s64) == 8);
    printf("  [PASS] Linux kernel primitive integer types (__u8 .. __u64)\n");

    /* 5. Test Host Fix Declarations (copy_file_range fallback, O_LARGEFILE) */
    assert(O_LARGEFILE == 0);
    int dummy = 0;
    assert(copy_file_range(dummy, NULL, dummy, NULL, 0, 0) == -1);
    printf("  [PASS] Host fix shim declarations and copy_file_range fallback\n");

    printf("[SUCCESS] All host header verification tests passed!\n");
    return 0;
}

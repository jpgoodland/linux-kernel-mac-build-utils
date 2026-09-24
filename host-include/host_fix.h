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
    (void)fd_in;
    (void)off_in;
    (void)fd_out;
    (void)off_out;
    (void)len;
    (void)flags;
    errno = ENOSYS;
    return -1;
}

#endif

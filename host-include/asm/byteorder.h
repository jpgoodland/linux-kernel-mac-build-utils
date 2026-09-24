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

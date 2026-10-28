#ifndef GLANCE_PLATFORM_H
#define GLANCE_PLATFORM_H

#include <IOKit/IOKitLib.h>
#include <notify.h>
#include <stdint.h>

typedef struct {
    uint32_t data_type;
    uint32_t data_size;
    uint8_t bytes[32];
} GlanceSMCValue;

kern_return_t glance_smc_read(io_connect_t connection, uint32_t key, GlanceSMCValue *value);

#endif

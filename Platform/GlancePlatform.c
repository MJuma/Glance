#include "GlancePlatform.h"
#include <stddef.h>
#include <string.h>

/* AppleSMC's undocumented wire layout is deliberately confined to this bridge. */
typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } version;
    struct { uint16_t version, length; uint32_t cpu, gpu, memory; } limits;
    struct { uint32_t size, type; uint8_t attributes; } info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCKeyData;

_Static_assert(sizeof(SMCKeyData) == 80, "Unexpected AppleSMC message size");
_Static_assert(offsetof(SMCKeyData, bytes) == 48, "Unexpected AppleSMC payload offset");

kern_return_t glance_smc_read(io_connect_t connection, uint32_t key, GlanceSMCValue *value) {
    SMCKeyData input = {0}, output = {0};
    size_t size = sizeof(output);
    input.key = key;
    input.command = 9;
    kern_return_t result = IOConnectCallStructMethod(connection, 2, &input, sizeof(input), &output, &size);
    if (result != KERN_SUCCESS) return result;
    if (size != sizeof(output)) return kIOReturnUnderrun;
    if (output.result != 0 || output.info.size == 0) return kIOReturnNotFound;
    if (output.info.size > sizeof(value->bytes)) return kIOReturnOverrun;
    value->data_type = output.info.type;
    value->data_size = output.info.size;

    input.command = 5;
    input.info.size = output.info.size;
    size = sizeof(output);
    memset(&output, 0, sizeof(output));
    result = IOConnectCallStructMethod(connection, 2, &input, sizeof(input), &output, &size);
    if (result != KERN_SUCCESS) return result;
    if (size != sizeof(output)) return kIOReturnUnderrun;
    if (output.result != 0) return kIOReturnNotFound;
    memcpy(value->bytes, output.bytes, value->data_size);
    return KERN_SUCCESS;
}

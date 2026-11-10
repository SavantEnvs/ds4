/* Fuzzes the --prompt-prefix transcript parser (USER:/ASSISTANT: turns). */
#include "../ds4_prompt_prefix.h"

#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return -1;
    ds4_prompt_prefix prefix = {0};
    char err[256];
    if (ds4_prompt_prefix_parse(&prefix, (const char *)data, size, err, sizeof(err)) == 0)
        ds4_prompt_prefix_free(&prefix);
    return 0;
}

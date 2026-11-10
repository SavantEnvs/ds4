/* Fuzzes the built-in PNG/JPEG decoders (ds4_image_decode_memory) and, for images small enough
 * to keep an exec fast, the model-specific patch preprocessors that run on the decoded pixels. */
#include "../ds4_image.h"

#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 8) return -1;
    ds4_image image;
    char err[160];
    if (!ds4_image_decode_memory(&image, data, size, err, sizeof(err))) return 0;

    if ((uint64_t)image.width * image.height <= (1u << 20)) {
        switch (image.fingerprint[0] & 3) {
        case 0: {
            ds4_image_patches p = {0};
            if (ds4_image_preprocess_glm53(&p, &image, 16u, 8000u, err, sizeof(err)))
                ds4_image_patches_free(&p);
            break;
        }
        case 1: {
            ds4_image_patches p = {0};
            if (ds4_image_preprocess_qwen4(&p, &image, 16u, 8000u, err, sizeof(err)))
                ds4_image_patches_free(&p);
            break;
        }
        case 2: {
            ds4_deepseek4_image_patches p = {0};
            if (ds4_image_preprocess_deepseek4(&p, &image, err, sizeof(err)))
                ds4_deepseek4_image_patches_free(&p);
            break;
        }
        default: {
            ds4_deepseek4_image_patches p = {0};
            if (ds4_image_preprocess_deepseek41(&p, &image, err, sizeof(err)))
                ds4_deepseek4_image_patches_free(&p);
            break;
        }
        }
    }
    ds4_image_free(&image);
    return 0;
}

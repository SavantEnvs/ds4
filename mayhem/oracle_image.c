/* Prints "<width>x<height> <sha256 fingerprint>" of an image decoded by ds4_image_decode_file,
 * so mayhem/test.sh can compare against known-good values (libjpeg-turbo bit-exact). */
#include "../ds4_image.h"
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    ds4_image image = {0};
    char error[160] = {0};
    if (!ds4_image_decode_file(&image, argv[1], error, sizeof(error))) {
        fprintf(stderr, "decode failed: %s\n", error);
        return 1;
    }
    printf("%ux%u ", image.width, image.height);
    for (int i = 0; i < 32; i++) printf("%02x", image.fingerprint[i]);
    printf("\n");
    ds4_image_free(&image);
    return 0;
}

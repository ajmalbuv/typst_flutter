#include <stdint.h>

// A dummy function to ensure the library is not stripped.
// This is required for FFI plugins on Apple platforms.
int32_t typst_flutter_dummy_method_to_enforce_bundling(void) {
    return 0;
}

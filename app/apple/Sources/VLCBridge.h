// Bridging header: libvlc C API from VLCKit (macOS only, ADR-0008).
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <vlc/vlc.h>
#endif

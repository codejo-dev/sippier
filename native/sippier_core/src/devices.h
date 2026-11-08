/*
 * Audio device list and default-device watcher (devices.c).
 */
#include <stdbool.h>

struct odict;

/* Called on a system thread when the default input or output changes */
typedef void (devices_default_h)(bool input);

/* Adds "input" and "output" arrays of {id, name} and, where known,
 * "defaultInput" and "defaultOutput" ids to od. Devices of the given audio
 * module, or the system's on macOS. */
int  devices_encode(struct odict *od, const char *module);
int  devices_watch(devices_default_h *h);
void devices_unwatch(void);

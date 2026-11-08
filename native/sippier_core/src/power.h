/*
 * System sleep and wake (power.c). The system announces sleep and waits
 * until power_sleep_ok(), so the core can unregister first: macOS at most
 * 30 s, Windows about 2 s.
 */
#include <stdbool.h>

/* Called on a system thread; ack is for power_sleep_ok() (sleep only) */
typedef void (power_h)(bool sleep, void *ack);

int  power_watch(power_h *h);
void power_unwatch(void);
void power_sleep_ok(void *ack);

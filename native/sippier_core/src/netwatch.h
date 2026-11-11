/*
 * Changes of the system's network (netwatch.c), on macOS and Windows.
 * Android reports them itself (PlatformChannel.kt, sc_network_changed).
 */

/* Called on a system thread, also once right after netwatch_start() */
typedef void (netwatch_h)(void);

int  netwatch_start(netwatch_h *h);
void netwatch_stop(void);

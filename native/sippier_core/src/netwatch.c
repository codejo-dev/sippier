/*
 * Changes of the system's network: Wi-Fi joined, switched or back after
 * sleep, a cable, a VPN. The core then binds its SIP transports to the new
 * addresses, reads the DNS servers again and registers. Started at login,
 * the core can come up before the network, so this is also how it
 * registers then.
 *
 * macOS: Network.framework's path monitor. Windows: IP address change
 * notifications. Android reports changes itself (PlatformChannel.kt).
 */
#include <re.h>
#include "netwatch.h"

#ifdef __APPLE__
#include <Network/Network.h>

static nw_path_monitor_t monitor;
static netwatch_h *handler;


int netwatch_start(netwatch_h *h)
{
	monitor = nw_path_monitor_create();
	if (!monitor)
		return ENOMEM;

	handler = h;
	nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
		netwatch_h *cb = handler;

		(void)path;
		if (cb)
			cb();
	});
	nw_path_monitor_set_queue(monitor,
				  dispatch_get_global_queue(QOS_CLASS_UTILITY,
							    0));
	nw_path_monitor_start(monitor);

	return 0;
}


void netwatch_stop(void)
{
	if (!monitor)
		return;

	handler = NULL;
	nw_path_monitor_cancel(monitor);
	nw_release(monitor);
	monitor = NULL;
}

#elif defined(_WIN32)
#include <winsock2.h>
#include <ws2ipdef.h>
#include <iphlpapi.h>

static HANDLE notify;
static netwatch_h *handler;


static VOID WINAPI address_changed(PVOID ctx, PMIB_UNICASTIPADDRESS_ROW row,
				   MIB_NOTIFICATION_TYPE type)
{
	netwatch_h *h = handler;
	(void)ctx;
	(void)row;
	(void)type;

	if (h)
		h();
}


int netwatch_start(netwatch_h *h)
{
	handler = h;
	if (NotifyUnicastIpAddressChange(AF_UNSPEC, address_changed, NULL,
					 TRUE, &notify) != NO_ERROR) {
		handler = NULL;
		notify = NULL;
		return EIO;
	}

	return 0;
}


void netwatch_stop(void)
{
	if (!notify)
		return;

	handler = NULL;
	CancelMibChangeNotify2(notify);
	notify = NULL;
}

#else

int netwatch_start(netwatch_h *h)
{
	(void)h;
	return 0;
}


void netwatch_stop(void)
{
}

#endif

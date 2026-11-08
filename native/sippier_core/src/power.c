/*
 * System sleep and wake. A sleeping computer can't take calls, and the
 * provider would keep sending them to its registration, so the core
 * unregisters before sleep and registers again after wake.
 *
 * macOS: IOKit's system power notifications. Windows: a suspend/resume
 * callback, which needs no window. Android keeps the CPU awake or wakes it
 * by alarm instead (SipService.kt, sc_keepalive).
 */
#include <re.h>
#include <baresip.h>
#include "power.h"

#ifdef __APPLE__
#include <dispatch/dispatch.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

static io_connect_t root;
static IONotificationPortRef port;
static io_object_t notifier;
static power_h *handler;


static void power_callback(void *refcon, io_service_t service, natural_t type,
			   void *arg)
{
	power_h *h = handler;
	(void)refcon;
	(void)service;

	switch (type) {

	/* idle sleep may go ahead; what to do comes with WillSleep */
	case kIOMessageCanSystemSleep:
		IOAllowPowerChange(root, (long)arg);
		break;

	case kIOMessageSystemWillSleep:
		if (h)
			h(true, arg);
		else
			IOAllowPowerChange(root, (long)arg);
		break;

	case kIOMessageSystemHasPoweredOn:
		if (h)
			h(false, NULL);
		break;

	default:
		break;
	}
}


int power_watch(power_h *h)
{
	handler = h;
	root = IORegisterForSystemPower(NULL, &port, power_callback,
					&notifier);
	if (!root) {
		handler = NULL;
		return EIO;
	}

	IONotificationPortSetDispatchQueue(port,
		dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));

	return 0;
}


void power_unwatch(void)
{
	if (!root)
		return;

	handler = NULL;
	IODeregisterForSystemPower(&notifier);
	IOServiceClose(root);
	IONotificationPortDestroy(port);
	root = 0;
	port = NULL;
}


void power_sleep_ok(void *ack)
{
	if (root)
		IOAllowPowerChange(root, (long)ack);
}

#elif defined(_WIN32)
/* after re.h, which brings winsock2.h */
#include <windows.h>
#include <powrprof.h>

#ifndef DEVICE_NOTIFY_CALLBACK
/* As in the Windows SDK's powrprof.h; MinGW-w64 lacks them */
#define DEVICE_NOTIFY_CALLBACK 2
typedef ULONG CALLBACK DEVICE_NOTIFY_CALLBACK_ROUTINE(PVOID context,
						      ULONG type,
						      PVOID setting);
typedef struct {
	DEVICE_NOTIFY_CALLBACK_ROUTINE *Callback;
	PVOID Context;
} DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS;
#endif

/* Windows gives a suspend about 2 s; returning from the callback lets it
 * go ahead */
#define SLEEP_BUDGET_MS 1800

static HPOWERNOTIFY notify;
static HANDLE ack_event;
static power_h *handler;


static ULONG CALLBACK power_callback(PVOID ctx, ULONG type, PVOID setting)
{
	power_h *h = handler;
	(void)ctx;
	(void)setting;

	switch (type) {

	case PBT_APMSUSPEND:
		if (h) {
			ResetEvent(ack_event);
			h(true, ack_event);
			WaitForSingleObject(ack_event, SLEEP_BUDGET_MS);
		}
		break;

	/* after every wake, also when no user is there yet */
	case PBT_APMRESUMEAUTOMATIC:
		if (h)
			h(false, NULL);
		break;

	default:
		break;
	}

	return 0;
}


int power_watch(power_h *h)
{
	static DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS params = {
		power_callback, NULL };

	ack_event = CreateEventW(NULL, TRUE, FALSE, NULL);
	if (!ack_event)
		return ENOMEM;

	handler = h;
	if (PowerRegisterSuspendResumeNotification(DEVICE_NOTIFY_CALLBACK,
						   (HANDLE)&params, &notify)) {
		handler = NULL;
		CloseHandle(ack_event);
		ack_event = NULL;
		return EIO;
	}

	return 0;
}


void power_unwatch(void)
{
	if (!notify)
		return;

	handler = NULL;
	PowerUnregisterSuspendResumeNotification(notify);
	notify = NULL;
	CloseHandle(ack_event);
	ack_event = NULL;
}


void power_sleep_ok(void *ack)
{
	if (ack && ack == ack_event)
		SetEvent(ack);
}

#else

int power_watch(power_h *h)
{
	(void)h;
	return 0;
}


void power_unwatch(void)
{
}


void power_sleep_ok(void *ack)
{
	(void)ack;
}

#endif

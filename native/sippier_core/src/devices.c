/*
 * Audio devices: the list for the settings, and a watcher for changes of
 * the system's default devices.
 *
 * macOS asks CoreAudio directly, with the device UID as id (what the
 * patched audiounit module opens), so the list is always current. Windows
 * asks the MMDevice API the same way, with the endpoint id (what wasapi
 * opens). Elsewhere the list comes from the audio module, with the device
 * name as id; Android's aaudio lists none, as the system routes audio.
 */
#include <re.h>
#include <baresip.h>
#include "devices.h"

#ifdef __APPLE__
#include <CoreAudio/CoreAudio.h>
#elif defined(_WIN32)
/* after re.h, which brings winsock2.h */
#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#endif


static int add_device(struct odict *arr, unsigned idx, const char *id,
		      const char *name)
{
	struct odict *o;
	char key[16];
	int err;

	err = odict_alloc(&o, 4);
	if (err)
		return err;

	err  = odict_entry_add(o, "id", ODICT_STRING, id);
	err |= odict_entry_add(o, "name", ODICT_STRING, name);
	re_snprintf(key, sizeof(key), "%u", idx);
	if (!err)
		err = odict_entry_add(arr, key, ODICT_OBJECT, o);

	mem_deref(o);
	return err;
}


#ifdef __APPLE__

static devices_default_h *default_h;

static const AudioObjectPropertyAddress default_in = {
	kAudioHardwarePropertyDefaultInputDevice,
	kAudioObjectPropertyScopeGlobal,
	kAudioObjectPropertyElementMain };

static const AudioObjectPropertyAddress default_out = {
	kAudioHardwarePropertyDefaultOutputDevice,
	kAudioObjectPropertyScopeGlobal,
	kAudioObjectPropertyElementMain };


static bool get_string(AudioObjectID id, AudioObjectPropertySelector sel,
		       char *buf, size_t sz)
{
	AudioObjectPropertyAddress a = {
		sel, kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain };
	CFStringRef s = NULL;
	UInt32 size = sizeof(s);
	bool ok;

	if (AudioObjectGetPropertyData(id, &a, 0, NULL, &size, &s) || !s)
		return false;

	ok = CFStringGetCString(s, buf, (CFIndex)sz, kCFStringEncodingUTF8);
	CFRelease(s);

	return ok;
}


static bool has_streams(AudioObjectID id, bool input)
{
	AudioObjectPropertyAddress a = {
		kAudioDevicePropertyStreams,
		input ? kAudioObjectPropertyScopeInput :
			kAudioObjectPropertyScopeOutput,
		kAudioObjectPropertyElementMain };
	UInt32 size = 0;

	return !AudioObjectGetPropertyDataSize(id, &a, 0, NULL, &size) &&
		size > 0;
}


static bool is_hidden(AudioObjectID id)
{
	AudioObjectPropertyAddress a = {
		kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain };
	UInt32 hidden = 0, size = sizeof(hidden);

	return !AudioObjectGetPropertyData(id, &a, 0, NULL, &size, &hidden) &&
		hidden;
}


static int add_default(struct odict *od, const char *key,
		       const AudioObjectPropertyAddress *a)
{
	AudioObjectID id = kAudioObjectUnknown;
	UInt32 size = sizeof(id);
	char uid[256];

	if (AudioObjectGetPropertyData(kAudioObjectSystemObject, a, 0, NULL,
				       &size, &id) ||
	    !get_string(id, kAudioDevicePropertyDeviceUID, uid, sizeof(uid)))
		return 0;

	return odict_entry_add(od, key, ODICT_STRING, uid);
}


int devices_encode(struct odict *od, const char *module)
{
	AudioObjectPropertyAddress a = {
		kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain };
	struct odict *in = NULL, *out = NULL;
	AudioObjectID *ids = NULL;
	unsigned nin = 0, nout = 0;
	char uid[256], name[256];
	UInt32 size = 0;
	int err;
	(void)module;

	err  = odict_alloc(&in, 8);
	err |= odict_alloc(&out, 8);
	if (err)
		goto out;

	if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0,
					   NULL, &size)) {
		err = EIO;
		goto out;
	}

	ids = mem_alloc(size ? size : 1, NULL);
	if (!ids) {
		err = ENOMEM;
		goto out;
	}

	if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL,
				       &size, ids)) {
		err = EIO;
		goto out;
	}

	for (size_t i = 0; i < size / sizeof(*ids); i++) {

		if (is_hidden(ids[i]) ||
		    !get_string(ids[i], kAudioDevicePropertyDeviceUID,
				uid, sizeof(uid)) ||
		    !get_string(ids[i], kAudioObjectPropertyName,
				name, sizeof(name)))
			continue;

		if (has_streams(ids[i], true))
			err |= add_device(in, nin++, uid, name);
		if (has_streams(ids[i], false))
			err |= add_device(out, nout++, uid, name);
	}

	err |= odict_entry_add(od, "input", ODICT_ARRAY, in);
	err |= odict_entry_add(od, "output", ODICT_ARRAY, out);
	err |= add_default(od, "defaultInput", &default_in);
	err |= add_default(od, "defaultOutput", &default_out);

 out:
	mem_deref(ids);
	mem_deref(in);
	mem_deref(out);

	return err;
}


static OSStatus default_changed(AudioObjectID obj, UInt32 n,
				const AudioObjectPropertyAddress *addrs,
				void *arg)
{
	devices_default_h *h = default_h;
	(void)obj;
	(void)arg;

	for (UInt32 i = 0; i < n && h; i++)
		h(addrs[i].mSelector ==
		  kAudioHardwarePropertyDefaultInputDevice);

	return noErr;
}


int devices_watch(devices_default_h *h)
{
	OSStatus ret;

	default_h = h;
	ret  = AudioObjectAddPropertyListener(kAudioObjectSystemObject,
					      &default_in, default_changed,
					      NULL);
	ret |= AudioObjectAddPropertyListener(kAudioObjectSystemObject,
					      &default_out, default_changed,
					      NULL);

	return ret ? EIO : 0;
}


void devices_unwatch(void)
{
	AudioObjectRemovePropertyListener(kAudioObjectSystemObject,
					  &default_in, default_changed, NULL);
	AudioObjectRemovePropertyListener(kAudioObjectSystemObject,
					  &default_out, default_changed, NULL);
	default_h = NULL;
}

#elif defined(_WIN32)

static devices_default_h *default_h;
static IMMDeviceEnumerator *watch_enum;


static int to_utf8(char *buf, size_t sz, LPCWSTR s)
{
	return s && WideCharToMultiByte(CP_UTF8, 0, s, -1, buf, (int)sz, NULL,
					NULL) ? 0 : EINVAL;
}


static IMMDeviceEnumerator *enumerator_new(void)
{
	IMMDeviceEnumerator *e = NULL;

	if (FAILED(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL,
				    CLSCTX_ALL, &IID_IMMDeviceEnumerator,
				    (void **)&e)))
		return NULL;

	return e;
}


static int add_endpoint(struct odict *arr, unsigned idx, IMMDevice *dev)
{
	IPropertyStore *store = NULL;
	LPWSTR wid = NULL;
	PROPVARIANT name;
	char id[256], nm[256];
	int err = EIO;

	PropVariantInit(&name);

	if (SUCCEEDED(IMMDevice_GetId(dev, &wid)) &&
	    SUCCEEDED(IMMDevice_OpenPropertyStore(dev, STGM_READ, &store)) &&
	    SUCCEEDED(IPropertyStore_GetValue(store, &PKEY_Device_FriendlyName,
					      &name)) &&
	    name.vt == VT_LPWSTR &&
	    !to_utf8(id, sizeof(id), wid) &&
	    !to_utf8(nm, sizeof(nm), name.pwszVal))
		err = add_device(arr, idx, id, nm);

	PropVariantClear(&name);
	if (store)
		IPropertyStore_Release(store);
	CoTaskMemFree(wid);

	return err;
}


static int add_list(struct odict *od, const char *key, const char *defkey,
		    IMMDeviceEnumerator *e, EDataFlow flow)
{
	IMMDeviceCollection *coll = NULL;
	IMMDevice *dev = NULL;
	struct odict *arr;
	UINT count = 0;
	unsigned n = 0;
	int err;

	err = odict_alloc(&arr, 8);
	if (err)
		return err;

	if (SUCCEEDED(IMMDeviceEnumerator_EnumAudioEndpoints(
			      e, flow, DEVICE_STATE_ACTIVE, &coll)))
		(void)IMMDeviceCollection_GetCount(coll, &count);

	for (UINT i = 0; i < count; i++) {
		if (FAILED(IMMDeviceCollection_Item(coll, i, &dev)))
			continue;
		if (!add_endpoint(arr, n, dev))
			++n;
		IMMDevice_Release(dev);
	}

	/* wasapi opens the default communications device */
	if (SUCCEEDED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(
			      e, flow, eCommunications, &dev))) {
		LPWSTR wid = NULL;
		char id[256];

		if (SUCCEEDED(IMMDevice_GetId(dev, &wid)) &&
		    !to_utf8(id, sizeof(id), wid))
			err |= odict_entry_add(od, defkey, ODICT_STRING, id);
		CoTaskMemFree(wid);
		IMMDevice_Release(dev);
	}

	err |= odict_entry_add(od, key, ODICT_ARRAY, arr);
	if (coll)
		IMMDeviceCollection_Release(coll);
	mem_deref(arr);

	return err;
}


int devices_encode(struct odict *od, const char *module)
{
	IMMDeviceEnumerator *e;
	HRESULT hr;
	int err;
	(void)module;

	/* Any thread may ask. One that already has COM (Flutter's, as an
	 * apartment) keeps it. */
	hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);

	e = enumerator_new();
	if (e) {
		err  = add_list(od, "input", "defaultInput", e, eCapture);
		err |= add_list(od, "output", "defaultOutput", e, eRender);
		IMMDeviceEnumerator_Release(e);
	}
	else {
		err = EIO;
	}

	if (SUCCEEDED(hr))
		CoUninitialize();

	return err;
}


/* IMMNotificationClient, static and without reference counting */
static HRESULT STDMETHODCALLTYPE nc_query(IMMNotificationClient *nc,
					  REFIID riid, void **ppv)
{
	if (IsEqualIID(riid, &IID_IUnknown) ||
	    IsEqualIID(riid, &IID_IMMNotificationClient)) {
		*ppv = nc;
		return S_OK;
	}

	*ppv = NULL;
	return E_NOINTERFACE;
}


static ULONG STDMETHODCALLTYPE nc_ref(IMMNotificationClient *nc)
{
	(void)nc;
	return 1;
}


static HRESULT STDMETHODCALLTYPE nc_state(IMMNotificationClient *nc,
					  LPCWSTR id, DWORD state)
{
	(void)nc;
	(void)id;
	(void)state;
	return S_OK;
}


static HRESULT STDMETHODCALLTYPE nc_device(IMMNotificationClient *nc,
					   LPCWSTR id)
{
	(void)nc;
	(void)id;
	return S_OK;
}


static HRESULT STDMETHODCALLTYPE nc_default(IMMNotificationClient *nc,
					    EDataFlow flow, ERole role,
					    LPCWSTR id)
{
	devices_default_h *h = default_h;
	(void)nc;
	(void)id;

	/* reported per role; wasapi follows the communications device */
	if (h && role == eCommunications && flow != eAll)
		h(flow == eCapture);

	return S_OK;
}


static HRESULT STDMETHODCALLTYPE nc_property(IMMNotificationClient *nc,
					     LPCWSTR id, const PROPERTYKEY key)
{
	(void)nc;
	(void)id;
	(void)key;
	return S_OK;
}


static IMMNotificationClientVtbl nc_vtbl = {
	nc_query, nc_ref, nc_ref, nc_state, nc_device, nc_device, nc_default,
	nc_property,
};
static IMMNotificationClient notification_client = { &nc_vtbl };


/* On the re thread, which keeps COM until devices_unwatch() */
int devices_watch(devices_default_h *h)
{
	HRESULT hr;

	hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
	if (FAILED(hr))
		return EIO;

	watch_enum = enumerator_new();
	if (!watch_enum)
		goto fail;

	default_h = h;
	if (FAILED(IMMDeviceEnumerator_RegisterEndpointNotificationCallback(
			   watch_enum, &notification_client)))
		goto fail;

	return 0;

 fail:
	default_h = NULL;
	if (watch_enum)
		IMMDeviceEnumerator_Release(watch_enum);
	watch_enum = NULL;
	CoUninitialize();
	return EIO;
}


void devices_unwatch(void)
{
	if (!watch_enum)
		return;

	IMMDeviceEnumerator_UnregisterEndpointNotificationCallback(
		watch_enum, &notification_client);
	IMMDeviceEnumerator_Release(watch_enum);
	watch_enum = NULL;
	default_h = NULL;
	CoUninitialize();
}

#else

static int add_list(struct odict *od, const char *key, const char *defkey,
		    const struct list *devs, bool input)
{
	struct odict *arr;
	unsigned n = 0;
	int err;

	err = odict_alloc(&arr, 8);
	if (err)
		return err;

	for (struct le *le = list_head(devs); le; le = le->next) {
		const struct mediadev *dev = le->data;
		bool def = input ? dev->src.is_default : dev->play.is_default;

		err |= add_device(arr, n++, dev->name, dev->name);
		if (def)
			err |= odict_entry_add(od, defkey, ODICT_STRING,
					       dev->name);
	}

	err |= odict_entry_add(od, key, ODICT_ARRAY, arr);
	mem_deref(arr);

	return err;
}


int devices_encode(struct odict *od, const char *module)
{
	const struct ausrc *as = ausrc_find(baresip_ausrcl(), module);
	const struct auplay *ap = auplay_find(baresip_auplayl(), module);
	int err;

	err  = add_list(od, "input", "defaultInput",
			as ? &as->dev_list : NULL, true);
	err |= add_list(od, "output", "defaultOutput",
			ap ? &ap->dev_list : NULL, false);

	return err;
}


int devices_watch(devices_default_h *h)
{
	(void)h;
	return 0;
}


void devices_unwatch(void)
{
}

#endif

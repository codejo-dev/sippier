/*
 * sippier_core: thin C layer over baresip. See include/sippier_core.h.
 */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <re.h>
#include <rem.h>
#include <baresip.h>
#include "sippier_core.h"
#include "devices.h"
#include "netwatch.h"
#include "power.h"
#include "ringtone.h"
#ifdef SIPPIER_AEC
#include "aec.h"
#endif

#ifdef __ANDROID__
#include <dirent.h>
#include <errno.h>
#include <android/log.h>
#endif

#ifdef _WIN32
/* after re.h, which brings winsock2.h */
#include <errno.h>
#include <windows.h>
#include <wincrypt.h>
#endif

#define MAX_ACCOUNTS 16
#define MAX_DNS_SERVERS 8
#define DTMF_TONE_MS 120

#define SLEEP_WAIT_MS 3000   /* for unregisters to be confirmed */
#define WAKE_RETRY_MS 3000   /* the network can take a while after wake */
#define WAKE_TRIES    10
/* Wi-Fi, its addresses and DNS servers come one after the other */
#define NETWORK_SETTLE_MS 2000
/* Android battery saver (sc_keepalive) */
#define KEEPALIVE_MIN_MS  30000
#define KEEPALIVE_MAX_MS  (15 * 60000)
#define REFRESH_WAIT_MS   (5 * 60000)  /* answer to a refresh overdue */
/* Routers drop idle UDP mappings (Linux-based ones after 120-180 s), and
 * with them the way in for calls. fonial pings every 30 s, Vodafone never;
 * the battery saver wakes the phone for it less often. */
#define NAT_KEEPALIVE_MS        25000
#define NAT_KEEPALIVE_SAVER_MS  60000

/* mqueue ids: the system's default input or output device changed; the
 * system is about to sleep, or woke up; its network changed */
enum { MQ_DEFAULT_IN = 1, MQ_DEFAULT_OUT, MQ_SLEEP, MQ_WAKE, MQ_NETWORK };

#if defined(__ANDROID__)
#define AUDIO_MODULE "aaudio"
/* No CA bundle file on Android; write_ca_bundle() builds one at start. A/AAAA
 * lookups use the system resolver (works without a server list, follows
 * Private DNS and DNS64); SRV/NAPTR need sc_set_dns_servers(). */
#define PLATFORM_CONFIG "dns_getaddrinfo\tyes\n"
#elif defined(_WIN32)
/* wasapi opens the default communications devices. No CA bundle file on
 * Windows either; write_ca_bundle() exports the system's roots at start. */
#define AUDIO_MODULE "wasapi"
#define PLATFORM_CONFIG ""
#else
#define AUDIO_MODULE "audiounit"
#define PLATFORM_CONFIG "sip_cafile\t/etc/ssl/cert.pem\n"
#endif

#ifdef SIPPIER_AEC
/* aec.c wraps the audio module and cancels echo on what it plays and
 * records; key tones and ringing go to the module directly */
#define CALL_AUDIO "aec," AUDIO_MODULE
#else
#define CALL_AUDIO AUDIO_MODULE ","
#endif

static const char config_template[] =
	"sip_verify_server\tyes\n"
	PLATFORM_CONFIG
	"call_local_timeout\t120\n"
	"call_max_calls\t4\n"
	"call_hold_other_calls\tyes\n"
	/* without it baresip leaves incoming INVITEs to an app module */
	"call_accept\tyes\n"
	"audio_player\t" CALL_AUDIO "\n"
	"audio_source\t" CALL_AUDIO "\n"
	"audio_alert\t" AUDIO_MODULE ",\n"
	"audio_level\tno\n"
	"audio_buffer\t20-160\n"
	"rtp_ports\t10000-20000\n"
	"ringback_disabled\tyes\n"
	"module\tg711.so\n"
	"module\tlibg722.so\n"
	"module\topus.so\n"
	"module\tsrtp.so\n"
	"module\t" AUDIO_MODULE ".so\n"
	"module\tstun.so\n"
	"module\tturn.so\n"
	"module\tice.so\n";

static struct {
	pthread_t thread;
	pthread_mutex_t lock;
	pthread_cond_t cond;
	bool init_done;
	int init_err;
	bool running;
	sc_event_cb cb;
	char config_dir[1024];
	FILE *logf;
	pthread_mutex_t log_lock;
	struct ua *uas[MAX_ACCOUNTS];
	struct log logh;
	struct tmr dtmf_tmr;
	struct tmr stop_tmr;
	struct tmr authfail_tmr;
	struct tmr sleep_tmr;
	struct tmr wake_tmr;
	struct tmr nat_tmr;
	struct tmr net_tmr;
	void *sleep_ack;
	unsigned sleep_polls;
	unsigned wake_tries;
	/* the local addresses the SIP transports are bound to
	 * (address_signature) */
	uint32_t net_sig;
	struct play *key_tone;
	struct play *ring;
	struct mqueue *mq;
	bool authfail[MAX_ACCOUNTS];
	/* registration the app asked for; what wake restores */
	bool enabled[MAX_ACCOUNTS];
	/* last REGISTER 200 OK (boottime ms) and the expiry it granted [s] */
	uint64_t reg_ok_ms[MAX_ACCOUNTS];
	uint32_t reg_expires[MAX_ACCOUNTS];
	/* refresh sent by sc_keepalive, waiting for its answer (boottime ms) */
	uint64_t refresh_ms[MAX_ACCOUNTS];
	char dtmf_call_id[128];
	/* chosen device ids, "" for the system default */
	char dev_in[128];
	char dev_out[128];
	char dev_ring[128];
} g = {
	.lock = PTHREAD_MUTEX_INITIALIZER,
	.cond = PTHREAD_COND_INITIALIZER,
	.log_lock = PTHREAD_MUTEX_INITIALIZER,
};


static void log_to_file(const char *prefix, const char *text, size_t len)
{
	char ts[32];
	time_t now = time(NULL);
	struct tm tm;

	pthread_mutex_lock(&g.log_lock);
	if (g.logf) {
#ifdef _WIN32
		localtime_s(&tm, &now);
#else
		localtime_r(&now, &tm);
#endif
		strftime(ts, sizeof(ts), "%H:%M:%S", &tm);
		fprintf(g.logf, "%s %s%.*s", ts, prefix, (int)len, text);
		if (len == 0 || text[len - 1] != '\n')
			fputc('\n', g.logf);
		fflush(g.logf);
	}
	pthread_mutex_unlock(&g.log_lock);
}


/* Hands a copy of the JSON string to the Dart side, which frees it. */
static void emit_odict(const struct odict *od)
{
	char *json = NULL;
	char *copy;

	if (!g.cb)
		return;

	if (re_sdprintf(&json, "%H", json_encode_odict, od))
		return;

	copy = strdup(json);
	mem_deref(json);
	if (copy)
		g.cb(copy);
}


static int acc_index(const struct ua *ua)
{
	if (!ua)
		return -1;

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		if (g.uas[i] == ua)
			return i;
	}

	return -1;
}


static struct ua *acc_get(int acc)
{
	if (acc < 0 || acc >= MAX_ACCOUNTS)
		return NULL;

	return g.uas[acc];
}


static void log_handler(uint32_t level, const char *msg)
{
	struct odict *od = NULL;

	log_to_file("", msg, strlen(msg));
#ifdef __ANDROID__
	__android_log_write(level >= LEVEL_WARN ? ANDROID_LOG_WARN :
			    ANDROID_LOG_INFO, "sippier", msg);
#endif

	if (odict_alloc(&od, 4))
		return;

	odict_entry_add(od, "kind", ODICT_STRING, "log");
	odict_entry_add(od, "level", ODICT_INT, (int64_t)level);
	odict_entry_add(od, "text", ODICT_STRING, msg);
	emit_odict(od);
	mem_deref(od);
}


static void authfail_handler(void *arg)
{
	(void)arg;

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		if (g.authfail[i] && g.uas[i]) {
			ua_stop_register(g.uas[i]);
			g.enabled[i] = false;  /* also after wake */
		}
		g.authfail[i] = false;
	}
}


/* One-strike rule: some providers (e.g. Vodafone DE) block the source IP
 * after 3 failed registrations, and libre would keep retrying. */
static bool is_auth_failure(const char *param)
{
	return param && (0 == strncmp(param, "401", 3) ||
			 0 == strncmp(param, "403", 3) ||
			 0 == strncmp(param, "407", 3));
}


/*
 * Plays a key's DTMF tone on the call speaker, as a second output next to
 * the call audio. RFC 4733 events are out of band, so without this neither
 * side hears anything. Straight to the audio module: through aec it would
 * feed a second stream into the echo reference.
 */
static void play_key_tone(char key)
{
	const uint32_t srate = 16000;
	struct mbuf *mb;
	int16_t *sampv;
	size_t sampc;

	g.key_tone = mem_deref(g.key_tone);

	mb = mbuf_alloc(srate * 2);
	if (!mb)
		return;

	/* one second of tone at 5 % per frequency; keep 120 ms at 15 % */
	if (autone_dtmf(mb, srate, key) == 0) {
		sampc = srate * DTMF_TONE_MS / 1000;
		sampv = (int16_t *)(void *)mb->buf;
		for (size_t i = 0; i < sampc; i++)
			sampv[i] = (int16_t)(sampv[i] * 3);
		mb->pos = 0;
		mb->end = sampc * 2;
		(void)play_tone(&g.key_tone, baresip_player(), mb, srate, 1,
				1, AUDIO_MODULE, g.dev_out);
	}

	mem_deref(mb);
}


/* Milliseconds that keep counting while the device sleeps, unlike libre's
 * timers (CLOCK_MONOTONIC_RAW) */
static uint64_t boottime_ms(void)
{
	struct timespec ts;

#ifdef CLOCK_BOOTTIME
	clock_gettime(CLOCK_BOOTTIME, &ts);
#else
	clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
	return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}


/* When the account registered, and for how long the provider granted it
 * (fonial gives 240 s for the 600 s we ask, Vodafone 900 s) */
static void note_registration(int acc)
{
	struct odict *od = NULL, *reg;
	uint64_t expires = 0;

	g.reg_ok_ms[acc] = boottime_ms();
	g.reg_expires[acc] = account_regint(ua_account(g.uas[acc]));

	if (odict_alloc(&od, 8) || ua_state_json_api(od, g.uas[acc]))
		goto out;
	reg = odict_get_object(od, "registration");
	if (reg && odict_get_number(reg, &expires, "expires") && expires)
		g.reg_expires[acc] = (uint32_t)expires;
 out:
	mem_deref(od);
}


static void nat_keepalive(void *arg)
{
	static int last;
	int n = 0;
	(void)arg;

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		if (g.enabled[i] && g.uas[i])
			n += ua_keepalive(g.uas[i]);
	}

	if (n != last)
		info("sippier: NAT keep-alive every %d s to %d registrar%s\n",
		     NAT_KEEPALIVE_MS / 1000, n, n == 1 ? "" : "s");
	last = n;

	tmr_start(&g.nat_tmr, NAT_KEEPALIVE_MS, nat_keepalive, NULL);
}


static void event_handler(enum bevent_ev ev, struct bevent *event, void *arg)
{
	struct odict *od = NULL;
	int acc = acc_index(bevent_get_ua(event));
	(void)arg;

	if (ev == BEVENT_VU_TX || ev == BEVENT_VU_RX)
		return;

	if (odict_alloc(&od, 8))
		return;

	if (bevent_odict_encode(od, event))
		goto out;

	odict_entry_add(od, "kind", ODICT_STRING, "event");
	odict_entry_add(od, "account", ODICT_INT, (int64_t)acc);

	if (ev == BEVENT_REGISTER_OK && acc >= 0)
		note_registration(acc);

	if ((ev == BEVENT_REGISTER_OK || ev == BEVENT_REGISTER_FAIL) &&
	    acc >= 0)
		g.refresh_ms[acc] = 0;

	if (ev == BEVENT_REGISTER_FAIL && acc >= 0 &&
	    is_auth_failure(bevent_get_text(event))) {
		/* stop outside the sipreg response handler */
		g.authfail[acc] = true;
		tmr_start(&g.authfail_tmr, 0, authfail_handler, NULL);
		odict_entry_add(od, "registration_stopped", ODICT_BOOL, true);
		warning("sippier: stopped registering %s after an auth "
			"failure (no automatic retry)\n",
			account_aor(ua_account(bevent_get_ua(event))));
	}

	emit_odict(od);

	/* the other side pressed a key */
	if (ev == BEVENT_CALL_DTMF_START && bevent_get_text(event))
		play_key_tone(bevent_get_text(event)[0]);

	if (ev == BEVENT_SHUTDOWN) {
		int i = acc_index(bevent_get_ua(event));
		if (i >= 0)
			g.uas[i] = NULL;
	}

 out:
	mem_deref(od);
}


static void sip_trace_handler(bool tx, enum sip_transp tp,
			      const struct sa *src, const struct sa *dst,
			      const uint8_t *pkt, size_t len, void *arg)
{
	char head[160];
	size_t i;
	(void)arg;

	/* NAT keep-alives (empty lines) every 25 s would drown the trace */
	for (i = 0; i < len && (pkt[i] == '\r' || pkt[i] == '\n'); i++)
		;
	if (i == len)
		return;

	re_snprintf(head, sizeof(head), "SIP %s %s %J -> %J\n",
		    tx ? "send" : "recv", sip_transp_name(tp), src, dst);
	log_to_file(head, (const char *)pkt, len);

#ifdef __ANDROID__
	/* release builds can't hand out the log file: logcat, one entry per
	 * line (entries are capped at about 4 KB) */
	__android_log_write(ANDROID_LOG_INFO, "sippier-sip", head);
	for (size_t i = 0; i < len;) {
		char line[1024];
		size_t n = 0;

		while (i < len && pkt[i] != '\n' && n < sizeof(line) - 1) {
			if (pkt[i] != '\r')
				line[n++] = (char)pkt[i];
			++i;
		}
		if (i < len && pkt[i] == '\n')
			++i;
		line[n] = '\0';
		__android_log_write(ANDROID_LOG_INFO, "sippier-sip", line);
	}
#endif
}


#ifdef __ANDROID__
/*
 * Android's CA directories name certificates by OpenSSL's old subject hash,
 * which OpenSSL 3 doesn't look up, so TLS found no issuer for any server.
 * Joins the certificates into one PEM file instead. The conscrypt APEX
 * (Android 14+) is updated with the system; older versions only have the
 * /system directory.
 */
static int write_ca_bundle(const char *path)
{
	static const char *dirs[] = {
		"/apex/com.android.conscrypt/cacerts",
		"/system/etc/security/cacerts",
	};
	char tmp[1100], file[512], buf[4096];
	int n = 0;

	snprintf(tmp, sizeof(tmp), "%s.tmp", path);

	for (size_t i = 0; i < RE_ARRAY_SIZE(dirs) && !n; i++) {
		DIR *dir = opendir(dirs[i]);
		struct dirent *de;
		FILE *out;

		if (!dir)
			continue;

		out = fopen(tmp, "w");
		if (!out) {
			closedir(dir);
			return errno;
		}

		while ((de = readdir(dir))) {
			FILE *in;
			size_t len;

			if (de->d_name[0] == '.')
				continue;

			snprintf(file, sizeof(file), "%s/%s", dirs[i],
				 de->d_name);
			in = fopen(file, "r");
			if (!in)
				continue;

			while ((len = fread(buf, 1, sizeof(buf), in)) > 0)
				fwrite(buf, 1, len, out);
			fputc('\n', out);
			fclose(in);
			++n;
		}

		closedir(dir);
		if (fclose(out)) {
			remove(tmp);
			return EIO;
		}
	}

	if (!n) {
		remove(tmp);
		return ENOENT;
	}

	return rename(tmp, path) ? errno : 0;
}
#elif defined(_WIN32)
/*
 * Windows keeps its trusted roots in the certificate store, which OpenSSL
 * can't read. Exports them into one PEM file instead.
 *
 * Caveat: Windows fetches some roots only when it first needs one (automatic
 * root update), so a root no Windows API has asked for yet isn't in the
 * store. Browsers bring their own roots and don't trigger that.
 */
static int write_ca_bundle(const char *path)
{
	PCCERT_CONTEXT cert = NULL;
	HCERTSTORE store;
	char tmp[1100];
	FILE *out;
	int n = 0;

	store = CertOpenSystemStoreW(0, L"ROOT");
	if (!store)
		return ENOENT;

	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	out = fopen(tmp, "wb");
	if (!out) {
		int err = errno;

		CertCloseStore(store, 0);
		return err;
	}

	while ((cert = CertEnumCertificatesInStore(store, cert))) {
		DWORD len = 0;
		char *pem;

		if (!CryptBinaryToStringA(cert->pbCertEncoded,
					  cert->cbCertEncoded,
					  CRYPT_STRING_BASE64HEADER, NULL, &len))
			continue;

		pem = malloc(len);
		if (!pem)
			continue;

		if (CryptBinaryToStringA(cert->pbCertEncoded,
					 cert->cbCertEncoded,
					 CRYPT_STRING_BASE64HEADER, pem, &len)) {
			fwrite(pem, 1, len, out);
			++n;
		}
		free(pem);
	}

	CertCloseStore(store, 0);

	if (fclose(out) || !n) {
		remove(tmp);
		return n ? EIO : ENOENT;
	}

	/* rename() doesn't replace an existing file on Windows */
	return MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING) ? 0 : EIO;
}
#endif


/* Module and device for a config entry; call audio goes through aec */
static void set_device(char *mod, size_t modsz, char *dev, size_t devsz,
		       bool call, const char *id)
{
#ifdef SIPPIER_AEC
	if (call) {
		str_ncpy(mod, "aec", modsz);
		if (str_isset(id))
			re_snprintf(dev, devsz, AUDIO_MODULE ":%s", id);
		else
			str_ncpy(dev, AUDIO_MODULE, devsz);
		return;
	}
#else
	(void)call;
#endif
	str_ncpy(mod, AUDIO_MODULE, modsz);
	str_ncpy(dev, id, devsz);
}


/* Reopens the source and/or player of every call with audio running */
static void restart_call_audio(bool input, bool output)
{
	const struct config_audio *cfg = &conf_config()->audio;

	for (struct le *le = list_head(uag_list()); le; le = le->next) {
		struct le *cle = list_head(ua_calls(le->data));

		for (; cle; cle = cle->next) {
			struct audio *a = call_audio(cle->data);

			if (!audio_started(a))
				continue;
			if (input)
				(void)audio_set_source(a, cfg->src_mod,
						       cfg->src_dev);
			if (output)
				(void)audio_set_player(a, cfg->play_mod,
						       cfg->play_dev);
		}
	}
}


/* Sleep waits until the unregisters are confirmed, or SLEEP_WAIT_MS */
static void sleep_poll(void *arg)
{
	bool pending = false;
	(void)arg;

	for (int i = 0; i < MAX_ACCOUNTS; i++)
		pending |= g.enabled[i] && ua_isregistered(g.uas[i]);

	if (pending && ++g.sleep_polls < SLEEP_WAIT_MS / 100) {
		tmr_start(&g.sleep_tmr, 100, sleep_poll, NULL);
		return;
	}

	info("sippier: %s, sleeping\n",
	     pending ? "unregister not confirmed" : "unregistered");
	power_sleep_ok(g.sleep_ack);
	g.sleep_ack = NULL;
}


/*
 * A sleeping computer can't take calls. Without an unregister the
 * provider keeps sending calls to the dead registration until it expires,
 * and its "when unreachable" forwarding never fires. Calls end cleanly
 * instead of timing out on the other side.
 */
static void prepare_sleep(void *ack)
{
	tmr_cancel(&g.wake_tmr);

	for (struct le *le = list_head(uag_list()); le; le = le->next) {
		struct ua *ua = le->data;
		struct le *cle = list_head(ua_calls(ua));

		while (cle) {
			struct call *call = cle->data;

			cle = cle->next;
			ua_hangup(ua, call, 0, NULL);
		}
	}

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		if (g.enabled[i] && g.uas[i])
			ua_unregister(g.uas[i]);
	}

	info("sippier: system goes to sleep, unregistering\n");
	if (g.sleep_ack)
		power_sleep_ok(g.sleep_ack);
	g.sleep_ack = ack;
	g.sleep_polls = 0;
	tmr_start(&g.sleep_tmr, 100, sleep_poll, NULL);
}


/*
 * The network is often not back right at wake ("No route to host" for a
 * few seconds), and libre waits 30 s or more after a failure, so start
 * failed registrations over for a while. One still waiting for an answer
 * is left alone: a second REGISTER gets Vodafone's "491 ... Parallel
 * registrations".
 */
static void wake_register(void *arg)
{
	bool pending = false;
	(void)arg;

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		struct ua *ua = g.uas[i];

		if (!g.enabled[i] || !ua || ua_isregistered(ua))
			continue;

		if (!g.wake_tries || ua_regfailed(ua))
			(void)ua_register(ua);
		pending = true;
	}

	if (pending && ++g.wake_tries < WAKE_TRIES)
		tmr_start(&g.wake_tmr, WAKE_RETRY_MS, wake_register, NULL);
}


static void wake(void)
{
	/* sleep came before the unregisters were confirmed */
	tmr_cancel(&g.sleep_tmr);
	if (g.sleep_ack) {
		power_sleep_ok(g.sleep_ack);
		g.sleep_ack = NULL;
	}

	info("sippier: system woke up, registering again\n");
	g.wake_tries = 0;
	tmr_start(&g.wake_tmr, 0, wake_register, NULL);
}


static bool add_laddr(const char *ifname, const struct sa *sa, void *arg)
{
	struct network *net = arg;

	if (net_ifaddr_filter(net, ifname, sa))
		(void)net_add_address_ifname(net, sa, ifname);

	return false;
}


struct addr_sum {
	struct network *net;
	uint32_t sum;
};


static bool sum_laddr(const char *ifname, const struct sa *sa, void *arg)
{
	struct addr_sum *s = arg;
	char buf[96];
	uint32_t h = 2166136261u;  /* FNV-1a */
	int n;

	if (!net_ifaddr_filter(s->net, ifname, sa))
		return false;

	n = re_snprintf(buf, sizeof(buf), "%s %j", ifname, sa);
	for (int i = 0; i < n; i++)
		h = (h ^ (uint8_t)buf[i]) * 16777619u;
	s->sum += h;

	return false;
}


/* The system's local addresses that add_laddr would take, in any order */
static uint32_t address_signature(struct network *net)
{
	struct addr_sum s = { net, 0 };

	net_if_apply(sum_laddr, &s);

	return s.sum;
}


/*
 * Local addresses come and go (Wi-Fi and mobile data, IPv6 privacy
 * addresses), and the SIP sockets stay bound to the old ones: sends then
 * fail with "Cannot assign requested address". Collects the addresses
 * again, rebinds the transports, moves running calls (re-INVITE) and
 * registers the enabled accounts again. baresip's own re-register would
 * also take disabled accounts and ones stopped after an auth failure.
 */
static int reset_network(void)
{
	struct network *net = baresip_network();
	int err;

	net_flush_addresses(net);
	net_if_apply(add_laddr, net);
	g.net_sig = address_signature(net);
	err = uag_reset_transp(false, true);

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		if (g.enabled[i] && g.uas[i])
			(void)ua_register(g.uas[i]);
	}

	return err;
}


/*
 * The system's network changed (netwatch.c), a moment ago. The DNS servers
 * are the system's, so read them again. New addresses need new transports
 * and registrations; with the same ones (the watcher's first report, a
 * change elsewhere) only failed registrations start over, as a second
 * REGISTER while one waits gets Vodafone's 491. Registrations that fail
 * while the network settles start over for a while, as after wake.
 */
static void network_settled(void *arg)
{
	struct network *net = baresip_network();
	bool reset = address_signature(net) != g.net_sig;
	(void)arg;

	net_dns_refresh(net);
	if (reset) {
		(void)reset_network();
		info("sippier: network changed, SIP transports reset\n");
	}

	g.wake_tries = 1;
	tmr_start(&g.wake_tmr, reset ? WAKE_RETRY_MS : 0, wake_register, NULL);
}


/* A device that follows the system default moves to the new default */
static void mqueue_handler(int id, void *data, void *arg)
{
	(void)arg;

	if (id == MQ_DEFAULT_IN && !g.dev_in[0])
		restart_call_audio(true, false);
	else if (id == MQ_DEFAULT_OUT && !g.dev_out[0])
		restart_call_audio(false, true);
	else if (id == MQ_SLEEP)
		prepare_sleep(data);
	else if (id == MQ_WAKE)
		wake();
	else if (id == MQ_NETWORK)
		tmr_start(&g.net_tmr, NETWORK_SETTLE_MS, network_settled, NULL);
}


/* On a system thread (netwatch.c) */
static void network_changed(void)
{
	if (g.mq)
		(void)mqueue_push(g.mq, MQ_NETWORK, NULL);
}


/* On a system thread (IOKit, Windows power callback); the system waits for
 * power_sleep_ok() */
static void power_changed(bool sleep, void *ack)
{
	if (!g.mq || mqueue_push(g.mq, sleep ? MQ_SLEEP : MQ_WAKE, ack)) {
		if (sleep)
			power_sleep_ok(ack);
	}
}


/* On a CoreAudio or MMDevice thread, which must not wait for the re thread */
static void default_changed(bool input)
{
	if (g.mq)
		(void)mqueue_push(g.mq, input ? MQ_DEFAULT_IN : MQ_DEFAULT_OUT,
				  NULL);
}


static void ua_exit_handler(void *arg)
{
	(void)arg;
	re_cancel();
}


static void signal_init_done(int err)
{
	pthread_mutex_lock(&g.lock);
	g.init_err = err;
	g.init_done = true;
	pthread_cond_signal(&g.cond);
	pthread_mutex_unlock(&g.lock);
}


static void *re_thread_main(void *arg)
{
	int err;
	(void)arg;

	err = libre_init();
	if (err) {
		signal_init_done(err);
		return NULL;
	}

	re_thread_async_init(4);

	g.logh.h = log_handler;
	log_register_handler(&g.logh);
	log_enable_stdout(false);
	log_enable_timestamps(false);
	log_enable_color(false);
	log_enable_info(true);

	err = conf_path_set(g.config_dir);
	if (err)
		goto out;

	err = conf_configure_buf((const uint8_t *)config_template,
				 sizeof(config_template) - 1);
	if (err)
		goto out;

#if defined(__ANDROID__) || defined(_WIN32)
	/* written on every start, so it follows system CA updates */
	{
		struct config_sip *sip = &conf_config()->sip;

		snprintf(sip->cafile, sizeof(sip->cafile), "%s/cacerts.pem",
			 g.config_dir);
		err = write_ca_bundle(sip->cafile);
		if (err) {
			warning("sippier: no CA bundle, TLS can't verify "
				"servers: %m\n", err);
			sip->cafile[0] = '\0';
			err = 0;
		}
	}
#endif

	err = baresip_init(conf_config());
	if (err)
		goto out;

	err = ua_init("Sippier/0.1 (baresip " BARESIP_VERSION ")",
		      true, true, true);
	if (err)
		goto out;

	uag_set_exit_handler(ua_exit_handler, NULL);

	err = bevent_register(event_handler, NULL);
	if (err)
		goto out;

	err = conf_modules();
	if (err)
		goto out;

#ifdef SIPPIER_AEC
	err = aec_register();
	if (err)
		goto out;
#endif

	err = mqueue_alloc(&g.mq, mqueue_handler, NULL);
	if (err)
		goto out;

	if (devices_watch(default_changed))
		warning("sippier: can't watch the default audio devices\n");
	if (power_watch(power_changed))
		warning("sippier: can't watch system sleep\n");
	/* the addresses baresip_init bound to */
	g.net_sig = address_signature(baresip_network());
	if (netwatch_start(network_changed))
		warning("sippier: can't watch the network\n");

	g.running = true;
	tmr_start(&g.nat_tmr, NAT_KEEPALIVE_MS, nat_keepalive, NULL);
	signal_init_done(0);

	re_main(NULL);

	g.running = false;
	g.key_tone = mem_deref(g.key_tone);
	g.ring = mem_deref(g.ring);
	tmr_cancel(&g.dtmf_tmr);
	tmr_cancel(&g.stop_tmr);
	tmr_cancel(&g.authfail_tmr);
	tmr_cancel(&g.sleep_tmr);
	tmr_cancel(&g.wake_tmr);
	tmr_cancel(&g.nat_tmr);
	tmr_cancel(&g.net_tmr);
	if (g.sleep_ack) {
		power_sleep_ok(g.sleep_ack);
		g.sleep_ack = NULL;
	}
	memset(g.uas, 0, sizeof(g.uas));
	memset(g.enabled, 0, sizeof(g.enabled));

 out:
	if (err)
		signal_init_done(err);

	devices_unwatch();
	netwatch_stop();
	power_unwatch();
	{
		struct mqueue *mq = g.mq;

		g.mq = NULL;
		mem_deref(mq);
	}

	bevent_unregister(event_handler);
	ua_close();
#ifdef SIPPIER_AEC
	aec_unregister();
#endif
	module_app_unload();
	conf_close();
	baresip_close();
	mod_close();
	log_unregister_handler(&g.logh);
	re_thread_async_close();
	libre_close();

	return NULL;
}


int sc_init(const char *config_dir, sc_event_cb cb)
{
	char path[1100];
	int err;

	if (!config_dir)
		return EINVAL;

	/* Already running, e.g. after a Dart hot restart: swap the callback
	 * so events stop going to the dead isolate. */
	if (g.running) {
		g.cb = cb;
		return EALREADY;
	}

	snprintf(g.config_dir, sizeof(g.config_dir), "%s", config_dir);
	snprintf(path, sizeof(path), "%s/sippier.log", config_dir);
	g.logf = fopen(path, "a");
	g.cb = cb;
	g.init_done = false;
	g.init_err = 0;

	err = pthread_create(&g.thread, NULL, re_thread_main, NULL);
	if (err)
		return err;

	pthread_mutex_lock(&g.lock);
	while (!g.init_done)
		pthread_cond_wait(&g.cond, &g.lock);
	err = g.init_err;
	pthread_mutex_unlock(&g.lock);

	if (err)
		pthread_join(g.thread, NULL);

	return err;
}


static void stop_handler(void *arg)
{
	(void)arg;
	ua_stop_all(false);
}


void sc_shutdown(void)
{
	if (!g.running)
		return;

	/* ua_stop_all() can end in re_cancel(), after which re_thread_leave()
	 * would no longer release the lock, so stop from inside the loop. */
	re_thread_enter();
	tmr_start(&g.stop_tmr, 0, stop_handler, NULL);
	re_thread_leave();

	pthread_join(g.thread, NULL);

	pthread_mutex_lock(&g.log_lock);
	if (g.logf) {
		fclose(g.logf);
		g.logf = NULL;
	}
	pthread_mutex_unlock(&g.log_lock);
	g.cb = NULL;
}


void sc_string_free(char *s)
{
	free(s);
}


int sc_account_add(const char *aor, const char *password)
{
	struct ua *ua = NULL;
	int id = -1;
	int err;

	if (!aor || !g.running)
		return -EINVAL;

	re_thread_enter();

	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		if (!g.uas[i]) {
			id = i;
			break;
		}
	}
	if (id < 0) {
		err = ENOSPC;
		goto out;
	}

	err = ua_alloc(&ua, aor);
	if (err)
		goto out;

	if (password && *password) {
		err = account_set_auth_pass(ua_account(ua), password);
		if (err) {
			ua_destroy(ua);
			goto out;
		}
	}

	g.uas[id] = ua;
	g.refresh_ms[id] = 0;

 out:
	re_thread_leave();
	return err ? -err : id;
}


int sc_account_remove(int acc)
{
	struct ua *ua;

	if (!g.running)
		return EINVAL;

	re_thread_enter();
	ua = acc_get(acc);
	if (ua) {
		g.uas[acc] = NULL;
		g.enabled[acc] = false;
		ua_destroy(ua);
	}
	re_thread_leave();

	return ua ? 0 : ENOENT;
}


int sc_account_update(int acc, const char *aor, const char *password)
{
	struct ua *old;
	struct ua *ua = NULL;
	char *pass = NULL;
	int err = 0;

	if (!aor || !g.running)
		return EINVAL;

	re_thread_enter();

	old = acc_get(acc);
	if (!old) {
		err = ENOENT;
		goto out;
	}

	if (password && *password)
		err = str_dup(&pass, password);
	else if (account_auth_pass(ua_account(old)))
		err = str_dup(&pass, account_auth_pass(ua_account(old)));
	if (err)
		goto out;

	/* Destroy first, so its unregister goes out before the new
	 * registration for what may be the same address of record. */
	g.uas[acc] = NULL;
	g.enabled[acc] = false;  /* until sc_account_register() */
	ua_destroy(old);

	err = ua_alloc(&ua, aor);
	if (err)
		goto out;

	if (str_isset(pass)) {
		err = account_set_auth_pass(ua_account(ua), pass);
		if (err) {
			ua_destroy(ua);
			goto out;
		}
	}

	g.uas[acc] = ua;
	g.refresh_ms[acc] = 0;

 out:
	re_thread_leave();
	mem_deref(pass);
	return err;
}


int sc_account_register(int acc, int enable)
{
	struct ua *ua;
	int err = 0;

	if (!g.running)
		return EINVAL;

	re_thread_enter();
	ua = acc_get(acc);
	if (!ua) {
		err = ENOENT;
	}
	else {
		g.enabled[acc] = enable != 0;
		if (enable)
			err = ua_register(ua);
		else
			ua_unregister(ua);
	}
	re_thread_leave();

	return err;
}


int sc_call(int acc, const char *uri, char *id_out, int id_out_size)
{
	struct ua *ua;
	struct call *call = NULL;
	char *uric = NULL;
	struct pl pl;
	int err;

	if (!uri || !g.running)
		return EINVAL;

	re_thread_enter();

	ua = acc_get(acc);
	if (!ua) {
		err = ENOENT;
		goto out;
	}

	/* Completes a plain number or user to sip:user@domain */
	pl_set_str(&pl, uri);
	err = account_uri_complete_strdup(ua_account(ua), &uric, &pl);
	if (err)
		goto out;

	err = ua_connect(ua, &call, NULL, uric, VIDMODE_OFF);
	if (err)
		goto out;

	if (id_out && id_out_size > 0)
		snprintf(id_out, (size_t)id_out_size, "%s", call_id(call));

 out:
	re_thread_leave();
	mem_deref(uric);
	return err;
}


/* Runs the body on the call with the given id inside the re thread. */
#define WITH_CALL(call_id, ...)				\
	do {						\
		struct call *call;			\
		int err = 0;				\
		if (!(call_id) || !g.running)		\
			return EINVAL;			\
		re_thread_enter();			\
		call = uag_call_find(call_id);		\
		if (!call)				\
			err = ENOENT;			\
		else {					\
			__VA_ARGS__;			\
		}					\
		re_thread_leave();			\
		return err;				\
	} while (0)


int sc_answer(const char *call_id)
{
	WITH_CALL(call_id,
		  err = ua_answer(call_get_ua(call), call, VIDMODE_OFF));
}


int sc_hangup(const char *call_id)
{
	WITH_CALL(call_id,
		  ua_hangup(call_get_ua(call), call, 0, NULL));
}


int sc_hold(const char *call_id, int hold)
{
	WITH_CALL(call_id, err = call_hold(call, hold != 0));
}


int sc_mute(const char *call_id, int mute)
{
	WITH_CALL(call_id, audio_mute(call_audio(call), mute != 0));
}


static void dtmf_release_handler(void *arg)
{
	struct call *call = uag_call_find(g.dtmf_call_id);
	(void)arg;

	if (call)
		call_send_digit(call, KEYCODE_REL);
}


int sc_send_dtmf(const char *call_id, char key)
{
	WITH_CALL(call_id, {
		/* baresip logs "send DTMF digit" even when the other side
		 * didn't accept telephone-event and nothing goes out */
		const struct sdp_format *fmt = sdp_media_rformat(
			stream_sdpmedia(audio_strm(call_audio(call))),
			"telephone-event");
		if (fmt)
			info("sippier: DTMF '%c' as RTP event (PT %s)\n", key,
			     fmt->id);
		else
			info("sippier: DTMF '%c' as SIP INFO (no "
			     "telephone-event in the remote SDP)\n", key);

		err = call_send_digit(call, key);
		if (!err) {
			play_key_tone(key);
			snprintf(g.dtmf_call_id, sizeof(g.dtmf_call_id),
				 "%s", call_id);
			tmr_start(&g.dtmf_tmr, DTMF_TONE_MS,
				  dtmf_release_handler, NULL);
		}
	});
}


void sc_set_sip_trace(int enable)
{
	if (!g.running)
		return;

	re_thread_enter();
	sip_set_trace_handler(uag_sip(), enable ? sip_trace_handler : NULL);
	re_thread_leave();
}


int sc_set_dns_servers(const char *servers)
{
	struct sa srvv[MAX_DNS_SERVERS];
	size_t n = 0;
	struct pl rest, tok;
	int err;

	if (!servers || !g.running)
		return EINVAL;

	/* "1.2.3.4, 2001:db8::1, [2001:db8::2]:5353" */
	pl_set_str(&rest, servers);
	while (n < MAX_DNS_SERVERS &&
	       !re_regex(rest.p, rest.l, "[ ,]*[^ ,]+", NULL, &tok)) {
		if (sa_set(&srvv[n], &tok, 53) == 0 ||
		    sa_decode(&srvv[n], tok.p, tok.l) == 0)
			++n;
		else
			warning("sippier: ignoring DNS server '%r'\n", &tok);

		rest.l -= tok.p + tok.l - rest.p;
		rest.p = tok.p + tok.l;
	}

	re_thread_enter();
	err = net_use_nameserver(baresip_network(), srvv, n);
	re_thread_leave();

	return err;
}


void sc_play_key_tone(char key)
{
	if (!g.running)
		return;

	re_thread_enter();
	play_key_tone(key);
	re_thread_leave();
}


/* malloc'd copy for the Dart side, freed with sc_string_free() */
static char *odict_json(const struct odict *od)
{
	char *json = NULL, *copy;

	if (re_sdprintf(&json, "%H", json_encode_odict, od))
		return NULL;

	copy = strdup(json);
	mem_deref(json);

	return copy;
}


char *sc_audio_devices(void)
{
	struct odict *od = NULL;
	char *json = NULL;

	if (!g.running)
		return NULL;

	re_thread_enter();
	if (!odict_alloc(&od, 8) && !devices_encode(od, AUDIO_MODULE))
		json = odict_json(od);
	re_thread_leave();

	mem_deref(od);

	return json;
}


int sc_set_audio_devices(const char *input, const char *output,
			 const char *ringer)
{
	struct config_audio *cfg;
	bool in, out;

	if (!g.running)
		return EINVAL;

	input = input ? input : "";
	output = output ? output : "";
	ringer = ringer ? ringer : "";

	re_thread_enter();

	in = 0 != str_cmp(g.dev_in, input);
	out = 0 != str_cmp(g.dev_out, output);
	str_ncpy(g.dev_in, input, sizeof(g.dev_in));
	str_ncpy(g.dev_out, output, sizeof(g.dev_out));
	str_ncpy(g.dev_ring, ringer, sizeof(g.dev_ring));

	cfg = &conf_config()->audio;
	set_device(cfg->src_mod, sizeof(cfg->src_mod),
		   cfg->src_dev, sizeof(cfg->src_dev), true, g.dev_in);
	set_device(cfg->play_mod, sizeof(cfg->play_mod),
		   cfg->play_dev, sizeof(cfg->play_dev), true, g.dev_out);
	set_device(cfg->alert_mod, sizeof(cfg->alert_mod),
		   cfg->alert_dev, sizeof(cfg->alert_dev), false, g.dev_ring);

	restart_call_audio(in, out);

	re_thread_leave();

	return 0;
}


char *sc_ringtones(void)
{
	struct mbuf *mb = mbuf_alloc(256);
	char *json = NULL;

	if (!mb)
		return NULL;

	if (!ringtone_names(mb))
		json = malloc(mb->end + 1);
	if (json) {
		memcpy(json, mb->buf, mb->end);
		json[mb->end] = '\0';
	}

	mem_deref(mb);

	return json;
}


int sc_ring_start(const char *tone)
{
	const struct config_audio *cfg;
	struct mbuf *mb = NULL;
	uint32_t srate;
	uint8_t ch;
	int err;

	if (!g.running)
		return EINVAL;

	re_thread_enter();

	g.ring = mem_deref(g.ring);
	cfg = &conf_config()->audio;
	err = ringtone_alloc(&mb, &srate, &ch, tone);
	if (!err)
		err = play_tone(&g.ring, baresip_player(), mb, srate, ch, -1,
				cfg->alert_mod, cfg->alert_dev);
	mem_deref(mb);

	re_thread_leave();

	return err;
}


void sc_ring_stop(void)
{
	if (!g.running)
		return;

	re_thread_enter();
	g.ring = mem_deref(g.ring);
	re_thread_leave();
}


/*
 * Android battery saver: without a wake lock the CPU sleeps, and libre's
 * timers don't count that time, so registration refreshes would come far
 * too late. An alarm calls this instead: accounts past half of the expiry
 * their provider granted refresh their registration now, and UDP accounts
 * get a NAT keep-alive. Returns the milliseconds until the next call is
 * due.
 */
int sc_keepalive(void)
{
	uint64_t now, next = KEEPALIVE_MAX_MS;

	if (!g.running)
		return KEEPALIVE_MIN_MS;

	re_thread_enter();

	now = boottime_ms();
	for (int i = 0; i < MAX_ACCOUNTS; i++) {
		struct ua *ua = g.uas[i];
		uint64_t expires_ms, age, due;

		if (!g.enabled[i] || !ua)
			continue;

		if (ua_keepalive(ua) > 0)
			next = min(next, (uint64_t)NAT_KEEPALIVE_SAVER_MS);

		expires_ms = (uint64_t)(g.reg_expires[i] ?
			g.reg_expires[i] : account_regint(ua_account(ua))) * 1000;
		age = now - g.reg_ok_ms[i];

		/* waiting for an answer: a second REGISTER gets a 491 */
		if ((!ua_isregistered(ua) && !ua_regfailed(ua)) ||
		    (g.refresh_ms[i] && now - g.refresh_ms[i] < REFRESH_WAIT_MS)) {
			next = min(next, (uint64_t)KEEPALIVE_MIN_MS);
			continue;
		}

		if (!ua_isregistered(ua)) {
			/* failed: start over */
			info("sippier: keep-alive: registering %s again\n",
			     account_aor(ua_account(ua)));
			(void)ua_register(ua);
			due = KEEPALIVE_MIN_MS;
		}
		else if (!g.reg_ok_ms[i] || age >= expires_ms / 2) {
			/* same Call-ID: a new registration would unregister
			 * the old one in parallel, and providers answer that
			 * with 482 (fonial) or a stale nonce (Vodafone) */
			info("sippier: keep-alive: refreshing %s"
			     " (%llu s since the last, %u s granted)\n",
			     account_aor(ua_account(ua)),
			     (unsigned long long)(g.reg_ok_ms[i] ?
						  age / 1000 : 0),
			     g.reg_expires[i]);
			g.refresh_ms[i] = now;
			(void)ua_refresh_register(ua);
			due = KEEPALIVE_MIN_MS;
		}
		else {
			due = expires_ms / 2 - age;
		}
		next = min(next, due);
	}

	re_thread_leave();

	return (int)max(next, (uint64_t)KEEPALIVE_MIN_MS);
}


int sc_account_expires(int acc)
{
	int expires = 0;

	if (!g.running)
		return 0;

	re_thread_enter();
	if (acc_get(acc) && g.reg_ok_ms[acc])
		expires = (int)g.reg_expires[acc];
	re_thread_leave();

	return expires;
}


/* Android's network callback (PlatformChannel.kt); see reset_network() */
int sc_network_changed(void)
{
	int err;

	if (!g.running)
		return EINVAL;

	re_thread_enter();
	err = reset_network();
	info("sippier: network changed, SIP transports reset\n");
	re_thread_leave();

	return err;
}

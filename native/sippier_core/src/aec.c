/*
 * Echo cancellation at the audio device: an audio player and an audio source
 * named "aec" that wrap another module's (device "<module>[:<device>]") and
 * run WebRTC audio processing on exactly what is played and recorded.
 *
 * baresip's own webrtc_aec filter feeds the canceller decoded audio before
 * the jitter buffer, so the echo delay it sees keeps changing with the buffer
 * level and packet bursts, and some echo always got through.
 */
#include <string.h>
#include <re.h>
#include <rem.h>
#include <baresip.h>
#include "apm.h"
#include "aec.h"

#define STATS_INTERVAL 10000  /* ms */

/* One canceller, shared by the player and the source of a call */
static struct {
	bool registered;
	mtx_t lock;
	struct apm *apm;
	unsigned users;
	struct tmr stats_tmr;
	struct auplay *auplay;
	struct ausrc *ausrc;
} aec;

struct auplay_st {
	struct auplay_st *inner;
	struct apm *apm;
	auplay_write_h *wh;
	void *arg;
	uint32_t srate;
	uint8_t ch;
	size_t framec;           /* samples per 10 ms frame */
	size_t n;                /* samples collected so far */
	int16_t frame[APM_MAX_FRAME];
};

struct ausrc_st {
	struct ausrc_st *inner;
	struct apm *apm;
	ausrc_read_h *rh;
	ausrc_error_h *errh;
	void *arg;
	uint32_t srate;
	uint8_t ch;
	size_t framec;
	size_t n;
	int16_t in[APM_MAX_FRAME];
	int16_t out[APM_MAX_FRAME];  /* the previous frame, processed */
};


static void stats_handler(void *arg)
{
	struct apm_stats s;
	(void)arg;

	apm_get_stats(aec.apm, &s);
	info("aec: delay %d ms, ERL %.1f dB, ERLE %.1f dB,"
	     " echo likelihood %.2f\n",
	     s.delay_ms, s.erl, s.erle, s.echo_likelihood);

	tmr_start(&aec.stats_tmr, STATS_INTERVAL, stats_handler, NULL);
}


static struct apm *apm_ref(void)
{
	struct apm *apm;

	mtx_lock(&aec.lock);

	if (!aec.apm) {
		aec.apm = apm_new();
		if (aec.apm)
			tmr_start(&aec.stats_tmr, STATS_INTERVAL,
				  stats_handler, NULL);
		else
			warning("aec: can't create the canceller\n");
	}

	if (aec.apm)
		++aec.users;
	apm = aec.apm;

	mtx_unlock(&aec.lock);

	return apm;
}


static void apm_unref(void)
{
	mtx_lock(&aec.lock);

	if (aec.users && --aec.users == 0) {
		tmr_cancel(&aec.stats_tmr);
		apm_delete(aec.apm);
		aec.apm = NULL;
	}

	mtx_unlock(&aec.lock);
}


/* WebRTC takes 8, 16, 32 or 48 kHz S16 */
static bool usable(int fmt, uint32_t srate, uint8_t ch)
{
	return fmt == AUFMT_S16LE && ch >= 1 && ch <= 2 &&
		(srate == 8000 || srate == 16000 ||
		 srate == 32000 || srate == 48000);
}


/* "<module>[:<device>]" */
static int split_device(const char *device, char *mod, size_t modsz,
			const char **dev)
{
	const char *colon;

	if (!str_isset(device))
		return EINVAL;

	colon = strchr(device, ':');
	str_ncpy(mod, device, colon ?
		 min((size_t)(colon - device) + 1, modsz) : modsz);
	*dev = colon ? colon + 1 : "";

	return 0;
}


static void play_destructor(void *arg)
{
	struct auplay_st *st = arg;

	/* stops the device before the canceller goes */
	mem_deref(st->inner);

	if (st->apm)
		apm_unref();
}


static void play_write(struct auframe *af, void *arg)
{
	struct auplay_st *st = arg;
	const int16_t *sampv;
	size_t i = 0;

	st->wh(af, st->arg);

	if (!st->apm || af->fmt != AUFMT_S16LE)
		return;

	sampv = af->sampv;
	while (i < af->sampc) {
		size_t take = min(af->sampc - i, st->framec - st->n);

		memcpy(&st->frame[st->n], &sampv[i], take * sizeof(int16_t));
		st->n += take;
		i += take;

		if (st->n == st->framec) {
			(void)apm_render(st->apm, st->frame, st->srate, st->ch);
			st->n = 0;
		}
	}
}


static int play_alloc(struct auplay_st **stp, const struct auplay *ap,
		      struct auplay_prm *prm, const char *device,
		      auplay_write_h *wh, void *arg)
{
	struct auplay_st *st;
	const char *dev;
	char mod[64];
	int err;
	(void)ap;

	if (!stp || !prm || !wh)
		return EINVAL;

	err = split_device(device, mod, sizeof(mod), &dev);
	if (err)
		return err;

	st = mem_zalloc(sizeof(*st), play_destructor);
	if (!st)
		return ENOMEM;

	st->wh = wh;
	st->arg = arg;
	st->srate = prm->srate;
	st->ch = prm->ch;
	st->framec = prm->srate / 100 * prm->ch;

	if (usable(prm->fmt, prm->srate, prm->ch))
		st->apm = apm_ref();
	else
		warning("aec: no echo cancellation for %u Hz, %u ch, %s\n",
			prm->srate, prm->ch, aufmt_name(prm->fmt));

	err = auplay_alloc(&st->inner, baresip_auplayl(), mod, prm, dev,
			   play_write, st);
	if (err)
		mem_deref(st);
	else
		*stp = st;

	return err;
}


static void src_destructor(void *arg)
{
	struct ausrc_st *st = arg;

	mem_deref(st->inner);

	if (st->apm)
		apm_unref();
}


static void src_read(struct auframe *af, void *arg)
{
	struct ausrc_st *st = arg;

	if (st->apm && af->fmt == AUFMT_S16LE) {
		int16_t *sampv = af->sampv;
		size_t i = 0;

		/* one frame (10 ms) of latency: each sample is swapped for
		 * the processed one at the same place in the frame before */
		while (i < af->sampc) {
			size_t take = min(af->sampc - i, st->framec - st->n);

			memcpy(&st->in[st->n], &sampv[i],
			       take * sizeof(int16_t));
			memcpy(&sampv[i], &st->out[st->n],
			       take * sizeof(int16_t));
			st->n += take;
			i += take;

			if (st->n == st->framec) {
				(void)apm_capture(st->apm, st->in, st->srate,
						  st->ch);
				memcpy(st->out, st->in,
				       st->framec * sizeof(int16_t));
				st->n = 0;
			}
		}
	}

	st->rh(af, st->arg);
}


static void src_error(int err, const char *str, void *arg)
{
	struct ausrc_st *st = arg;

	if (st->errh)
		st->errh(err, str, st->arg);
}


static int src_alloc(struct ausrc_st **stp, const struct ausrc *as,
		     struct ausrc_prm *prm, const char *device,
		     ausrc_read_h *rh, ausrc_error_h *errh, void *arg)
{
	struct ausrc_st *st;
	const char *dev;
	char mod[64];
	int err;
	(void)as;

	if (!stp || !prm || !rh)
		return EINVAL;

	err = split_device(device, mod, sizeof(mod), &dev);
	if (err)
		return err;

	st = mem_zalloc(sizeof(*st), src_destructor);
	if (!st)
		return ENOMEM;

	st->rh = rh;
	st->errh = errh;
	st->arg = arg;
	st->srate = prm->srate;
	st->ch = prm->ch;
	st->framec = prm->srate / 100 * prm->ch;

	if (usable(prm->fmt, prm->srate, prm->ch))
		st->apm = apm_ref();
	else
		warning("aec: no echo cancellation for %u Hz, %u ch, %s\n",
			prm->srate, prm->ch, aufmt_name(prm->fmt));

	err = ausrc_alloc(&st->inner, baresip_ausrcl(), mod, prm, dev,
			  src_read, src_error, st);
	if (err)
		mem_deref(st);
	else
		*stp = st;

	return err;
}


int aec_register(void)
{
	int err;

	if (mtx_init(&aec.lock, mtx_plain) != thrd_success)
		return ENOMEM;

	tmr_init(&aec.stats_tmr);
	aec.registered = true;

	err  = auplay_register(&aec.auplay, baresip_auplayl(), "aec",
			       play_alloc);
	err |= ausrc_register(&aec.ausrc, baresip_ausrcl(), "aec", src_alloc);
	if (err)
		return err;

	info("aec: echo cancellation (WebRTC) at the audio device\n");

	return 0;
}


void aec_unregister(void)
{
	if (!aec.registered)
		return;

	aec.auplay = mem_deref(aec.auplay);
	aec.ausrc = mem_deref(aec.ausrc);
	tmr_cancel(&aec.stats_tmr);
	mtx_destroy(&aec.lock);
	aec.registered = false;
}

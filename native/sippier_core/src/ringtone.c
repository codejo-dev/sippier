/*
 * Ringtones: built-in ones, synthesized rather than shipped as files, and
 * sound files the user picked. Each is one cycle (sound, then pause) that
 * the player loops.
 *
 * The built-in ones are short original melodies in the style of friendly
 * app ringtones: round mallet and bubble sounds, a light rhythm, stereo
 * with a little echo.
 */
#include <math.h>
#include <string.h>
#include <re.h>
#include <rem.h>
#include <baresip.h>
#include "ringtone.h"

#ifdef __APPLE__
#include <AudioToolbox/AudioToolbox.h>
#endif

#define SRATE       48000
#define PEAK        0.5    /* of full scale */
#define NOTE_MAX    1.5    /* s a note rings at most */
#define FILE_PREFIX "file:"
#define FILE_PAUSE  1.0    /* s of silence after a picked sound */
#define FILE_MAX    60     /* s of a picked sound that is used */

struct note {
	double t;    /* start [s] */
	int midi;    /* 60 = middle C */
	double vel;  /* 0..1 */
	double pan;  /* -1 left .. 1 right */
};

typedef double (voice_h)(double x, double f);

struct tone {
	const char *name;
	voice_h *voice;
	const struct note *notes;
	size_t n;
	double cycle;  /* s, including the pause */
	double echo;   /* ping-pong echo feedback */
};


static double hz(int midi)
{
	return 440.0 * pow(2.0, (midi - 69) / 12.0);
}


/* A few ms of fade-in, so no note starts with a click */
static double attack(double x, double secs)
{
	return x < secs ? x / secs : 1;
}


/* Marimba-like: a strong fundamental, the 4th harmonic and a bright knock
 * that fade fast; low notes ring longer */
static double mallet(double x, double f)
{
	double tau = 0.35 * sqrt(440.0 / f);

	return attack(x, 0.002) *
		(exp(-x / tau) * sin(2 * M_PI * f * x) +
		 0.25 * exp(-x / 0.04) * sin(2 * M_PI * 4 * f * x) +
		 0.08 * exp(-x / 0.008) * sin(2 * M_PI * 10 * f * x));
}


/* The pitch slides up into the note, like a drop of water */
static double bubble(double x, double f)
{
	const double tau = 0.025;
	double phase = 2 * M_PI * f * (x - 0.35 * tau * (1 - exp(-x / tau)));

	return attack(x, 0.003) * exp(-x / 0.14) *
		(sin(phase) + 0.12 * sin(2 * phase));
}


/* FM bell: bright when struck, mellow as it rings */
static double glass(double x, double f)
{
	double index = 2.2 * exp(-x / 0.25);

	return attack(x, 0.002) * exp(-x / 0.7) *
		sin(2 * M_PI * f * x + index * sin(2 * M_PI * 3.5 * f * x));
}


/* Bubbles: a bouncy pentatonic phrase and its answer */
static const struct note bubbles[] = {
	{0.00, 79, 0.8, -0.3}, {0.11, 84, 0.8,  0.3}, {0.22, 88, 0.9, -0.2},
	{0.44, 86, 0.7,  0.2}, {0.55, 91, 1.0,  0.0}, {0.77, 88, 0.7, -0.3},
	{0.88, 84, 0.7,  0.3}, {1.10, 81, 0.8, -0.2}, {1.21, 84, 0.8,  0.2},
	{1.32, 86, 0.9, -0.1}, {1.54, 91, 1.0,  0.1},
};

/* Marimba: a warm, syncopated groove in the middle register */
static const struct note marimba[] = {
	{0.00, 72, 0.9, -0.2}, {0.15, 76, 0.7,  0.2}, {0.30, 79, 0.8, -0.1},
	{0.45, 84, 0.9,  0.1}, {0.75, 81, 0.7, -0.2}, {0.90, 79, 0.7,  0.2},
	{1.05, 76, 0.8, -0.1}, {1.35, 74, 0.7,  0.1}, {1.50, 79, 0.9,  0.0},
};

/* Glass: four calm bells in E major */
static const struct note glassy[] = {
	{0.00, 88, 0.9, -0.3}, {0.30, 83, 0.8,  0.3},
	{0.60, 85, 0.8, -0.1}, {0.90, 80, 0.9,  0.1},
};

/* Classic: the old double ring as a quick mallet trill (C6/E6) */
#define TRILL(t) \
	{t + 0.00, 84, 0.8, -0.2}, {t + 0.05, 88, 0.8,  0.2}, \
	{t + 0.10, 84, 0.8, -0.2}, {t + 0.15, 88, 0.8,  0.2}, \
	{t + 0.20, 84, 0.8, -0.2}, {t + 0.25, 88, 0.8,  0.2}, \
	{t + 0.30, 84, 0.8, -0.2}, {t + 0.35, 88, 0.8,  0.2}, \
	{t + 0.40, 84, 0.8, -0.2}, {t + 0.45, 88, 0.8,  0.2}, \
	{t + 0.50, 84, 0.8, -0.2}, {t + 0.55, 88, 0.8,  0.2}
static const struct note classic[] = { TRILL(0.0), TRILL(0.8) };

static const struct tone tones[] = {
	{"bubbles", bubble, bubbles, RE_ARRAY_SIZE(bubbles), 2.6, 0.30},
	{"marimba", mallet, marimba, RE_ARRAY_SIZE(marimba), 3.0, 0.25},
	{"glass",   glass,  glassy,  RE_ARRAY_SIZE(glassy),  3.0, 0.35},
	{"classic", mallet, classic, RE_ARRAY_SIZE(classic), 3.4, 0.15},
};


static int synth(struct mbuf **mbp, const struct tone *tn)
{
	size_t n = (size_t)(tn->cycle * SRATE), d = (size_t)(0.12 * SRATE);
	const double a = 1 - exp(-2 * M_PI * 7000.0 / SRATE);  /* low-pass */
	double *l, *r, yl = 0, yr = 0, peak = 0;
	struct mbuf *mb;
	int err = 0;

	l = mem_zalloc(n * sizeof(*l), NULL);
	r = mem_zalloc(n * sizeof(*r), NULL);
	mb = mbuf_alloc(n * 2 * sizeof(int16_t));
	if (!l || !r || !mb) {
		err = ENOMEM;
		goto out;
	}

	for (size_t i = 0; i < tn->n; i++) {
		const struct note *nt = &tn->notes[i];
		double f = hz(nt->midi), angle = (nt->pan + 1) * M_PI / 4;
		size_t start = (size_t)(nt->t * SRATE);
		size_t len = start < n ? min(n - start,
					     (size_t)(NOTE_MAX * SRATE)) : 0;

		for (size_t k = 0; k < len; k++) {
			double s = nt->vel * tn->voice((double)k / SRATE, f);

			l[start + k] += s * cos(angle);
			r[start + k] += s * sin(angle);
		}
	}

	for (size_t i = 0; i < n; i++) {
		if (i >= d) {
			l[i] += tn->echo * r[i - d];
			r[i] += tn->echo * l[i - d];
		}
		yl += a * (l[i] - yl);
		yr += a * (r[i] - yr);
		l[i] = yl;
		r[i] = yr;
		peak = fmax(peak, fmax(fabs(yl), fabs(yr)));
	}

	for (size_t i = 0; i < n; i++) {
		/* the last 30 ms fade out, so the loop doesn't click */
		double fade = fmin(1, (double)(n - i) / (0.03 * SRATE));
		double g = peak > 0 ? PEAK * fade / peak : 0;

		err |= mbuf_write_u16(mb, (uint16_t)(int16_t)(l[i] * g * 32767));
		err |= mbuf_write_u16(mb, (uint16_t)(int16_t)(r[i] * g * 32767));
	}
	mb->pos = 0;

 out:
	mem_deref(l);
	mem_deref(r);
	if (err)
		mem_deref(mb);
	else
		*mbp = mb;

	return err;
}


/* FILE_PAUSE of silence after the sound */
static int add_pause(struct mbuf *mb, uint32_t srate, uint8_t ch)
{
	return mbuf_fill(mb, 0, (size_t)(FILE_PAUSE * srate) * ch * 2);
}


#ifdef __APPLE__

/* Anything CoreAudio reads (WAV, AIFF, MP3, AAC/M4A, CAF), resampled to
 * SRATE, in the file's channels (at most 2) */
static int file_sound(struct mbuf **mbp, uint32_t *sratep, uint8_t *chp,
		      const char *path)
{
	AudioStreamBasicDescription fmt = {0}, ffmt = {0};
	UInt32 size = sizeof(ffmt);
	ExtAudioFileRef file = NULL;
	struct mbuf *mb = NULL;
	int16_t buf[4096];
	CFURLRef url;
	OSStatus ret;
	uint8_t ch;

	url = CFURLCreateFromFileSystemRepresentation(NULL,
			(const UInt8 *)path, (CFIndex)strlen(path), false);
	if (!url)
		return ENOMEM;

	ret = ExtAudioFileOpenURL(url, &file);
	CFRelease(url);
	if (ret)
		return ENOENT;

	ret = ExtAudioFileGetProperty(file,
				      kExtAudioFileProperty_FileDataFormat,
				      &size, &ffmt);
	if (ret)
		goto out;
	ch = ffmt.mChannelsPerFrame >= 2 ? 2 : 1;

	fmt.mSampleRate = SRATE;
	fmt.mFormatID = kAudioFormatLinearPCM;
	fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger |
		kAudioFormatFlagIsPacked;
	fmt.mBitsPerChannel = 16;
	fmt.mChannelsPerFrame = ch;
	fmt.mFramesPerPacket = 1;
	fmt.mBytesPerFrame = 2 * ch;
	fmt.mBytesPerPacket = 2 * ch;
	ret = ExtAudioFileSetProperty(file,
				      kExtAudioFileProperty_ClientDataFormat,
				      sizeof(fmt), &fmt);
	if (ret)
		goto out;

	mb = mbuf_alloc(SRATE * 2 * ch * 4);
	if (!mb) {
		ret = -1;
		goto out;
	}

	while (mb->end < (size_t)FILE_MAX * SRATE * 2 * ch) {
		AudioBufferList bl = {1, {{ch, sizeof(buf), buf}}};
		UInt32 frames = RE_ARRAY_SIZE(buf) / ch;

		ret = ExtAudioFileRead(file, &frames, &bl);
		if (ret || !frames)
			break;
		if (mbuf_write_mem(mb, (const uint8_t *)buf,
				   frames * 2 * ch)) {
			ret = -1;
			break;
		}
	}
	if (!ret && mb->end && add_pause(mb, SRATE, ch))
		ret = -1;

 out:
	ExtAudioFileDispose(file);
	if (ret || !mb || !mb->end) {
		mem_deref(mb);
		return EIO;
	}

	mb->pos = 0;
	*mbp = mb;
	*sratep = SRATE;
	*chp = ch;

	return 0;
}

#else

/* WAV (S16, mono or stereo) at its own sample rate */
static int file_sound(struct mbuf **mbp, uint32_t *sratep, uint8_t *chp,
		      const char *path)
{
	struct aufile_prm prm;
	struct aufile *af = NULL;
	struct mbuf *mb = NULL;
	uint8_t buf[4096];
	size_t max;
	int err;

	err = aufile_open(&af, &prm, path, AUFILE_READ);
	if (err)
		return err;

	if (prm.fmt != AUFMT_S16LE || !prm.srate || !prm.channels ||
	    prm.channels > 2) {
		err = ENOTSUP;
		goto out;
	}

	mb = mbuf_alloc(sizeof(buf));
	if (!mb) {
		err = ENOMEM;
		goto out;
	}

	max = (size_t)FILE_MAX * prm.srate * prm.channels * 2;
	while (!err && mb->end < max) {
		size_t sz = sizeof(buf);

		err = aufile_read(af, buf, &sz);
		if (err || !sz)
			break;
		err = mbuf_write_mem(mb, buf, sz);
	}
	if (!err && !mb->end)
		err = ENODATA;
	if (!err)
		err = add_pause(mb, prm.srate, prm.channels);

 out:
	mem_deref(af);
	if (err) {
		mem_deref(mb);
		return err;
	}

	mb->pos = 0;
	*mbp = mb;
	*sratep = prm.srate;
	*chp = prm.channels;

	return 0;
}

#endif


int ringtone_names(struct mbuf *mb)
{
	int err;

	err = mbuf_write_str(mb, "[");
	for (size_t i = 0; i < RE_ARRAY_SIZE(tones); i++)
		err |= mbuf_printf(mb, "%s\"%s\"", i ? "," : "",
				   tones[i].name);
	err |= mbuf_write_str(mb, "]");

	return err;
}


int ringtone_alloc(struct mbuf **mbp, uint32_t *sratep, uint8_t *chp,
		   const char *name)
{
	size_t k;

	if (!mbp || !sratep || !chp)
		return EINVAL;

	if (name && !strncmp(name, FILE_PREFIX, strlen(FILE_PREFIX))) {
		const char *path = name + strlen(FILE_PREFIX);
		int err = file_sound(mbp, sratep, chp, path);

		if (!err)
			return 0;

		warning("ringtone: can't read %s (%m), using %s\n", path,
			err, tones[0].name);
		name = tones[0].name;
	}

	for (k = 0; k < RE_ARRAY_SIZE(tones); k++) {
		if (!str_casecmp(name, tones[k].name))
			break;
	}
	if (k == RE_ARRAY_SIZE(tones))
		k = 0;

	*sratep = SRATE;
	*chp = 2;

	return synth(mbp, &tones[k]);
}

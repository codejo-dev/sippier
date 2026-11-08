/*
 * Ringtones (ringtone.c): built-in synthesized ones, and sound files the
 * user picked ("file:/path/to/sound.m4a"), as interleaved S16.
 */
#include <stdint.h>

struct mbuf;

/* Writes the built-in names as a JSON array, the default first */
int ringtone_names(struct mbuf *mb);

/* One cycle (sound, then pause) to loop, with its sample rate and channels.
 * Unknown names, and files that can't be read, give the default. */
int ringtone_alloc(struct mbuf **mbp, uint32_t *sratep, uint8_t *chp,
		   const char *name);

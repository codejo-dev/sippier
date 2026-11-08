/*
 * WebRTC audio processing (apm.cpp) behind a small C interface for aec.c.
 * Frames are 10 ms of interleaved S16 at 8, 16, 32 or 48 kHz.
 */
#include <stdint.h>

#define APM_MAX_FRAME (48000 / 100 * 2)

struct apm;

struct apm_stats {
	int delay_ms;           /* estimated echo delay, -1 if unknown       */
	double erl;             /* echo return loss [dB], -1 if unknown      */
	double erle;            /* echo return loss enhancement [dB], or -1  */
	double echo_likelihood; /* residual echo likelihood 0..1, or -1      */
};

struct apm *apm_new(void);
void apm_delete(struct apm *apm);
int  apm_render(struct apm *apm, const int16_t *frame, uint32_t srate,
		uint8_t ch);
int  apm_capture(struct apm *apm, int16_t *frame, uint32_t srate,
		 uint8_t ch);
void apm_get_stats(struct apm *apm, struct apm_stats *stats);

/*
 * WebRTC audio processing behind the C interface in apm.h.
 */
#include <new>
#include <modules/audio_processing/include/audio_processing.h>

extern "C" {
#include "apm.h"
}

using webrtc::AudioProcessing;
using webrtc::StreamConfig;

struct apm {
	AudioProcessing *ap;
};


extern "C" struct apm *apm_new(void)
{
	AudioProcessing::Config config;
	struct apm *apm = new (std::nothrow) struct apm;

	if (!apm)
		return nullptr;

	apm->ap = webrtc::AudioProcessingBuilder().Create();
	if (!apm->ap) {
		delete apm;
		return nullptr;
	}

	/* Every submodule is off by default. Settings as for a desktop
	 * WebRTC call. */
	config.echo_canceller.enabled = true;
	config.echo_canceller.mobile_mode = false;
	config.high_pass_filter.enabled = true;
	config.noise_suppression.enabled = true;
	config.noise_suppression.level =
		AudioProcessing::Config::NoiseSuppression::kModerate;
	config.gain_controller2.enabled = true;
	config.gain_controller2.adaptive_digital.enabled = true;
	apm->ap->ApplyConfig(config);

	return apm;
}


extern "C" void apm_delete(struct apm *apm)
{
	if (!apm)
		return;

	delete apm->ap;
	delete apm;
}


extern "C" int apm_render(struct apm *apm, const int16_t *frame,
			  uint32_t srate, uint8_t ch)
{
	int16_t out[APM_MAX_FRAME];
	StreamConfig config(srate, ch);

	return apm->ap->ProcessReverseStream(frame, config, config, out);
}


extern "C" int apm_capture(struct apm *apm, int16_t *frame, uint32_t srate,
			   uint8_t ch)
{
	StreamConfig config(srate, ch);

	return apm->ap->ProcessStream(frame, config, config, frame);
}


extern "C" void apm_get_stats(struct apm *apm, struct apm_stats *stats)
{
	webrtc::AudioProcessingStats s = apm->ap->GetStatistics(true);

	stats->delay_ms = s.delay_ms ? *s.delay_ms : -1;
	stats->erl = s.echo_return_loss ? *s.echo_return_loss : -1;
	stats->erle = s.echo_return_loss_enhancement ?
		*s.echo_return_loss_enhancement : -1;
	stats->echo_likelihood = s.residual_echo_likelihood ?
		*s.residual_echo_likelihood : -1;
}

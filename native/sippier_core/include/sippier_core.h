/*
 * sippier_core: a thin C layer over baresip with a small, FFI-friendly API.
 *
 * Threading: baresip runs its event loop on a dedicated native thread that
 * sc_init() starts. Every sc_* function is safe to call from any thread.
 *
 * Events: delivered as JSON strings through the callback passed to sc_init().
 * The callback may run on any thread. The receiver owns the string and must
 * release it with sc_string_free().
 */
#ifndef SIPPIER_CORE_H
#define SIPPIER_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SC_API __declspec(dllexport)
#else
#define SC_API __attribute__((visibility("default")))
#endif

typedef void (*sc_event_cb)(char *json);

/* Starts baresip. config_dir holds the log file and runtime state.
 * Blocks until initialisation finished. Returns 0 or an errno value.
 * Returns EALREADY if baresip is already running; the callback is then
 * replaced and existing accounts stay as they are. */
SC_API int sc_init(const char *config_dir, sc_event_cb cb);

/* Stops all calls and registrations and shuts baresip down. */
SC_API void sc_shutdown(void);

SC_API void sc_string_free(char *s);

/* Adds an account from a baresip account line without the password, e.g.
 * "Alice" <sip:alice@example.com;transport=tls>;regint=600
 * Returns an account id >= 0, or a negative errno value. */
SC_API int sc_account_add(const char *aor, const char *password);
SC_API int sc_account_remove(int acc);

/* Replaces an account's settings; the account keeps its id. An empty or
 * NULL password keeps the current one. Ends the account's calls and
 * unregisters it first; call sc_account_register() afterwards.
 * On failure the account is gone (its id is free again). */
SC_API int sc_account_update(int acc, const char *aor, const char *password);
SC_API int sc_account_register(int acc, int enable);

/* Starts an outgoing call. Writes the call id into id_out (NUL-terminated).
 * Returns 0 or an errno value. */
SC_API int sc_call(int acc, const char *uri, char *id_out, int id_out_size);
SC_API int sc_answer(const char *call_id);
SC_API int sc_hangup(const char *call_id);
SC_API int sc_hold(const char *call_id, int hold);
SC_API int sc_mute(const char *call_id, int mute);
SC_API int sc_send_dtmf(const char *call_id, char key);

/* Plays a key's DTMF tone locally, e.g. while dialling. sc_send_dtmf() and
 * received DTMF play it too. */
SC_API void sc_play_key_tone(char key);

/* Writes every SIP message to the log file. Contains auth hashes but never
 * plain passwords. Off by default. */
SC_API void sc_set_sip_trace(int enable);

/* Sets the DNS servers, comma separated ("1.2.3.4, [2001:db8::1]:53").
 * Needed on Android, where libre can't read the system's servers. */
SC_API int sc_set_dns_servers(const char *servers);

/* Audio devices as JSON: {"input": [{"id", "name"}], "output": [...],
 * "defaultInput": id, "defaultOutput": id}. Free with sc_string_free().
 * Empty lists where the platform routes audio itself (Android). */
SC_API char *sc_audio_devices(void);

/* Microphone and speaker for calls, and the device for ringing, as ids from
 * sc_audio_devices(); NULL or "" follows the system default, also when it
 * changes during a call. Running calls switch at once. Key tones play on
 * the call speaker. */
SC_API int sc_set_audio_devices(const char *input, const char *output,
				const char *ringer);

/* Names of the built-in ringtones as a JSON array, the default first.
 * Free with sc_string_free(). */
SC_API char *sc_ringtones(void);

/* Loops a ringtone on the ringing device until sc_ring_stop(), replacing
 * one already playing: a built-in name, or "file:<path>" for a sound file
 * (macOS: anything CoreAudio reads; elsewhere WAV). Unknown names and
 * unreadable files play the default. */
SC_API int sc_ring_start(const char *tone);
SC_API void sc_ring_stop(void);

/* Android battery saver, from an alarm while the device would otherwise
 * sleep: refreshes the registration of enabled accounts past half of the
 * expiry their provider granted, and sends UDP accounts' NAT keep-alives
 * (while awake the core sends those every 25 s itself). Returns the
 * milliseconds until the next call. */
SC_API int sc_keepalive(void);

/* Seconds the provider granted the account's last registration (fonial
 * gives 240 s for the 600 s asked), or 0 before the first one. */
SC_API int sc_account_expires(int acc);

/* The device's network or its addresses changed: rebinds the SIP
 * transports, moves running calls and registers enabled accounts again. */
SC_API int sc_network_changed(void);

#ifdef __cplusplus
}
#endif

#endif

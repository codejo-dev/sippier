# SIP Audio Calling: Research Notes for a Flutter SIP Phone

_Compiled 2026-11-02. Background reference for building a simple Flutter SIP softphone ("Sippier")._
_Updated 2026-11-04: iOS is out of scope for now; milestone 2 is Windows + Linux (see 1a.13)._
_Updated 2026-11-07: Linux is out of scope for now too; milestone 2 is Windows (see 1a.13)._

---

## 1. TL;DR

- **Protocol stack:** SIP (RFC 3261) does signalling, SDP (RFC 8866 + offer/answer RFC 3264) negotiates the media, and RTP/RTCP (RFC 3550) carries the audio. On top of that you need NAT traversal (rport, keep-alives, STUN/TURN/ICE) and optionally encryption (TLS for signalling, SRTP for media).
- **Codecs that matter in practice:**
  - **G.711** (PCMA/PCMU) is the universal fallback. Every PBX and SIP trunk supports it.
  - **G.722** is the "HD voice" codec on desk phones and PBXs.
  - **Opus** has the best quality per bit and dominates WebRTC and app-to-app calls, but not every trunk or desk phone supports it.
  - **G.729** only matters for legacy low-bandwidth links.
  - **telephone-event** (RFC 4733) carries DTMF.
- **The biggest decision** is which servers the app has to talk to:
  - **Your own PBX** (Asterisk, FreeSWITCH, Kamailio/OpenSIPS + rtpengine, 3CX): `sip_ua` + `flutter_webrtc` over WSS is free (MIT) and pure Dart. The server has to accept WebRTC-style media (DTLS-SRTP, ICE, rtcp-mux).
  - **Any SIP provider or PBX over UDP/TCP/TLS** (a generic softphone like Zoiper or Linphone): you need a native SIP stack. Options are **Siprix** (commercial, fastest to ship), **PJSIP** (GPLv2 or a commercial licence from Teluu) or the **Linphone SDK** (AGPLv3 or commercial).
- **Sippier's decision:** we connect to third-party providers (fonial, Vodafone), so we need a **native stack**. See section 1a.
- **Mobile reality:** you can't reliably keep a SIP socket open in the background. Incoming calls when the app isn't in the foreground need **push**: PushKit VoIP push + CallKit on iOS, FCM high-priority messages + Core-Telecom/ConnectionService on Android. A server-side component has to send those pushes.
- **Platform scope (2026-11-07):** macOS, Windows and Android. **iOS and Linux are out of scope for now** (iOS since 2026-11-04, Linux since 2026-11-07); their research (1a.10 and 9.1 for iOS, the Linux notes in 1a.13 and 1a.14) stays for a later return. See 1a.13.

---

## 1a. Sippier requirements and what follows from them (decided 2026-11-02)

**Requirements**
- **A general SIP phone:** it registers directly with **any standards-compliant SIP provider or PBX, worldwide**. There is no PBX of our own.
- **fonial** (cloud PBX) and **Vodafone Germany** are the owner's own providers. They serve as the **reference and test providers**, not the target market (see 1a.12).
- **Multiple accounts** at the same time.
- Platforms: **macOS, Windows, Android**. *(Until 2026-11-04 this read "macOS, iOS, Windows, Android, and optionally Linux", until 2026-11-07 "macOS, Windows, Linux, Android". iOS and Linux are out of scope for the next milestones; see 1a.13.)*

**What follows**

1. **`sip_ua` is ruled out.**
   - It requires DTLS-SRTP (WebRTC media), and Vodafone's interface spec says outright: *"DTLS is explicitly not supported."*
   - It also has no UDP signalling and no DNS SRV.
2. **We need a native SIP stack** that supports:
   - UDP/TCP/TLS
   - **SDES-SRTP** (`AES_CM_128_HMAC_SHA1_80`)
   - **DNS SRV**
   - PRACK/UPDATE
   - G.722 / G.711 A-law
   - several accounts at once
   - all five platforms (iOS is parked, but the stack shouldn't rule it out)
3. **Candidates:** Siprix (commercial), PJSIP via `dart:ffi` (GPLv2 or commercial), Linphone SDK via FFI or channels (AGPLv3 or commercial). See 1a.3. **Decided: open source with baresip (BSD) via `dart:ffi`, with PJSIP as the fallback.** See 1a.6–1a.8.
4. **Codecs:**
   - Generic default: **Opus, G.722, then PCMA/PCMU** (A-law first outside North America and Japan, µ-law first there), plus telephone-event.
   - Each account can edit and reorder the list.
   - (Until 2026-11-05 the fonial and Vodafone presets dropped Opus. Without presets, Opus stays in the offer and the provider picks a codec it supports.)
5. **Incoming calls on iOS when the app is in the background need a push proxy that we operate.** *(Parked with iOS, 1a.13.)*
   - Third-party providers won't send pushes to our app.
   - The proxy has to hold the SIP registration with fonial/Vodafone for the user. See 1a.4.

### 1a.1 Provider facts: Vodafone Germany

Source: *IP Anlagen-Anschluss (R.6) Interface Description*, dated 24 Apr 2026. This is the business SIP trunk spec; registration mode is the one relevant to a client.

| Topic | Vodafone requirement | Impact on the app |
|---|---|---|
| Transport / ports | UDP and TCP on 5060, **TLS on 5061**. TLS runs over TCP only; **no `sips:` URI**. | Support all three. Use `sip:` URIs with `transport=tls`. |
| TLS | **TLS 1.2 only.** DigiCert certificates (DigiCert Global Root G2). Server authentication only, using TCP/TLS connection reuse: the client keeps the connection open, and the SBC sends incoming calls over it. | Keep the TLS connection alive and reconnect at once if it drops. The system trust store already has the DigiCert root. |
| SRTP | **SDES only (RFC 4568), only `AES_CM_128_HMAC_SHA1_80`.** DTLS is not supported. | SDES-SRTP, preferably over TLS. |
| Codecs | The SBC adds **G.722, AMR-WB, AMR, G.711 A-law, telephone-event/16000** to the codec list if missing, and transcodes between them. Recommended ptime is 20 ms for G.711. **Opus isn't mentioned.** | Offer G.722, PCMA, PCMU and telephone-event. |
| DTMF | RFC 2833/4733 telephone events. Put **telephone-event last** in the `m=` line (some endpoints reject it when it's first). | Configure the SDP payload order. |
| Registration | **`Expires` ≥ 900** (lower values are rejected). **3 failed registrations block the client IP for 5 minutes.** **A second device with the same credentials replaces the first registration.** | Don't hammer a wrong password: stop on 401/403 and back off. Warn users that the app knocks the router or desk phone off that line, and the other way round. |
| Identity | E.164 global format `sip:+49…@host;user=phone`. Send P-Preferred-Identity or P-Asserted-Identity; otherwise the line's default number is used. CLIR uses an anonymous `From` and/or `Privacy: id`. | Normalise dialled numbers to +49. Allow choosing the caller ID per account. |
| PRACK / UPDATE / early offer | **Strongly recommended**, otherwise network announcements and tones (early media) may be missing. Put the SDP in the INVITE (early offer). | Turn on 100rel, UPDATE and early offer. |
| Hold | RFC 3264 `a=sendonly`/`inactive`. **Resume must carry an SDP offer**; `0.0.0.0` hold isn't recommended. | Standard hold via re-INVITE. |
| Transfer | **REFER isn't supported.** Transfer only via INVITE/re-INVITE (SIPconnect). | Not relevant: transfer is out of scope for Sippier (section 11). |
| NAT | The SBC ignores the private addresses in Via, Contact and SDP. It sends RTP to wherever the client's **first RTP packet** came from. If RTP stops (hold, VAD), the NAT entry can expire. | Send RTP right away, even silence. Don't use VAD/DTX. Send keep-alives (OPTIONS or CRLF). Router SIP ALG isn't suitable with TLS. |
| Session timer | Supported (RFC 4028). Intervals that are too short get `422`. | Use the standard session-timer support. |
| Testing | Dialling **113** behaves like 110/112 but plays a test announcement. | Use it to test emergency-call handling. |

Vodafone **residential** (cable or DSL) is a different situation:
- Forum users report the registrar `sip.kabelfon.vodafone.de:5060`, with the phone number as username.
- Vodafone moderators state that using the SIP credentials behind third-party devices is "not intended and not supported".
- Rented routers often don't reveal the credentials at all.
- **Treat residential Vodafone as best effort.** It also has the same "one registration wins" conflict with the customer's router.
- **Residential DSL has no TLS** (checked 2026-11-04): the IMS proxy `egfNN.fixed.vodafone.de` publishes only UDP in NAPTR/SRV, and its SBCs (`sbcNN.fixed.vodafone.de`) accept TCP 5060 but not 5061, over IPv4 or IPv6. SRTP would send its keys in clear text there, so don't offer it on that preset. The TLS/SDES rows above apply to the business trunk.

### 1a.2 Provider facts: fonial

Source: *Fact Sheet fonial Trunking*. fonial runs on the **plusnet** infrastructure.

| Topic | fonial | Impact on the app |
|---|---|---|
| Domain / proxy | Domain `sip.plusnet.de`, proxy `proxyXX.sip.plusnet.de` | Account form needs separate domain and outbound-proxy fields. |
| **DNS SRV** | **Mandatory.** Without SRV lookups, registration and calls fail. The UDP SRV answer for `sip.plusnet.de` lists 18 servers, too big for a UDP DNS reply, so it **needs TCP fallback**. The proxy SRV returns 3 prioritised servers and is preferred. | The SIP stack must do SRV with failover. Dart's `InternetAddress.lookup` can't do SRV. |
| Number format | E.164 `+49…` in To/From | Normalise numbers. |
| CLIR | `From: anonymous` + `P-Asserted-Identity` | Per-call CLIR option. |
| Codecs | G.711 (A-law, µ-law) supported; **G.722 recommended** | G.722 first. |
| DTMF | RFC 2833 | telephone-event. |
| Keep-alive | The server sends periodic **OPTIONS and expects 200 OK**, or the endpoint is treated as offline and calls aren't delivered. | Answer OPTIONS. Most stacks do this automatically; verify it. |
| TLS (checked 2026-11-04, not in the factsheet) | The outbound proxy `sbc.sip.plusnet.de` publishes `SIPS+D2T` → `_sips._tcp` → `sbc1`/`sbc2.sip.plusnet.de:5061`. TLS 1.3; certificate from GeoTrust TLS RSA CA G1 (DigiCert), with `sbc.sip.plusnet.de` and `sip.plusnet.de` in the SAN. `sip.plusnet.de` itself publishes only UDP SRV. SRTP isn't documented. | Registration over TLS works (2026-11-04). Calls over TLS offering plain RTP get an immediate `488 Not Acceptable Here` with no reason header, so fonial probably requires SRTP with TLS, as sipgate documents for itself. TLS + mandatory SRTP not tested yet. |
| Server IPs | 92.197.176.16–19, 92.197.177.16–19, 92.197.182.16–19 | Useful for firewall rules and debugging. |
| Fax | T.38 with G.711 fallback | Not relevant. |

That factsheet is for trunking. Softphone credentials come from the fonial customer portal. Cloud PBXs like fonial normally issue **separate SIP credentials per device**, which avoids the "one registration wins" problem; check this in the portal.

### 1a.3 Native stack options for all five platforms

| | **Siprix** (`siprix_voip_sdk` 1.1.5) | **PJSIP** (own `dart:ffi` plugin) | **Linphone SDK** (own FFI/channel plugin) |
|---|---|---|---|
| Platforms | Android, iOS, macOS, Windows, Linux (ready-made Flutter plugin) | All five (C library; we build it per platform) | All five (Linphone desktop runs on Win/macOS/Linux) |
| Multi-account | Yes | Yes (`PJSUA_MAX_ACC`, default 8, can be raised at compile time) | Yes |
| TLS / SDES-SRTP | Yes / yes (SRTP mode details to verify) | Yes / yes (also DTLS) | Yes / yes (also DTLS, ZRTP) |
| DNS SRV | **Not documented, verify in the trial** | Yes, built-in resolver. On mobile you must pass nameservers explicitly. | Yes (belle-sip resolver) |
| PRACK / UPDATE | Verify in the trial | Yes | Yes |
| G.722 / G.711 / Opus | Verify the codec list in the trial | Yes / yes / yes | Yes / yes / yes |
| Push client side | PushKit+CallKit and FCM built in. Who *sends* the pushes isn't documented, so assume our own server. | DIY (PJSIP has an iOS push/CallKit guide) | DIY. Its push ecosystem is Flexisip (AGPL). |
| Extras | Hold, DTMF, conference, blind and attended transfer, BLF, MESSAGE, MP3 recording, video | Everything, but each needs bridging | Everything, but each needs bridging |
| Licence | **Commercial.** The trial drops calls after 60 s; price on request. | **GPLv2+** (our app must be GPL) **or commercial** (Teluu) | **AGPLv3 or commercial** (Belledonne) |
| Effort | **Low.** Dart API exists. | **High:** native builds ×5, threading (marshal callbacks to Dart via `NativePort`), audio devices, CallKit audio-session handling | **High**, similar to PJSIP |

> **Superseded on 2026-11-02:** the app will be **open source**, so Siprix is out. See 1a.6 for the open-source decision. The original recommendation is kept below for reference.

**Recommendation (before the open-source decision):**
1. **Start with a 1–2 day Siprix spike.** Register a fonial account and a Vodafone account, then check DNS SRV, TLS, SDES-SRTP, G.722, PRACK and the `Expires` setting.
2. If it passes and the licence price works, use it. It's the only option that meets "5 platforms + multi-account + push" without months of native work.
3. If the app should be open source, or Siprix fails a provider test, fall back to **PJSIP via FFI**, or Linphone if AGPL suits us better.

### 1a.4 Incoming calls on each platform

| Platform | Without our own server | With a push proxy |
|---|---|---|
| macOS / Windows (and Linux, parked) | **Works while the computer is awake.** The app stays running (tray icon, start at login) and keeps registrations alive. Sleep ends that; see 1a.14. | Not needed |
| Android | **Mostly works.** A foreground service keeps a TCP/TLS registration with keep-alives. Costs battery; OEM battery savers may kill it; the Play Console needs the FGS type declared. | Better battery life and reliability (FCM high-priority message, then Core-Telecom) |
| iOS | **Only while the app is in the foreground.** iOS suspends background sockets, and VoIP keep-alive was dropped in iOS 10. | **Required:** PushKit VoIP push, then CallKit |

How a **push proxy** works for a third-party provider (this is how Acrobits SIPIS, Zoiper and SessionTalk do it):
1. A server holds the SIP registration with fonial/Vodafone *for* the user, using the user's credentials stored on the server.
2. When an INVITE arrives, it sends an APNs VoIP push (or FCM message).
3. The app wakes, reports the call to CallKit, connects to the proxy and receives the INVITE.
4. Media flows directly between the app and the provider.

Ways to build one:
- Kamailio (`uac_reg` for upstream registrations)
- OpenSIPS (`uac_registrant` + RFC 8599 push support)
- Asterisk (outbound registration + a trigger that sends the push)

Consequences:
- **We store users' SIP passwords server-side**, which brings GDPR/DSGVO and security duties.
- We run the infrastructure ourselves.
- For Vodafone, the proxy's registration is the only one, so it replaces the router's.

**Rollout (updated 2026-11-04):**
- MVP: desktop (macOS, Windows) + Android (foreground service). No server needed. Linux was part of it until 2026-11-07.
- iOS, Linux and the push proxy are parked (1a.13). Until then the plan was iOS with incoming calls only while in the foreground, plus the push proxy in phase 3.

### 1a.5 Multi-account and desktop details to design for

**Multi-account:**
- Each account has its own registration state, transport, outbound proxy, codec list, caller ID and CLIR default.
- The incoming-call UI shows which account was called.
- The dialler has an account picker and a default account.
- Call waiting works across accounts, including hold and switch.

**Account form fields** (German providers distinguish these):
- display name
- SIP username / phone number
- **auth username** (can differ, e.g. the customer number)
- password
- domain/registrar
- outbound proxy
- transport
- registration interval (Vodafone needs ≥ 900 s)
- SRTP mode (off / SDES)

**Desktop:**
- Input/output device selection
- Tray icon, start at login
- Native notifications for incoming calls
- Register `sip:`/`tel:` URL handlers: macOS `CFBundleURLTypes`, Windows registry (Linux, parked: `.desktop` `x-scheme-handler`)
- macOS microphone usage description, plus network client/server entitlements if sandboxed
- Windows firewall prompt for listening sockets

### 1a.6 Decision: open source, using baresip (PJSIP as fallback)

The app will be open source. That leaves three stacks:

| | **baresip + libre** | **PJSIP** | **Linphone SDK** |
|---|---|---|---|
| Licence | **BSD-3-Clause** | GPLv2+ | AGPLv3 (GPLv3 terms for client apps) |
| What our app's licence must be | **Anything** (MIT, Apache-2.0, GPL…) | GPL-compatible (GPLv2+/v3) | GPLv3/AGPLv3 |
| **Apple App Store** | **No licence conflict** | **Risky.** GPLv2 is widely considered incompatible with the App Store terms, and PJSIP's copyright belongs to Teluu, not us (see the VLC 2011 removal and Pidgin's FAQ). The iCall project, which uses PJSIP, recommends a commercial licence for App Store releases. | Same open question. Belledonne sells "App Store submission" as a paid service. |
| Platforms | Android 8+, iOS 10+, macOS 11+, Linux, Windows 10+ (mobile is libre's "Tier 2") | All five | All five |
| DNS NAPTR/SRV (RFC 3263) | Yes | Yes (pass nameservers on mobile) | Yes |
| TLS / SDES-SRTP | Yes / yes (`srtp` module; also DTLS-SRTP, ZRTP) | Yes / yes | Yes / yes |
| PRACK / UPDATE / SIP Outbound | Yes / yes / yes | Yes | Yes |
| G.722 / G.711 / Opus | Yes / yes / yes | Yes | Yes |
| Multiple accounts | Yes | Yes (default 8) | Yes |
| Audio drivers | AudioUnit/CoreAudio, WASAPI, AAudio/OpenSL ES, PulseAudio/PipeWire/ALSA | All platforms | All platforms |
| Existing Flutter wrapper | None usable. `baresip_flutter` is discontinued, Android-only and uses MethodChannel. | `pjsip_connect_flutter` covers Android and iOS only and bundles prebuilt binaries. | Android-only plugin |
| Community | Active, smaller; widely used in embedded devices and intercoms | Largest, most mature | Company-backed, mature, heavy SDK |

**Decision: baresip.**
- It's the only one whose licence doesn't create an App Store problem or force a licence on our app.
- It lists every protocol feature the providers need (RFC 3263 SRV, TLS 1.2, SDES-SRTP, PRACK, UPDATE, G.722, multiple accounts).
- It has audio drivers for all five platforms.

**Risks to check first:**
- iOS is a less-tested platform for libre. We need CallKit audio-session handling with the AudioUnit driver. *(Parked with iOS.)*
- Windows and Linux are libre **Tier 1** (tested in CI, MinGW-w64 and VS 2022 on Windows), so they carry less risk than the mobile platforms.
- The community is smaller than PJSIP's.
- Session timers aren't listed in the README; check the source. (REFER doesn't matter, because transfer is out of scope.)

**Fallback: PJSIP**, if baresip fails a provider or mobile-audio test. We'd accept GPL and the App Store risk, or buy a Teluu licence later.

**Licence hygiene:**
- Check the licence of every module's dependencies before enabling the module.
- OpenSSL 3 is Apache-2.0, libopus is BSD, and libre is BSD.
- Avoid modules that pull in **spandsp (LGPL)**, e.g. the `plc` module. Static LGPL linking on iOS has its own obligations.
- **Sippier itself is Apache-2.0** (decided 2026-11-02): explicit patent grant, contribution terms and name protection; the app already ships Apache-2.0 code via OpenSSL 3.
- Every build shows the third-party licence texts (baresip, libre, libg722, Opus, OpenSSL; on desktop also WebRTC audio processing and Abseil) via Flutter's `LicenseRegistry` / `showLicensePage`.

### 1a.7 FFI plugin architecture

```
Flutter app (Dart)                 ── UI, state, account storage (flutter_secure_storage)
  └─ package sippier_sip (Dart)    ── typed API: Account, Call, events as Streams
       └─ dart:ffi bindings        ── generated with ffigen from sippier_core.h
            └─ sippier_core (C)    ── thin shim we own: narrow API, events as JSON
                 └─ libbaresip + libre + OpenSSL + opus (static)
Platform glue (separate, MethodChannel or existing plugins):
  Android: Core-Telecom + foreground service · (iOS: CallKit + PushKit, parked)
  Desktop: tray, start at login, notifications, sip:/tel: URL handlers
```

**Threading:**
- libre runs a single-threaded event loop (`re_main`) on a dedicated native thread that the shim starts.
- **Dart → native:** commands are posted into the loop through libre's thread-safe `mqueue`. We never call baresip directly from the Dart thread.
- **Native → Dart:** baresip events (registration state, incoming call, call state, DTMF, errors) are serialised to small JSON strings and delivered through a **`NativeCallable.listener`** callback (Dart 3.1+). It can be called from any thread and runs asynchronously on the Dart isolate.

**Shim API sketch** (kept small on purpose, so the FFI surface stays tiny):

```c
int  sc_init(const char *config_dir, void (*on_event)(const char *json));
void sc_shutdown(void);
int  sc_account_add(const char *aor_line);   // baresip account syntax, returns account id
int  sc_account_remove(int acc);
int  sc_register(int acc, int enable);
int  sc_call(int acc, const char *uri);      // returns call id
int  sc_answer(int call), sc_hangup(int call, int code);
int  sc_hold(int call, int hold), sc_mute(int call, int mute);
int  sc_dtmf(int call, char key);
int  sc_set_audio_device(const char *in, const char *out);
```

**Native builds** (in CI, as prebuilt artifacts):

| Platform | Output |
|---|---|
| Android | NDK + CMake for `arm64-v8a`, `armeabi-v7a`, `x86_64` (`.so`) |
| macOS | Universal (arm64 + x86_64) dylib or framework |
| Windows | DLL for x64 and arm64 (MSYS2 + clang, 1a.13) |
| Linux (parked) | `.so` for x64 and arm64 |
| iOS (parked) | Static `.xcframework` (device + simulator) |

Start from `flutter create --template=plugin_ffi`. Also look at Dart build hooks (native assets) and check their current stable status.

### 1a.8 Spike plan

Exit criteria:
- Register and make a two-way call on **fonial and Vodafone**.
- Covered on **macOS and Android**, with iOS audio proven. *(iOS dropped from the exit criteria on 2026-11-04.)*

1. **macOS (dev machine).**
   - Build libre + baresip with the modules `g711`, `g722`, `opus`, `srtp`, `audiounit`/`coreaudio`, `stun`, `account`. Add the C shim and a Dart FFI binding.
   - fonial: register over TLS, check that DNS SRV resolves `sip.plusnet.de`, make an outgoing and an incoming call with G.722, send DTMF to an IVR.
   - Vodafone: `Expires` 900, SDES-SRTP, PRACK/UPDATE early media; call 113 for the test announcement.
2. **Android.** NDK build, AAudio, call on a real device, a foreground service keeping the TLS registration alive, Wi-Fi ↔ LTE handover.
3. ~~**iOS.** xcframework, AudioUnit + CallKit (start media only after `didActivate`), no echo on speaker.~~ Parked (1a.13).
4. **Windows.** WASAPI device selection. Now milestone 2 (1a.13). Linux (PulseAudio/PipeWire) was part of this step until 2026-11-07; parked.
5. **Go/no-go on baresip**, or switch to PJSIP.

**Spike results, macOS (2026-11-02): go for baresip.**

| | fonial | Vodafone DE (DSL) |
|---|---|---|
| Registration | ✅ 200 OK (UDP/IPv4, `sip.plusnet.de` via DNS SRV) | ✅ 200 OK (UDP/IPv6, domain `fixed.vodafone.de`, proxy `egfNN.fixed.vodafone.de` via NAPTR/SRV, user `+49…`, auth user `IMPI_49…`) |
| Outgoing call | ✅ ringing, answered, G.722 both ways | ✅ after the Service-Route patch: 183 early media, 180, answered, G.722 both ways, remote hang-up handled |
| Incoming call | ✅ INVITE through the router's NAT, answered, G.722 both ways (after enabling `call_accept`) | ✅ INVITE arrives and rings (M1 app, IPv6); answered on 2026-11-04. A caller hang-up arrives as `CANCEL` with Vodafone's own `Reason: X.int;reasoncode=0x0000030B`, not SIP 487 |
| DTMF, hold | hold/resume ✅ (M1 app). DTMF: receiving ✅; sending not confirmed (see below) | hold/resume ✅ (2026-11-04). DTMF: receiving ✅; sending not confirmed |
| TLS / SRTP | TLS registration ✅ on `sbc.sip.plusnet.de` (1a.2). Calls with plain RTP over TLS: 488. TLS + SRTP not tested yet | No TLS on residential DSL (1a.1), so no SRTP |

**Milestone 1 test (2026-11-04):** Android ↔ macOS on both providers, and calls to and from a mobile: audio and hold work.
- **Received keypad tones arrive:** the macOS log shows RFC 4733 events from the Android app and from a mobile.
- **Sent ones weren't heard on the other side.**
  - baresip logs "send DTMF digit" either way. With `dtmfmode=rtpevent` it silently drops the events when the remote SDP has no `telephone-event`, so the log proved nothing.
  - Mobile phones may also not play received RFC 4733 events as sound.
  - The app now uses `dtmfmode=auto` (SIP INFO when `telephone-event` isn't negotiated) and logs per key which way it goes. Confirm against an IVR (e.g. a voicemail PIN prompt) with SIP trace on.
- **Android TLS couldn't have worked:** Android's CA directories name files by OpenSSL's *old* subject hash, which OpenSSL 3 doesn't look up ("unable to get local issuer certificate"). The core now joins them into `cacerts.pem` at start, from the conscrypt APEX and otherwise `/system/etc/security/cacerts`. A bundle of the Pixel's 120 certificates verifies fonial's chain.

Findings:
- **Vodafone DSL is an IMS network.** Calls need the registration's `Service-Route` set (RFC 3608) as preloaded routes, or the SBC answers `407` with *"IP association no match, user not registered"*. baresip didn't support this, so we patch it (`native/patches/baresip-0001-service-route.patch`). It passes baresip's register and call selftests. **Upstream candidate.**
- `fixed.vodafone.de` has no DNS records; the `egfNN` proxies do.
- baresip codec names need the sample rate when it isn't 8000: `G722/16000/1`.
- baresip's `call_accept` defaults to `no`: incoming INVITEs then only raise `SIPSESS_CONN` and get no reply at all. When embedding baresip without its menu module, set `call_accept yes`.
- macOS: the `audiounit` module uses HALOutput, so there's **no echo cancellation** of its own. *Decided 2026-11-04: WebRTC audio processing instead of VoiceProcessingIO, so the desktop platforms share one echo canceller (1a.13).*
- Don't overwrite a loaded dylib in place: macOS kills the process. Replace the file instead.
- libre: calling `re_cancel()` inside `re_thread_enter()`/`re_thread_leave()` leaks the lock. Stop from a timer inside the loop instead.

Still open from the exit criteria: Vodafone incoming, DTMF and hold (macOS), then Android and iOS audio. These move into the first milestones of the real client. *(iOS parked on 2026-11-04.)*

**Milestone 1 build setup (2026-11-02):**
- `packages/sippier_core` is a plain Dart package with a **build hook** (`hook/build.dart`, `hooks` 1.x to match Flutter 3.41's runner). The hook runs `native/scripts/build.sh <os> <arch> <min-version>` and bundles `libsippier_core` as a code asset; Dart calls it through `@Native` functions. No library paths or plugin boilerplate.
- `build.sh` builds **OpenSSL 3.5.9 (LTS) and Opus 1.6.1 from release tarballs** (SHA-256 pinned) for every target, so neither platform depends on Homebrew libraries. baresip is built from a patched copy (`git archive` + `native/patches/`), so the submodule stays clean.
- **Android:** NDK 28+, API 28 minimum (AAudio). baresip's `aaudio` module already uses `VOICE_COMMUNICATION` usage and input preset, so the platform's echo cancellation applies. The `.so` links only system libraries and uses 16 KB page alignment (required by Google Play for Android 15+).
- **Android DNS:** libre can't find the system DNS servers on Android (no resolv.conf). The app reads them from `ConnectivityManager` and passes them in with `sc_set_dns_servers()`, also when the default network changes.
- **macOS app is sandboxed** (network client + server, audio input) and works; passwords use the legacy Keychain (`usesDataProtectionKeychain: false`), so no provisioning profile is needed.
- `permission_handler` 13 needs a newer Android Gradle Plugin than Flutter 3.41 ships; the app asks for the microphone itself in `MainActivity.kt`.
- **Vodafone: one registration per line, seen in practice (2026-11-02).** Outgoing calls from the Mac worked for a few minutes after registering, then every INVITE got `407 Proxy Authentication Required` (a registration refresh didn't help), and the de-REGISTER failed with `481 … 219 Wrong Contact in de-REGISTER`. The Mac's addresses hadn't changed and no other Sippier had the account, so most likely the router re-registered the same line. A fresh REGISTER took the line back. The app now explains 401/403/407 call failures and the Vodafone preset says to turn the line off in the router.
- **Registration failures in plain words (2026-11-05):** `RegistrationProblem` turns the provider's answer into a short summary for the account list ("Login rejected (not retried)") and advice for the account form, keeping the provider's own text for support.
  - The form also catches mistakes that hold for every provider before anything is sent: no `sip:` in the username or auth username, no `@domain` in the username, no spaces. An `@` stays allowed in the auth username, because some providers use email-like auth names.
  - **No provider-specific checks or messages** (decided 2026-11-05). A Vodafone check for `IMPI_…` was tried after an `IMPL_…` typo got `403 Forbidden - 6037 Identities do not match` on the Pixel, and was dropped.
- **Android ringing:** Android drops audio and vibration from apps it doesn't consider in front, even with a foreground service, and our own "UI is resumed" flag was wrong when the app started with the screen locked. The incoming-call notification now rings for every call (ringtone channel, `FLAG_INSISTENT`, CallStyle). Full-screen display over the lock screen needs the user to allow "full-screen notifications" (Android 14+); the app shows a banner for it.

### 1a.9 Backend: what's needed, and when

**MVP: no backend.**
- fonial and Vodafone *are* the SIP backend. The app registers directly with them, and media flows directly to their SBCs.
- Their SBCs handle NAT by sending RTP back to wherever ours arrives from, so we need **no STUN/TURN/RTP relay** for these providers.
- Desktop and Android (with a foreground service) receive calls without any server. iOS receives calls only while the app is in the foreground. *(iOS parked, 1a.13.)*

**Phase 3: push backend** (needed for background incoming calls on iOS; optional on Android, where it saves battery). *Parked with iOS on 2026-11-04 (1a.13); kept as the design if iOS returns.*

```
             (1) enrol: SIP creds + push token (HTTPS API)
  App  ───────────────────────────────────────────────►  Push proxy (Kamailio / OpenSIPS)
   ▲  ◄──── (5) app wakes, REGISTERs over TLS ───────   ├─ upstream REGISTER per account ──► fonial / Vodafone
   │        (6) proxy forwards the held INVITE           │  (2) INVITE arrives from provider
   │                                                     └─ (3) "device asleep" → push request
   │                                                            ▼
   └──────── (4) APNs VoIP push / FCM high-priority ──── Push gateway (holds APNs .p8 / FCM service account)
  Media (RTP/SRTP) always flows app ⇄ provider SBC, never through our servers.
```

| Component | Job | Options |
|---|---|---|
| **SIP push proxy** | Holds one upstream registration per enrolled account. Accepts the app's REGISTER (TLS). Holds an incoming INVITE, triggers a push, and forwards the INVITE once the app has registered again. Record-Routes the dialog so mid-call requests pass through it. Answers provider OPTIONS (fonial) while the app sleeps. | **Kamailio**: `uac` module remote registrations (`reg_db_url`, `uacreg` table) + `tsilo` (store the INVITE transaction, append a branch when the device registers) or `t_suspend`/`t_continue`, plus `registrar`/`usrloc`, `nathelper`, `tls`. **OpenSIPS 3.1+**: `uac_registrant` + built-in RFC 8599 push (`pn_enable`, `pn_providers`). Custom: Go `sipgo` or Node `drachtio`. |
| **Push gateway** | Sends the pushes. APNs: HTTP/2, `apns-push-type: voip`, topic `<bundle-id>.voip`, high priority, short or zero expiration, payload ≤ 5 KB with caller and call-id so the app can report to CallKit immediately. FCM: **HTTP v1 API** (the legacy API was shut down in July 2024) with an OAuth2 service account, data-only message with Android `priority: high` and a short TTL. | A small service (Go, Dart or Node). Matrix's *Sygnal* is a reference design for an open-source push gateway. |
| **Enrolment API** | The app uploads per-account SIP credentials, the device's push token (APNs VoIP or FCM) and platform. Also handles un-enrolment and token refresh. Credentials can't travel inside SIP, so this needs its own HTTPS endpoint. | Part of the push gateway or proxy service |
| **Storage** | Accounts, upstream registration state, device tokens, location table. | PostgreSQL or MySQL (Kamailio/OpenSIPS DB modules) |
| **Hosting** | Public static IPv4 (and IPv6), DNS name, TLS certificate (Let's Encrypt), ports 5060/5061 + HTTPS, **hosted in the EU** (GDPR). | A VPS with Docker Compose. Add Homer/HEP for SIP capture and Prometheus for metrics. |

**Open-source twist:**
- Only the holder of the app's APNs key (tied to our bundle ID and Apple team) can push to the App Store build.
- So: **make the SIP push proxy self-hostable** (Docker image), but run **one central push gateway** ourselves. Self-hosted proxies call that gateway.
- This is the Matrix/Sygnal model.

**Risks and duties:**
- **Vodafone IP blocking:** three failed registrations block the client IP for 5 minutes. On a shared proxy, *one user's wrong password blocks every Vodafone user on that proxy*. Validate credentials before enrolling, stop on 401/403, and consider separate egress IPs.
- **Vodafone single registration:** the proxy's registration replaces the customer's router or desk phone on that line.
- **Many registrations from one IP** may trip provider fraud or rate limits. Ask the providers before going live.
- **Stored SIP passwords:** encrypt them at rest and restrict access. Where the proxy supports it, store the digest HA1 instead of the plaintext password (MD5 digest only).
- **Legal (Germany):** processing call metadata (GDPR), and possibly telecom rules (TKG/TDDDG) if we relay signalling for the public. Get legal advice before running a public service.

**Other backend-ish pieces (none required for the MVP):**
- **CI:** GitHub Actions building the native libs and the app for macOS, Windows and Android (macOS and Windows runners; see 1a.13).
- **Desktop auto-update:** Sparkle (macOS), WinSparkle or MSIX (Windows).
- ~~**Provider presets** (fonial/Vodafone defaults): bundled JSON first, optionally hosted later.~~ Dropped on 2026-11-05 (1a.12).
- **Crash reporting:** self-hosted Sentry or GlitchTip, opt-in.
- **Dev/test:** Asterisk or FreeSWITCH in Docker as a local test PBX, SIPp, Wireshark/sngrep, plus real test accounts at fonial and Vodafone.

### 1a.10 iOS without a server (decided 2026-11-02: no server to maintain)

> **Parked on 2026-11-04:** iOS is out of scope for the next milestones (1a.13). Nothing in this section is scheduled; it stays as the starting point if iOS comes back. At that point: there's no `app/ios/` yet, `build.sh` needs `ios-arm64` and `ios-sim-arm64` targets, and the build hook needs an `OS.iOS` case. The Simulator covers UI, registration and calls with the Mac's audio, but CallKit, echo cancellation, background suspension and the keep-alive below need a real iPhone.

**The hard limit:**
- iOS suspends a backgrounded app within seconds. Only a **VoIP push** wakes it for a call, and a push can only come from a server holding our APNs key.
- So with no server, the iOS app **can't ring when it isn't in the foreground**.
- Everything else works without a server: outgoing calls, incoming calls while the app is open, and calls that keep running when the screen locks (CallKit + the `audio`/`voip` background modes).

| Workaround | Verdict |
|---|---|
| **A. Foreground-only + unregister on background + provider-side fallback** | **Chosen.** No server, App Store-safe. Details below. |
| B. Local Push Connectivity (`NEAppPushProvider`, iOS 14+): an app extension keeps a persistent connection **on configured Wi-Fi SSIDs only** and can trigger CallKit via `reportIncomingCall(userInfo:)` | **Parked.** Needs an entitlement that Apple must approve. Apple positions it for "a local, restricted network that doesn't have access to APNs", which a home or office Wi-Fi with internet isn't. It doesn't work on cellular. And it's architecturally hard: the SIP dialog would live in the extension while the media lives in the app. |
| C. Silent-audio or location keep-alive | **Not in the App Store, and not in EU alternative marketplaces either.** Guideline 2.5.4 ("background services only for their intended purposes") is marked as applying to Notarization too. **Possible in an opt-in sideload build** that never goes through Apple review; see below. |
| D. Legacy VoIP keep-alive sockets (`setKeepAliveTimeout`) | **No.** Deprecated since iOS 10. The `voip` background mode now only goes with PushKit and CallKit. |
| E. Desktop app sends the pushes itself | **No.** It would have to ship our APNs key inside an open-source app, and anyone could extract it and push to every user. |
| F. Someone else's server (CPaaS such as Twilio, Telnyx, Vonage or Sinch, which have push for their own SDKs) | Possible, but it changes the architecture: route calls through their platform at per-minute cost. It's still a server, just not ours. |
| G. Provider webhooks + serverless push function | Only for providers with call webhooks. **sipgate.io** sends a `newCall` webhook and can be steered with an XML reply; fonial and Vodafone document nothing comparable. A Cloudflare Worker can sign APNs `.p8` tokens and send VoIP pushes (reference: *AgentCall*, MIT). The catch: a provider usually won't offer an already-ringing call to a contact that registers late, unless the webhook reply or sequential ringing routes it to the device afterwards. |
| H. Hosted push gateway run by someone else | **Belledonne (Linphone)** offers a paid SaaS push gateway for third-party SIP accounts, priced case by case; Flexisip itself is AGPLv3 if self-hosted. Zoiper and Acrobits push services only work with their own apps. Using one of these for *our* app would need our APNs credentials on their side. |

**Web check (2026-11-02): no hidden trick exists.**
- **Apple DTS (Quinn, Apple Developer Forums, Oct 2022), answering "how can we receive incoming calls in background without push":** there are exactly two ways, PushKit and Local Push Connectivity. Local Push "is only useful if you're building an app for a restricted environment, like a cruise ship. For a general-purpose VoIP you must use PushKit." Apps that seemed to manage without push were probably "relying on the legacy VoIP infrastructure, which is no longer supported".
- **Local Push entitlement:** forum reports describe repeated denials (a video-intercom use case) and approvals for development only, with Apple asking for a product description before App Store release.
- **What other softphones do:**
  - Zoiper's free tier rings only while the app is open; push is a paid Zoiper service.
  - Linphone's stock app gets pushes only from Belledonne's Flexisip servers. For third-party SIP servers, the PBX must send pushes, or you run or buy a Flexisip push gateway.
  - Older reports of GS Wave ringing in the background over plain TCP date from old iOS versions.
- **Yak**, an iOS client built on baresip, also needs "your own push relay" for incoming calls.
- **Without push,** Siprix warns that an incoming call doesn't trigger CallKit, which can cause "no audio".
- **Silent-audio keep-alives** are rejected under App Review guideline 2.5.4.

**Option A in detail:**
1. **On foreground:** register all accounts. Calls can be made and received while the app is open.
2. **On background:**
   - Start a background task (`beginBackgroundTask`, about 30 s) and send **REGISTER with `Expires: 0`** for every account.
   - Otherwise the provider keeps sending calls to a dead contact: the caller hears ringing for nothing, and the provider's "unreachable" forwarding never fires.
   - Skip the unregister if a call is active; CallKit keeps the app alive then.
3. **Provider-side fallback, set once by the user** (the app's onboarding should explain it):
   - **fonial:** parallel ringing or a ring group that includes the user's mobile number, or forwarding "when not registered / no answer" to the mobile. The call then rings on the iPhone's normal phone app.
   - **Vodafone:** call forwarding when unreachable or on no answer. Forwarded calls may be charged.
4. **Vodafone caveat:**
   - Registering from the iPhone replaces the router's or desk phone's registration, and unregistering leaves the line unregistered until the router re-registers on its own schedule.
   - **Recommend not using the iOS app on a Vodafone line shared with a router or desk phone.** fonial is fine, because each device gets its own SIP credentials.
5. **UX:**
   - Say it clearly in the app: *"On iPhone, Sippier rings only while the app is open."*
   - Offer a "stay reachable" mode: keep the app open, screen dimmed via the proximity/idle settings, ideally while charging.

**Option S: sideload build flavor (opt-in, for technical users) — decided 2026-11-02 to prepare it**

**Distribution paths without any Apple review:**

| Path | Validity | Limits | Who it's for |
|---|---|---|---|
| Build from source in Xcode, free Apple ID | 7 days, then re-install | 3 sideloaded apps per device | Anyone with a Mac; open source makes this possible |
| Build from source, paid developer account ($99/yr) | 1 year | Your own devices | You personally |
| AltStore (classic) / SideStore with the user's own Apple ID | 7 days (free), auto-refresh: AltServer on the same Wi-Fi, or SideStore over a local VPN (LocalDevVPN) | 3 apps (free); LiveContainer works around this | Tech-savvy users without Xcode |
| Ad-hoc build from our paid account | 1 year | Max 100 registered devices per type per year (UDIDs) | Small tester groups |

Not suitable:
- **EU alternative marketplaces / web distribution:** they need Notarization, which enforces 2.5.4.
- **Enterprise certificates:** employees only; public distribution gets the certificate revoked.
- **TestFlight:** Beta App Review applies, and builds expire after 90 days.

**How the keep-alive would work (to be proven on a real iPhone):**
1. **Keep the app running.** While idle, play a silent loop through `AVAudioEngine` with `AVAudioSession` category `.playback` + `.mixWithOthers`, under the `audio` background mode. `.mixWithOthers` lets music from other apps keep playing.
2. **Show incoming calls.** The app is still running, so when an INVITE arrives it can report the call with `CXProvider.reportNewIncomingCall` and get the full native call screen, even on the lock screen, without PushKit. Apple DTS says VoIP apps should declare both the `audio` and `voip` background modes.
3. **During a call:** stop the silent loop, because CallKit activates its own `playAndRecord` session. Restart it after the call ends.
4. **Handle interruptions.** A GSM call, Siri, or an app taking exclusive audio interrupts the loop. Restart it on `interruptionEnded` and whenever the app becomes active, and show "not reachable" in the app if it can't restart.
5. **Location as a fallback keep-alive:** worse. It needs the "Always" permission, shows the location indicator, and drains much more battery. Only if audio proves unreliable.

**Known limits:**
- **Battery:** the audio hardware stays on. Measure this before promising anything.
- **iOS can still kill the app** under memory pressure. After a reboot nothing runs until the user opens the app.
- **iOS updates may break the trick** at any time.

**Keeping the App Store build clean:**
- **One codebase with a compile-time flag** (`SIPPIER_SIDELOAD`: a Swift compilation condition, plus a Dart define for the settings UI).
- The App Store build declares `audio` + `voip` for real calls but **contains no keep-alive code**.
- The sideload build adds the keep-alive and a settings toggle: "Stay reachable in the background (uses more battery)".

**Platform summary with no server:**

| | Outgoing | Incoming, app open | Incoming, app closed or background |
|---|---|---|---|
| macOS / Windows (and Linux, parked) | ✅ | ✅ | ✅ while the computer is awake (runs in the tray; 1a.14) |
| Android | ✅ | ✅ | ✅ (foreground service; battery cost) |
| iOS (App Store) | ✅ | ✅ | ❌ → provider forwards to the mobile number |
| iOS (sideload flavor) | ✅ | ✅ | ⚠️ while the keep-alive runs (to be proven; battery cost) |

### 1a.11 With a server: one Vodafone line ringing on many devices

**Yes, a server is the way to get multiple devices on one Vodafone line.**
- Vodafone accepts only **one registration per line**; a second registration replaces the first.
- So the server holds that one registration, and every device (desktop, Android, iPhone, iPad, desk phone, even a FRITZ!Box) registers to **our server** instead.
- In Vodafone's terms the server is simply a small PBX on an *IP Anlagen-Anschluss*, which is exactly what registration mode is meant for.

```
                Vodafone A-SBC
                     │  ONE registration (TLS 5061, Expires ≥ 900, SDES-SRTP)
                     ▼
           Our server (proxy or PBX + push sender)
   ┌──────────┬───────────┬───────────┬───────────┬──────────────┐
 Desktop    Android     iPhone      iPad      Desk phone /
 (online)   (FCM wake) (VoIP push) (VoIP push) FRITZ!Box (online)
```

**Incoming call to several devices:**
1. Vodafone sends the INVITE to the server.
2. The server **forks right away** to devices that are already registered (desktop, desk phone). At the same time it sends **VoIP pushes to every sleeping iPhone/iPad and FCM messages to Android devices**, keeping the transaction open.
3. Mobiles wake and show CallKit or Android's call UI. They register, and the server **adds them to the ringing set** (Kamailio `tsilo` was built for this multi-device case; with Asterisk, dial the devices once they're reachable).
4. **The first device to answer wins.** The server CANCELs the others with `Reason: SIP;cause=200;text="Call completed elsewhere"` (RFC 3326).
5. An iPhone that woke but hadn't registered yet still has to finish the CallKit report, because every VoIP push must be reported. It then ends the call immediately with reason `.answeredElsewhere`.
6. Media flows from the answering device to Vodafone: directly if the server is a proxy, through the server if it's a B2BUA.

**Outgoing calls:**
- Devices send calls to the server, which forwards them to Vodafone using the line's identity (P-Preferred-Identity `+49…`).
- Devices get **their own server credentials**. The Vodafone password stays only on the server.

**Two ways to build it:**

| | **SIP proxy** (Kamailio / OpenSIPS) | **B2BUA PBX** (Asterisk / FreeSWITCH) |
|---|---|---|
| Push and multi-device | Built in: Kamailio `uac` (upstream registration) + `tsilo` (late branches); OpenSIPS `uac_registrant` + RFC 8599 | Custom: dialplan/ARI triggers the push, then dials the devices once registered |
| Media | Direct between device and Vodafone (light server) | Through the server (bandwidth; small extra latency) |
| Codecs / SRTP | Each device must meet Vodafone's rules (SDES `AES_CM_128_HMAC_SHA1_80`, G.722/PCMA) | Separate on each side: Vodafone leg SDES + G.722/PCMA, device legs can use anything (Opus, DTLS) |
| Transfer, park, internal calls, voicemail | Limited (Vodafone has no REFER). Not needed: out of scope. | All internal, if ever wanted |
| Fit | **"Ring all my devices, answer anywhere"** | A real small phone system on top of the Vodafone line |

Sippier is a simple phone without transfer, so the **SIP proxy (Kamailio or OpenSIPS)** is the better fit: lighter, media direct, multi-device push built in. Asterisk would only make sense if PBX features become wanted.

**Caveats:**
- **The router and desk phones must move to the server.** A FRITZ!Box can register to our server as its "telephony provider", and desk phones register directly. If anything registers to Vodafone directly, it knocks the server off the line.
- **Simultaneous calls** are limited by the booked voice channels on the Vodafone line.
- **IP block risk on a shared server:** Vodafone blocks a source IP for 5 minutes after 3 failed registrations, which would hit every customer on that IP. Mitigate with **"check in the app first, then hand over to the server"** (below). That makes one shared server IP acceptable at small scale; a separate instance or IP per customer line remains the safest option.
- **Residential Vodafone** (cable/DSL) lines aren't meant for third-party equipment. Business *IP Anlagen-Anschluss* is the supported case.
- **Ops:** it's still a server to run: updates, TLS certificates, monitoring, backups.

**Credential onboarding: check in the app first, then hand over to the server**

The goal: wrong passwords fail from the *user's* IP, never from the shared server IP.

1. **The app checks the credentials** from the user's own network.
   - Flow: DNS SRV → TLS 5061 → REGISTER (`Expires: 900`) → `401` challenge → REGISTER with digest.
   - `200 OK` means the credentials are valid.
   - Only the **second** 401/403 (after we've answered the challenge) counts as a failure. The first 401 is just the normal challenge.
   - On failure: stop and show "wrong credentials". No automatic retry. Allow at most one manual retry, then show "wait 5 minutes", since Vodafone blocks on the 3rd failure.
2. **Possibly gentler alternative:** a *query-only* REGISTER without a Contact header (RFC 3261 §10.2.3) checks the credentials **without changing bindings**, so it wouldn't knock anything off the line. However, Vodafone's spec says Contact must be present on the initial registration, so the SBC may reject it. **Test this in the spike.**
3. If step 1 used a normal REGISTER, the app **unregisters right away** (`Expires: 0` on its own Contact). It then uploads the credentials to the server over HTTPS, and the server stores them encrypted.
4. **The server registers within seconds** and takes over the line. That's expected in this design; the router has to point at the server.
   - If the server's first attempt fails even though the app succeeded, **stop immediately**.
   - Likely cause: the line only accepts registrations from Vodafone's own access network (possible on residential lines; business registration mode works "via any Internet Access").
   - Tell the user, rather than retrying.
5. **Ongoing: one-strike rule on the server.**
   - Credentials can go bad later (password changed in the Vodafone portal, contract change).
   - On the first auth failure during a refresh, the server **stops registering that account**, marks it "credentials invalid", and pushes "please re-enter your Vodafone password" to the user's devices. Re-checking happens in the app again (step 1).
6. **Global limiter on the server.**
   - It's unclear whether Vodafone counts failures per account or per source IP. Assume **per IP across all accounts**.
   - So allow **at most 1 failed upstream authentication per Vodafone SBC per 5 minutes across all tenants**, and queue the rest.
   - Treat `503` separately: it means "this SBC is unavailable", not a credentials problem. Fail over to another SBC from DNS.
7. **Leftover risks:**
   - A user checking from mobile data sits behind carrier NAT. A block there briefly affects other Vodafone SIP users on that NAT IP; that's minor.
   - Many registrations from one server IP may still trip Vodafone's fraud or rate limits. Ask Vodafone before going live.

If background ringing on iOS becomes a must-have later, the only robust path is the push backend in 1a.9. A small managed container on Fly.io, Railway or similar reduces the upkeep but doesn't remove it.

### 1a.12 Going general: standards-based core + provider presets

> **Changed on 2026-11-05: no provider presets.** The account form is one generic form, without a provider dropdown, hints or provider-specific checks; the M1 presets (fonial, Vodafone DE) were removed. New accounts start with a 600 s registration interval: a provider that wants longer answers `423` with `Min-Expires`, and libre follows. Codecs the provider lacks drop out of the offer. Provider facts stay in this document (1a.1, 1a.2) for reference. The "Preset can override" column below is history.

**Principle:**
- The core speaks plain, standards-based SIP. Provider quirks live in **data (presets)**, never in code paths.
- fonial and Vodafone DE become the first two presets, next to **"Other SIP provider"**.
- "General" means *any standards-compliant SIP account*, not every exotic feature (see section 11 for what's out of scope).

**What going general adds** (most of it is per-account settings with sensible defaults):

| Area | Generic behaviour | Preset can override |
|---|---|---|
| Server discovery | RFC 3263 NAPTR/SRV, falling back to A/AAAA, on the account domain. Optional outbound proxy. | Fixed proxy (e.g. fonial `proxyXX.sip.plusnet.de`) |
| Transport | Auto (NAPTR) or UDP / TCP / TLS. Many smaller providers are still UDP-only. | Vodafone: TLS 5061 |
| Encryption | SRTP mode: off / optional SDES / mandatory SDES | Vodafone: SDES `AES_CM_128_HMAC_SHA1_80` |
| Codecs | Opus, G.722, PCMA/PCMU in region order, + telephone-event; user can reorder. G.729 isn't in baresip's module list, so add it only on demand. | fonial/Vodafone: G.722, PCMA, PCMU |
| NAT | rport + keep-alives always. **Optional STUN server** (no default third-party server; user or preset sets one). ICE/TURN modules available if a provider needs them. | fonial/Vodafone: none needed (their SBCs handle NAT) |
| Registration | Interval setting (default 600 s), "register: yes/no" (outgoing-only accounts), back-off on failures, never hammering a 401/403 | Vodafone: ≥ 900 s, max 2 auth attempts |
| Auth | Separate **auth username**, optional realm, digest MD5/SHA-256 | Vodafone: auth user = registration ID |
| Numbers | E.164 normalisation from the account's **country** (libphonenumber-style Dart package), dial prefix/strip rules, `user=phone` toggle | fonial/Vodafone: `+49`, `user=phone` |
| DTMF | RFC 4733 (default) / SIP INFO / in-band | none |
| Caller ID | Display name; optional P-Preferred-Identity; per-call CLIR | Vodafone: PPI with the line number |
| Early media | PRACK/100rel, UPDATE, early offer: on by default | none |

**Generic concerns that didn't matter for "just me":**
- **Emergency calls (112/911…):** VoIP emergency routing depends on the provider and the registered address. On Android (and iOS, if it returns), by default **hand emergency numbers to the native dialer** (`tel:`), with a per-account opt-in to send them over SIP. Desktops have no native dialer, so show a one-time notice that emergency calls go through the SIP provider.
- **Localisation:** English as the default plus German (Flutter `intl`/ARB). Open source makes community translations easy. *Done 2026-11-07:* `app/lib/l10n/app_en.arb` (template) and `app_de.arb`, German with "du". The app follows the system's display language, or the one picked under Settings > General > Language (System, English, Deutsch), e.g. for a German user on an English Windows. On Android 13+ the pick also becomes the app's language (`LocaleManager`), so the notifications follow it. Native strings: Android's notifications and channels in `res/values*/strings.xml`; the macOS menu bar's and Windows tray's Open/Quit come from the ARB files with the status. Open: macOS `NSMicrophoneUsageDescription` and the main menu (`MainMenu.xib`) are English only, as they need `.lproj` files in the Xcode project.
- **Provisioning (nice to have):** import an account from a QR code or URL, as many providers and PBXs offer. Export and import accounts too.
- **App Store distribution** (iOS, parked):
  - **China:** CallKit isn't allowed there, so leave out the China storefront or disable CallKit for it.
  - **Encryption export compliance:** TLS/SRTP count as standard encryption. Declare it (`ITSAppUsesNonExemptEncryption` + the App Store Connect questions).
  - A privacy policy is required.
- **Community presets:** keep presets as JSON files in the repo (`presets/<country>/<provider>.json`) so users can contribute tested settings for their providers via pull requests. Mark each preset "tested by N users".
- **Broader testing:**
  - Your own providers (fonial, Vodafone).
  - A local Asterisk and a local FreeSWITCH configured for UDP, TCP, TLS, SRTP on/off, and with or without NAT handling.
  - A couple of free public SIP services.
  - Beta testers abroad (Play internal testing, Windows preview builds).

**What doesn't change:** baresip (already generic), the no-server MVP, the target platforms (1a.13), and the optional server. The proxy design in 1a.11 works with any provider; Vodafone's single-registration rule is simply a preset fact.

### 1a.13 Platform scope: iOS and Linux out, Windows next (decided 2026-11-04; Linux out 2026-11-07)

**Decision:**
- **iOS is out of scope for the next milestones.** Parked with it: the iOS build (xcframework, CallKit), the sideload flavor and keep-alive (1a.10), App Store topics (1a.12) and the push backend (1a.9), which only iOS strictly needs.
- **Linux is out of scope too (decided 2026-11-07).** Until then it shared milestone 2 with Windows. Its notes are under *Linux (parked)* at the end of this section, and its sleep research in 1a.14.
- **Windows is milestone 2.** Like macOS, it receives calls with no server (1a.4), and libre lists it as Tier 1.
- The iOS and Linux research stays in this document for a later return.

| Milestone | Platforms | Status |
|---|---|---|
| 1 | macOS, Android | In progress |
| 2 | Windows | In progress (started 2026-11-06) |
| Later, maybe | iOS, Linux | Out of scope for now |

**Native core (`build.sh` + build hook):**
- **Windows:** start with `windows-x64`; arm64 later. The hook calls `bash`, which Windows doesn't have. Pick the toolchain at the start of milestone 2:

  | | (a) MSYS2 UCRT64 + clang | (b) MSVC (VS 2022) |
  |---|---|---|
  | `build.sh` | Runs almost unchanged (OpenSSL target `mingw64`); the hook calls MSYS2's bash | Needs a PowerShell twin of `build.sh` |
  | Extra installs | MSYS2 | Strawberry Perl + NASM for OpenSSL (`VC-WIN64A`); VS 2022 is already required by Flutter |
  | Upstream CI | libre and baresip test MinGW-w64 | libre and baresip test MSVC |
  | Notes | Link the runtime statically so the DLL needs no MinGW DLLs. Debug info is DWARF unless clang emits CodeView. | Native PDBs for the VS debugger |

  **Lean (a):** one build script for every platform. The C API keeps the DLL independent of Flutter's MSVC runtime.

  **Decided 2026-11-06: (a), with MSYS2's CLANG environments.** CLANGARM64 for `windows-arm64`, CLANG64 for `windows-x64` (both clang with the UCRT). Built and tested first on Windows 11 on Arm, where Flutter only builds `windows-arm64`; x64 comes from CI or an x64 PC.
  - The hook starts `bash -l` with `MSYSTEM` set for the target. Hooks only pass a few environment variables (`PATH`, `SYSTEMDRIVE`, …), so it finds MSYS2 through `PATH` (its folder or `usr\bin`) or in `C:\msys64`.
  - OpenSSL has no MinGW target for arm64, so `native/scripts/openssl-mingwarm64.conf` adds one: `mingw64` without `-m64` and without assembly. x64 uses `mingw64`.
  - Opus presumes NEON only when CMake says `aarch64`, and Windows says `ARM64`; its runtime CPU detection doesn't exist for MinGW on ARM. `build.sh` presumes NEON, as Opus's autotools build does.
  - zlib is off (`CMAKE_DISABLE_FIND_PACKAGE_ZLIB`): libre only uses it for crc32, and MSYS2's is a DLL. libg722's static library is `libg722_static.a` on Windows; `build.sh` renames it so baresip finds it.
  - `sippier_core.dll` links the MinGW runtime, libc++ and winpthreads statically (`-static`). It imports only Windows system DLLs and the UCRT, which Windows 10+ includes.
  - Git for Windows checks out with CRLF (`core.autocrlf`), which bash and the patches don't take, so `.gitattributes` keeps `*.sh` and `*.patch` LF.
- **Windows core (2026-11-06):**
  - `wasapi` opens its default device only for the device name `default`; Sippier's "system default" is an empty name. `baresip-0004-wasapi-default-device.patch` treats both as the default communications device (**upstream candidate**).
  - `devices.c` lists devices through the MMDevice API (friendly name, endpoint id as the id `wasapi` opens, default *communications* devices) and follows default changes with `IMMNotificationClient`. The wasapi module's own list has only endpoint ids.
  - `power.c` uses `PowerRegisterSuspendResumeNotification` (no window needed). Windows gives a suspend about 2 s, so the callback waits up to 1.8 s for the unregisters.
  - **TLS:** OpenSSL can't read the Windows certificate store, and baresip doesn't verify servers without a CA file. Like on Android, the core writes `cacerts.pem` at every start, here from the `ROOT` store. **Open:** Windows downloads roots on first use (automatic root update), so a provider's root may be missing until some Windows API has asked for it. A fresh VM had 26 roots. Options: verify the chain with `CertGetCertificateChain` (which fetches missing roots), or ship Mozilla's bundle as a fallback.
  - The runner's manifest sets the UTF-8 code page, so the core's `fopen()` with UTF-8 paths also works for non-ASCII user names.
  - `dart test` in `packages/sippier_core` passes on Windows (arm64): the hook builds the DLL, the core starts, lists devices, registers `aec` and exports the CA bundle.
- **Audio module:** `wasapi`, which opens the default *communications* device (`eCommunications`).
- **Echo cancellation:** `wasapi` doesn't cancel echo on its own. Use the same canceller as macOS (since 2026-11-04):
  - **`native/sippier_core/src/aec.c`** registers an audio player and source named `aec` that wrap the real module (config `audio_player aec,audiounit`; device syntax `<module>[:<device>]`). Every frame handed to the speaker goes to WebRTC as the echo reference. Every recorded frame is processed before baresip gets it, in 10 ms frames with 10 ms of added latency. Ringing and key tones go to the module directly.
  - **`apm.cpp`** is the C++ side: echo canceller (AEC3), high-pass filter, moderate noise suppression and adaptive digital gain. It logs `aec: delay … ms, ERL …, ERLE …, echo likelihood …` every 10 s during a call.
  - **Offline check** (synthetic echo, odd callback sizes): 49 dB less echo with a 70 ms echo path, and 54 dB with 250 ms. The reported ERLE (around 6 dB) covers only the linear filter; the suppressor does the rest.
  - **Real call (2026-11-04, MacBook speakers, Vodafone, G.722, 1:41 min):** no echo heard on the mobile. The delay estimate settled at 60 ms after about 20 s and stayed there. ERL was 14.6 dB (speaker-to-mic coupling) and the residual echo likelihood 0.15–0.29. With baresip's filter, echo had still been audible in the same test.
  - **Why not baresip's `webrtc_aec` filter**, which was tried first:
    - baresip 4.12's module never enables the canceller. It creates the processor without `ApplyConfig()`, and every submodule is off by default. A patch fixed that.
    - It still left echo in a real call. The filter feeds the canceller decoded audio *before* the jitter buffer (`audio_buffer 20-160`), so the echo delay it sees changes with the buffer level and with packet bursts. Both are **upstream candidates** to report.
  - `build.sh` builds **webrtc-audio-processing 1.3** (PulseAudio's packaging of WebRTC's audio processing; BSD-3-Clause plus WebRTC's patent grant) with Meson. Meson's wrap fetches **abseil 20230125.1** (Apache-2.0). Both texts are on the licences screen. Version 1.x has the stable `AudioProcessingBuilder().Create()` API that `apm.cpp` uses.
  - Windows needs no Meson cross file: each MSYS2 environment builds for its own architecture (done 2026-11-06). `CMakeLists.txt` has the `--start-group` link for GNU ld and lld, and `WEBRTC_WIN`/`WEBRTC_POSIX`.
  - Android keeps the platform's echo cancellation (`VOICE_COMMUNICATION`).
- **DNS:** libre finds the system's DNS servers itself on Windows (`src/dns/win32`), so there's no `sc_set_dns_servers()` call like on Android.

**App (Flutter):**
- `flutter create --platforms=windows .` in `app/` added the runner (2026-11-06).
- **Platform bridge:** the macOS runner implements `startRinging`, `stopRinging` and `updateStatus` (menu bar icon). Methods a platform doesn't implement are no-ops (`MissingPluginException` is caught), so the app ran before the Windows runner did anything. It needs:
  - a tray icon showing registration state, with Open and Quit
  - a ringtone: done in the core since 2026-11-04 (1a.16), so the runner only shows the call
  - an incoming-call notification with Answer and Decline (Windows toast)
  - bringing the window to the front on answer
  - Plugins (tray, notifications, start at login) or our own runner code: decide at the start of milestone 2.
  - **Windows tray, done 2026-11-07, in the runner's own code** (`flutter_window.cpp`, no plugin, like the macOS menu bar): the mark in colour while an account is registered, in grey while none is, the status as tooltip and menu line, and Open and Quit. Closing the window hides it. Quit goes through Flutter's exit request, so `onExitRequested` shuts the core down (unregisters) before the window goes. `startRinging` shows the window and flashes the taskbar button, since Windows may refuse to bring it to the front. The icons come from `branding/generate.py`.
- **Password storage:** `flutter_secure_storage` supports Windows out of the box.
- **Microphone access:** Windows has no runtime prompt for desktop apps. If "Let desktop apps access your microphone" is off, capture fails or stays silent, so detect it and link to `ms-settings:privacy-microphone`.
- The desktop list in 1a.5 applies too: device selection, start at login, `sip:`/`tel:` handlers, Windows firewall prompt.

**Build machines and CI:**
- Flutter doesn't cross-compile desktop apps: Windows builds need Windows.
- Locally: Windows 11 on Arm, where Flutter builds only `windows-arm64` (checked 2026-11-06); x64 from CI or an x64 PC.
- CI: GitHub Actions `windows-latest`, plus the existing macOS and Android builds.

**Distribution (decide by the end of milestone 2):**
- **Windows:** MSIX or an installer (e.g. Inno Setup). Sign it, or SmartScreen warns on every download (code-signing certificate or Azure Trusted Signing). Auto-update per 1a.9.

**Exit criteria for milestone 2** (same bar as the macOS spike):
- Register and make two-way calls on **fonial and Vodafone** on **Windows** (x64).
- An incoming call rings while the window is closed to the tray.
- Input and output device selection; no echo on laptop speakers.
- Saved accounts and passwords survive a restart.
- Sleep handling per 1a.14: accounts unregister before sleep and re-register by themselves after wake.

**Linux (parked 2026-11-07),** kept for a later return. Until then it was planned next to Windows in milestone 2:
- **Native core:** `linux-x64` and `linux-arm64` targets in `build.sh` (OpenSSL `linux-x86_64` / `linux-aarch64`) and an `OS.linux` case in `hook/build.dart`; the script already runs on any Unix with bash, CMake and Ninja. A Meson cross file per target for webrtc-audio-processing (macOS writes one already).
- **Audio:** `pulse`, which also works on PipeWire systems through pipewire-pulse; baresip's native `pipewire` module is an option later. It doesn't cancel echo, so `aec.c` as on macOS and Windows.
- **DNS:** libre reads `/etc/resolv.conf`. Verify that fonial's oversized SRV answer still falls back to TCP through systemd-resolved's stub (`127.0.0.53`).
- **Runner:** `flutter create --platforms=linux .`; incoming-call notification through `org.freedesktop.Notifications` actions.
- **Tray caveat:** GNOME shows no tray icons without the AppIndicator extension (Ubuntu ships it, Fedora doesn't). Without a tray, closing the window must not quit while accounts are enabled; incoming calls then rely on the notification.
- **Password storage:** `flutter_secure_storage` uses libsecret, which needs a Secret Service (GNOME Keyring, KWallet) running. Show a clear error when there's none.
- **Microphone:** no permission, except inside Flatpak.
- **Builds:** need Linux: an arm64 VM on the Mac, CI `ubuntu-latest` and `ubuntu-24.04-arm`.
- **Distribution:** Flatpak (Flathub) first; AppImage or `.deb` optional. The Flatpak needs network access, `--socket=pulseaudio`, the Secret Service (`--talk-name=org.freedesktop.secrets`) and notifications.
- **Sleep:** a logind delay inhibitor (1a.14).

### 1a.14 Staying awake to receive calls (added 2026-11-04)

"Runs in the tray" (1a.4) only holds while the device is awake. **A sleeping computer can't receive calls on any platform**, and the provider has no way to wake it.

**What goes wrong when the device sleeps:**
1. **The provider keeps ringing a dead contact.** The registration stays valid until it expires (Vodafone: at least 900 s). The caller hears ringing for nothing, and the provider's "when unreachable" forwarding doesn't fire. It's the same problem as on iOS (1a.10).
2. **Timers stop.** libre's registration refreshes and keep-alives don't run while the CPU sleeps, which is why `SipService.kt` holds a wake lock on Android. After wake the registration may have lapsed, and the router's NAT bindings have expired.
3. **Connections are dead after wake.** TCP and TLS connections don't survive sleep, and the IP address may have changed. Vodafone sends incoming calls over the client's own TLS connection (1a.1), so nothing arrives until the app reconnects and registers again.
4. **Nothing wakes the computer for a call.** Wake-on-LAN, Wake on Wireless and macOS's "Wake for network access" react only to special packets or services, never to a SIP INVITE.

**What the app should do on every platform:**
- **Before sleep:** unregister every account (`Expires: 0`) in the short time the OS allows: about 2 s on Windows, and up to `InhibitDelayMaxSec` (5 s by default) on Linux with a logind delay inhibitor. Skip it during an active call. Vodafone caveat: unregistering leaves a line shared with a router unregistered until the router registers again (1a.10, step 4).
- **After wake:** reconnect and register at once instead of waiting for timers, and treat it as a network change (phase 2 in section 11).
- **Provider-side fallback:** suggest forwarding "when not registered" to the user's mobile number, as for iOS (1a.10, step 3). The unregister before sleep makes it fire right away.
- **Opt-in "Keep the computer awake to receive calls":**
  - It only blocks *idle* sleep. The screen can still turn off and lock.
  - It can't stop the user, or a closed lid, from putting the machine to sleep.
  - Turn it on only on the power adapter by default, because it keeps a laptop running all night.
- **Say it in the UI:** "Sippier can't ring while the computer sleeps."

**Per platform:**

| Platform | What sleeps and when | Keeping it awake | Sleep and wake signals |
|---|---|---|---|
| **macOS** | Laptops sleep when idle and when the lid closes (except in clamshell mode: external display and power). **App Nap** throttles the timers of an app with no visible window, which is Sippier sitting in the menu bar, so refreshes and keep-alives run late. | `ProcessInfo.beginActivity` with `.idleSystemSleepDisabled` blocks idle sleep, like `caffeinate -i`. `.userInitiatedAllowingIdleSystemSleep` only keeps the app out of App Nap; use it whenever an account is enabled. | `NSWorkspace.willSleepNotification` and `didWakeNotification` |
| **Windows** | Most current laptops use **Modern Standby**: when the screen turns off, the Desktop Activity Moderator pauses desktop apps, so Sippier can't answer anything. Older machines sleep fully (S3). | `PowerSetRequest(PowerRequestSystemRequired)` or `SetThreadExecutionState(ES_SYSTEM_REQUIRED)` blocks idle sleep; `powercfg /requests` lists it. On Modern Standby on battery, Windows ends such requests 5 minutes after the sleep timeout. Whether they keep the app running once the screen is off needs testing. | `WM_POWERBROADCAST` (`PBT_APMSUSPEND`, `PBT_APMRESUMEAUTOMATIC`) or `PowerRegisterSuspendResumeNotification`. On Modern Standby, also watch the display-state notifications. |
| **Linux** | GNOME suspends idle machines **on AC power too**: after 20 min upstream since GNOME 3.28, after 15 min on Fedora 38+. Closing the lid suspends regardless of inhibitors (logind's default `LidSwitchIgnoreInhibited=yes`). | The XDG portal `org.freedesktop.portal.Inhibit` with the suspend flag, which also works inside Flatpak; outside Flatpak a logind `sleep` inhibitor works too. Check that GNOME and KDE honour it. | logind's `PrepareForSleep(true/false)` signal, with a delay inhibitor to get time for the unregister |
| **Android** | No App Nap, but: **Doze** (screen off and still: no network, wake locks ignored), **App Standby buckets** (rarely used apps get less background time), the **freezer for cached apps**, the user's **"Restricted"** battery setting, and **OEM battery savers**. | Milestone 1's foreground service (`specialUse` while idle) with a partial wake lock (`SipService.kt`) covers the first three: stock Android leaves foreground-service apps their wake locks and network in Doze, counts them as active for the standby buckets, and doesn't freeze them because they aren't cached. It can't beat "Restricted" (detect it and warn) or OEM battery savers (Samsung, Xiaomi, Huawei…), where users may have to set battery usage to "Unrestricted" (dontkillmyapp.com lists the steps per vendor). | Not needed while the service runs |

**A call handler doesn't make Android reachable.**
- Core-Telecom (`CallsManager.addCall`) takes over only once the INVITE has arrived. It doesn't keep the app alive or online while it waits.
- What it improves is the call itself: the system's call surfaces (Bluetooth, car, watch), correct behaviour when a mobile call comes in during a SIP call, audio routing, and the `phoneCall` service type during calls. Today the app uses `microphone` during calls, which Android doesn't allow to start from the background.
- Only push (FCM, which needs a server; parked) would replace the always-on service.

**Status (2026-11-04):**
- **Android:** handled in milestone 1 (foreground service + wake lock); measure the battery cost. Google Play asks for a justification of the `specialUse` service type.
  - **"Restricted" warning (2026-11-04):** when `ActivityManager.isBackgroundRestricted` is set, a banner says Sippier can't receive calls in the background. "Change" opens the app's info page, where "App battery usage" is; Android has no intent for that page itself. The check runs at start and whenever the app comes back to the front, like the lock-screen banner.
  - Tested on the Pixel (Android 17) by setting the `RUN_ANY_IN_BACKGROUND` app op to `ignore` and back: the banner appears, "Change" opens app info, and the banner goes away after restoring.
  - **Battery cost, measured (2026-11-04, `dumpsys batterystats`):**
    - Over 3 h 39 min on battery, the wake lock `sippier:registration` was held for 3 h 33 min (97%), so the CPU never suspends while Sippier runs.
    - Sippier used about 8 min of CPU time, and app info shows it at **44% of battery use since the last full charge**.
    - The permanent partial wake lock in `SipService.kt` is the main cost.
    - Better: let the CPU sleep and wake the core with exact alarms (`setExactAndAllowWhileIdle`) shortly before registration refreshes and NAT keep-alives are due. Incoming packets wake the device through the Wi-Fi or modem driver.
  - **Battery saver (experiment, 2026-11-05):** "Keep the phone awake" under Settings → Calls in the background on Android, on by default.
    - It's **one setting, not one per account**: the wake lock belongs to the whole app, so a per-account switch (tried first) would do nothing as long as any other account kept it on. The per-provider cost shows as a hint below the switch, e.g. "every 2 min for fonial, every 7½ min for Vodafone", from the registration time each provider granted (`sc_account_expires`).
    - On, or while a call rings or runs, the app holds the wake lock. Otherwise `SipService` releases it and sets an alarm (exact if battery usage is "Unrestricted" or the user allows "Alarms & reminders", otherwise inexact "while idle").
    - On the alarm it holds a 10 s wake lock and calls `sc_keepalive()`. That re-registers accounts past half of the expiry their provider granted (read through `ua_state_json_api`) and returns when the next alarm is due.
    - The core measures time with `CLOCK_BOOTTIME`, because libre's timers (`CLOCK_MONOTONIC_RAW`) stop while the CPU sleeps.
    - Granted expiry sets the refresh rate: fonial gives 60–240 s on UDP (120 s in the 2026-11-06 test), Vodafone 900 s (a refresh every 7½ min). Android 12+ allows about 72 "while idle" alarms per hour to apps that aren't Unrestricted.
    - UDP accounts also need a NAT keep-alive, so the phone wakes at least every 60 s (see the overnight test below). In the 2026-11-06 test it actually woke every 30 s: after each refresh `sc_keepalive` schedules the next call 30 s later to check the answer, instead of half the granted time.
    - Answered by the tests: the router doesn't keep the UDP path open between wake-ups without keep-alives. INVITEs that arrive while the CPU sleeps do wake it and ring; a Vodafone call came in 5½ min after the last REGISTER in battery-saver mode.
    - **Test (Pixel 6, Android 17, 2026-11-05): the battery saver only works with battery usage set to "Unrestricted".** Under "Optimized" (the default) registrations ran out. Keeping the phone awake works under both.
      - This is stock Android (AOSP AlarmManager), not Pixel-specific. "Unrestricted" puts the app on the power allowlist (`dumpsys deviceidle whitelist`), and that changes two things. Exact alarms are allowed without "Alarms & reminders" (`dumpsys alarm` shows `exactAllowReason=allow-listed window=0`). While-idle alarms also have no quota.
      - Under "Optimized" the alarm is inexact (it can come 75% of the delay late), and while the phone dozes Android allows 72 per hour (`allow_while_idle_quota=72` per `allow_while_idle_window=1h`). fonial's short grants need 120 per hour.
      - OEM battery savers (Samsung, Xiaomi…) add their own restrictions on top, see dontkillmyapp.com.
      - The app now checks `PowerManager.isIgnoringBatteryOptimizations`. When the battery saver is on and the app is still Optimized, a banner explains the problem and offers "Allow" or "Keep awake instead". "Allow" opens the system dialog (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, permission `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`). Google Play only allows that permission for apps whose core function breaks under Doze; a calling app that can't use FCM push qualifies, so declare it in the Play Console (milestone 2 moves to push anyway).
    - **Overnight test (Pixel 6, 2026-11-05/06, SIP trace in logcat): Vodafone lost its registration in battery-saver mode; with the wake lock it stayed registered, but calls stopped coming in after a while. fonial kept working.**
      - **Refresh bug:** `sc_keepalive` re-registered with `ua_register()`. baresip's `reg_register()` then makes a new sipreg (new Call-ID) and destroys the old one, which unregisters the old binding (`expires=0`) at the same time.
        - Vodafone (IMS) confirmed the de-REGISTER and answered the new REGISTER's authenticated retry with `401 stale=true`. libre gives up after two 401s in a row, so the one-strike rule stopped the account until it was saved again the next morning.
        - fonial answered `482 Request merged` 45 times overnight and handed out varying expiries (60–180 s instead of 240 s).
        - Fix: `baresip-0003-refresh-keepalive.patch` adds `ua_refresh_register()`, which sends `sipreg_send()` on the existing registration (same Call-ID, next CSeq). `sc_keepalive` uses it and waits for the answer before sending another (at most 5 min).
      - **NAT path:** fonial sends OPTIONS every 30 s, and answering them keeps the router's UDP mapping toward fonial alive. Vodafone sends nothing, and the wake-lock mode refreshes only every 13½ min (libre: 90% of 900 s).
        - A Vodafone call that came in 2:51 min after a REGISTER rang. Linux-based routers (the AVM FRITZ!Box here) keep a mapping with replies for 120–180 s.
        - Fix: `ua_keepalive()` sends an empty line (CRLF CRLF) to each registrar registered over UDP, as pjsip and Linphone do. RFC 5626's STUN keep-alive needs registrar support, which plain registrars lack. The core sends it every 25 s while awake, and in battery-saver mode `sc_keepalive` sends it and wakes the phone at least every 60 s.
        - The SIP trace skips these packets.
      - IPv6 on that Wi-Fi (the FRITZ!Box guest network, `192.168.179.0/24`) has addresses but no default route. Every REGISTER first fails over IPv6 at once ("Network is unreachable") and libre falls back to IPv4. Harmless.
      - **Retest with both fixes (2026-11-06, 11:35–14:30, mostly battery-saver mode): works.**
        - All Vodafone refreshes kept one Call-ID and got 200 OK. When Vodafone's nonce expired (`401 stale=true`, three times), libre authenticated once more and got 200 OK.
        - fonial sent no 482 and granted a steady 120 s.
        - A Vodafone call at 14:28 rang 5 min 23 s after the last REGISTER, longer than the router keeps an idle UDP path. fonial calls rang too.
        - The log line "NAT keep-alive every 25 s to 2 registrars" confirms that keep-alives go to both providers.
  - Open for milestone 1: Core-Telecom (not used yet; the app shows its own CallStyle notification).
- **macOS:** done in milestone 1 (2026-11-04; real sleep test pending):
  - **App Nap off** while any account is enabled or a call runs: the runner holds `beginActivity(.userInitiatedAllowingIdleSystemSleep)`, so idle sleep stays allowed.
  - **Before sleep** (`power.c`, IOKit's `IORegisterForSystemPower` on a dispatch queue): the core ends calls cleanly and unregisters every account the app enabled. It holds sleep back until the unregisters are confirmed, at most 3 s, then calls `IOAllowPowerChange`.
  - **After wake:** the core registers those accounts again at once, then retries every 3 s for 30 s while the network comes back. libre's own retry after a failure would wait 30 s or more.
  - Accounts the one-strike rule stopped after an auth failure stay off after wake, so a wrong password can't trip Vodafone's IP block.
  - Not done: the opt-in "keep the computer awake".
  - **First test (2026-11-04):** IOKit's notifications work inside the App Sandbox.
    - Twice, both accounts unregistered and were confirmed in under a second before sleep, and registered again within a second of wake.
    - The Mac never really slept: the power log shows the display off for only 4 s each time, with no "Entering Sleep state", most likely woken by Bluetooth input.
    - **Vodafone's second de-REGISTER got `481 … 219 Wrong Contact in de-REGISTER`**, 17 s after the re-REGISTER at wake, so that binding stayed until it expired.
    - Suspected cause: macOS changed the IPv6 address after wake, so the Contact no longer matched. SIP trace was off; repeat with it on.
  - **Repeat test (2026-11-04, real sleeps of 4½ min and 40 s, SIP trace on):**
    - Both unregisters were confirmed before each sleep, with no 481.
    - After wake the network was missing for about 6 s ("No route to host"). The 3 s retries registered fonial 7 s after wake.
    - **Bug, fixed:** a retry started a new REGISTER for Vodafone while the previous one was still waiting for an answer, and Vodafone answered `491 REGISTER request pending - 110 Parallel registrations`. Retries now only restart registrations that failed.
    - The trace confirms that **the Contact changes across sleep**: IPv6 address and port went from `…78a2…]:62909` to `…a361]:51947`, and the second wake registered Vodafone over IPv4 because IPv6 wasn't ready yet. That explains the earlier 481 if the address changes between the REGISTER at wake and the next de-REGISTER.
    - Possible fix, not done: patch libre's `sipreg` so a de-REGISTER uses the Contact of the last successful REGISTER. That needs patch support for libre in `build.sh`.
- **Windows:** `power.c` since 2026-11-06 (1a.13); not tested with a real sleep yet.
- **Linux:** parked (1a.13).

### 1a.15 Contacts integration (added 2026-11-04)

**Short answer:** possible on Android and macOS, which have a system address book. Windows and Linux have nothing comparable. Contacts aren't required anywhere, including Android with a call handler.

| Platform | System address book | Access | Notes |
|---|---|---|---|
| **Android** | Yes: `ContactsContract`, synced from Google, Exchange and others | `READ_CONTACTS` runtime permission; number lookup through `PhoneLookup` | Picking a contact with the system picker (`ACTION_PICK`) needs no permission |
| **macOS** | Yes: Contacts (iCloud, Google, Exchange) | Contacts framework (`CNContactStore`), `NSContactsUsageDescription`, and the sandbox entitlement `com.apple.security.personal-information.addressbook` | — |
| **Windows** | Practically none | The WinRT `ContactStore` API still exists, but the People app that filled it ended support on 2024-12-31 and is gone from Windows 11 24H2; My People is unsupported on Windows 11 | Contacts now live in Outlook / Microsoft 365, reachable only through the cloud Graph API with sign-in |
| **Linux** | Depends on the desktop | GNOME: Evolution Data Server; KDE: Akonadi. Both are separate D-Bus services, and there's no Flatpak portal for contacts | — |
| iOS (parked) | Yes | Contacts framework | CallKit matches a phone-number handle to contacts by itself and can add calls to the Phone app's recents |

**Flutter:** `flutter_contacts` covers Android, iOS and macOS, not Windows or Linux.

**Android with a call handler:**
- **Not required.** Core-Telecom (`CallsManager.addCall`) shows the display name and number the app passes in. The docs don't say that Telecom looks up contacts for apps like ours, so assume it doesn't: we look up the name and pass it.
- **What contacts add:**
  - The caller's name in the notification, and through Telecom on Bluetooth, car and watch displays.
  - **Do Not Disturb exceptions:** give the CallStyle notification's `Person` a `tel:` URI. Android then matches it to a contact, so starred contacts can ring through Do Not Disturb. This needs no contacts permission.
  - Names in recents, and a contact picker in the dialer.
- **System call log** (separate from contacts, optional): by default Android doesn't put calls from self-managed calling apps into the Phone app's history. The `PhoneAccount` extra `EXTRA_LOG_SELF_MANAGED_CALLS` (API 30+) opts in. From Android 17 (API 37), Core-Telecom apps can write to `CallLog.Calls` directly. Sippier keeps its own history anyway.
- **Calling *from* the Contacts or Phone app into Sippier** is a bigger feature:
  - a "Call with Sippier" row on each contact, as WhatsApp adds, which needs our own contacts account and sync adapter
  - or a calling account the user turns on in the Phone app's settings (a managed, not self-managed, `PhoneAccount`); the system dialer then shows the call
  - Cheap middle ground: handle `tel:` and `sip:` links (Android intent filters; desktop handlers in 1a.5).

**Number matching:** convert stored numbers and caller IDs to E.164 with the account's country (1a.12) before comparing. Fall back to comparing the last digits for numbers that can't be converted.

**Privacy:** contacts stay on the device; nothing is uploaded. Declare contacts access in Google Play's Data safety form and explain it in the macOS permission text.

**Recommendation (not decided yet):**
- **Android and macOS:** caller names and contact search from the system address book (phase 2, section 11), with the `tel:` URI on Android's call notification.
- **Windows:** no contacts at first; names come from our own call history. Later, if people ask for it: vCard import into an in-app list, then CardDAV sync (works with iCloud, Google, Nextcloud and Fastmail, not Microsoft 365).
- **Leave out unless wanted:** "Call with Sippier" rows in the Android contacts app, and a managed calling account.

### 1a.16 Audio devices and ringtones (added 2026-11-04)

**What the user gets (desktop):**
- Settings → Audio: **Microphone**, **Speaker** and **Ringing on**, each "System default" or a specific device.
- A default **ringtone** with a preview button.
- Each account can pick its own ringtone in the account form ("Default" unless changed). Changing only the ringtone doesn't register the account again.

**How it works:**
- **Device list** (`sc_audio_devices`): the core asks the system each time, so the list is always current: CoreAudio on macOS (device UID as id), the MMDevice API on Windows (endpoint id as id, since 2026-11-06). Android routes audio itself and lists none.
- **Choosing** (`sc_set_audio_devices`) changes the config and switches running calls at once (`audio_set_source` / `audio_set_player`). Call audio still goes through `aec`, as `aec,<module>:<device>`.
- **"System default" follows changes:** CoreAudio's default-device listener posts to the core's message queue. The re thread then reopens the call's source or player on the new default, e.g. when AirPods connect. The listener never waits for the re thread.
- **baresip patch** `native/patches/baresip-0002-audiounit-device.patch`: `audiounit` ignored the device setting and always took the default. It now opens the device with the given CoreAudio UID and falls back to the default when that device is gone. **Upstream candidate.**
- **Ringing is in the core on desktop:** baresip's tone player loops the ringtone on the ringing device.
  - **Built-in ringtones** are original short melodies in the style of friendly app ringtones (Skype was the reference for the feel, not the melody). `ringtone.c` synthesizes them with mallet (marimba-like), bubble (pitch sliding up into the note) and FM glass-bell voices, panned in stereo, with a ping-pong echo and a gentle low-pass, at 48 kHz. There are no sound files to licence.
  - The tones are **Bubbles** (default), **Marimba**, **Glass** and **Classic** (the old double ring as a mallet trill). The core lists the default first, and "no ringtone chosen" means that one.
  - **Your own sound:** "Choose a file…" copies the file into `<app support>/ringtones/`, so the macOS sandbox still lets the core read it later; it needs the `files.user-selected.read-only` entitlement only for the open dialog. The core plays it as `file:<path>`, followed by 1 s of silence, using at most 60 s. macOS reads anything CoreAudio reads (M4A, MP3, WAV, AIFF, CAF) through ExtAudioFile; elsewhere the core reads WAV via libre's `aufile`. A file it can't read falls back to the default.
  - The macOS system sounds (Submarine, …) were tried as the default and dropped: they weren't liked.
  - The macOS runner only brings the window forward and bounces the Dock icon.
  - Windows needs no native ringing code; its runner shows the window and flashes the taskbar button.
- **Key tones** play on the call speaker, straight to the audio module. Through `aec` they would add a second stream to the echo reference.

**Android:**
- The system routes audio. Earpiece, speaker, Bluetooth and wired headset switching comes with Core-Telecom (milestone 1, item 4).
- Ringing uses the incoming-call notification channel's sound. Settings → Audio → Ringtone opens that channel's system settings.
- Per-account ringtones on Android would need one notification channel per account: later, if wanted.

---

## 2. Architecture overview

```
┌────────────────────────── Flutter app ──────────────────────────┐
│  UI (dialer, in-call screen, history, settings)                 │
│  State (accounts, registration state, active calls)             │
│  SIP engine:  sip_ua (Dart)   OR   native SDK via channels/FFI  │
│  OS call integration: CallKit+PushKit (iOS), Core-Telecom (And.)│
└──────────────┬──────────────────────────────┬───────────────────┘
               │ SIP signalling               │ Media
               │ (WSS / TLS / TCP / UDP)      │ RTP/SRTP or DTLS-SRTP+ICE
               ▼                              ▼
     Registrar / proxy / PBX  ◄──────►  Media server / RTP relay
     (Asterisk, FreeSWITCH,             (PBX itself, rtpengine,
      Kamailio, OpenSIPS, 3CX,           TURN server)
      SIP provider)
               │
               ▼  (incoming call while app is asleep)
     Push gateway ──► APNs (VoIP push) / FCM (high-priority data msg)
     (OpenSIPS RFC 8599, Flexisip, or custom service)
```

---

## 3. SIP signalling essentials

### 3.1 Transports and ports

| Transport | Default port | Notes for mobile |
|---|---|---|
| UDP | 5060 | Classic default. Problems: fragmentation of large messages (RFC 3261 says to switch to TCP if a request is within 200 bytes of the path MTU, i.e. larger than about 1300 bytes), short carrier NAT timeouts, router "SIP ALG" mangling, and some carriers block 5060. |
| TCP | 5060 | No fragmentation issues. Needs keep-alives. |
| TLS | 5061 | **Preferred on mobile.** It encrypts signalling and gets past SIP ALGs and port blocking. |
| WebSocket WS/WSS (RFC 7118) | Varies, often 443 or 8089 (Asterisk) and 7443 (FreeSWITCH) | Used by browser and WebRTC clients and by `sip_ua`. Over WSS, media is always DTLS-SRTP. |

RTP media uses a UDP port range, for example 10000–20000 on Asterisk and 16384–32768 on FreeSWITCH.

### 3.2 Methods you'll actually use

| Method | Purpose | RFC |
|---|---|---|
| REGISTER | Bind your contact address to your SIP URI (log in). Re-register before `Expires`; unregister with `Expires: 0`. | 3261 |
| INVITE / ACK / BYE / CANCEL | Set up, confirm, end, and abort a call. A re-INVITE changes an established call (hold, codec change, new IP). | 3261 |
| OPTIONS | Capability query; often used as a keep-alive or "ping". | 3261 |
| PRACK | Reliable provisional responses (`100rel`), used with early media. | 3262 |
| UPDATE | Change session parameters before the call is answered; session refresh. | 3311 |
| INFO | Mid-call info; used by some systems for DTMF (`application/dtmf-relay`). | 6086 |
| REFER (+ NOTIFY) | Call transfer. Blind transfer uses `Refer-To`; attended transfer adds `Replaces` (RFC 3891). | 3515 |
| SUBSCRIBE / NOTIFY | Events: voicemail MWI (`message-summary`, RFC 3842), BLF (`dialog`, RFC 4235), presence (RFC 3856). | 6665 |
| MESSAGE | Pager-mode instant messages. | 3428 |

### 3.3 Responses to handle in the UI

`100 Trying` · `180 Ringing` · `183 Session Progress` (early media, e.g. a carrier announcement) · `200 OK` · `401/407` (auth challenge, answer it with credentials) · `403 Forbidden` · `404 Not Found` · `408 Request Timeout` · `480 Temporarily Unavailable` · `486 Busy Here` · `487 Request Terminated` (after CANCEL) · `488 Not Acceptable Here` (**no common codec, or SRTP/DTLS mismatch**) · `503 Service Unavailable` · `603 Decline`.

### 3.4 Key concepts

- **Headers:** `Via` (with `branch=z9hG4bK…` and `rport`), `From`/`To` (with tags), `Call-ID`, `CSeq`, `Contact`, `Route`/`Record-Route`, `Max-Forwards`, `Expires`, `Allow`, `Supported`, `User-Agent`.
- **Dialog** = Call-ID + local tag + remote tag.
- **Transactions** have retransmission timers. T1 = 500 ms; INVITE timeout (Timer B) = 64×T1 = 32 s.
- **Authentication:** HTTP Digest. MD5 (RFC 2617) is still most common; SHA-256 is defined in RFC 8760. Support `qop=auth`.
- **Hold:** send a re-INVITE with `a=sendonly`, and the peer answers `recvonly`. Resume with `a=sendrecv`. Accept the legacy `c=0.0.0.0` hold, but don't send it.
- **Session timers (RFC 4028):** `Session-Expires`/`Min-SE`, refreshed by re-INVITE or UPDATE. Mismatches cause calls to drop at fixed intervals (15 or 30 min).
- **SIP Outbound (RFC 5626):** `reg-id`, `+sip.instance` and CRLF keep-alives. A robust way to keep NAT bindings and recover after the network changes.
- **Caller ID:** `P-Asserted-Identity` (RFC 3325). In the US, STIR/SHAKEN (`Identity` header, RFC 8224) is handled by carriers.

### 3.5 Basic call flow

```
App (Alice)              PBX / Proxy                Bob
   | INVITE (SDP offer)      |                        |
   |------------------------>| INVITE                 |
   |  100 Trying             |----------------------->|
   |<------------------------|  180 Ringing           |
   |  180 Ringing            |<-----------------------|
   |<------------------------|  200 OK (SDP answer)   |
   |  200 OK (SDP answer)    |<-----------------------|
   |<------------------------|                        |
   | ACK                     | ACK                    |
   |------------------------>|----------------------->|
   |<=========== RTP audio (both directions) ========>|
   | BYE                     | BYE                    |
   |------------------------>|----------------------->|
   |  200 OK                 |  200 OK                |
   |<------------------------|<-----------------------|
```

The PBX may challenge the INVITE with `401`/`407`. The app then resends it with an `Authorization`/`Proxy-Authorization` header.

---

## 4. SDP and offer/answer

Example audio offer (plain RTP, typical for a native SIP stack):

```
v=0
o=- 4858 4858 IN IP4 192.0.2.10
s=-
c=IN IP4 192.0.2.10
t=0 0
m=audio 40000 RTP/AVP 111 9 8 0 101
a=rtpmap:111 opus/48000/2
a=fmtp:111 minptime=10;useinbandfec=1
a=rtpmap:9 G722/8000
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-16
a=ptime:20
a=sendrecv
```

- The payload type order in the `m=` line is your **preference order**. The answerer picks from it.
- **Profile variants:**
  - `RTP/AVP` is plain RTP.
  - `RTP/SAVP` + `a=crypto:` is SRTP with SDES keys (RFC 4568). Only safe over TLS.
  - `UDP/TLS/RTP/SAVPF` + `a=fingerprint`, `a=setup`, `a=ice-ufrag/pwd`, `a=candidate` and `a=rtcp-mux` is WebRTC: DTLS-SRTP (RFC 5763/5764) + ICE.
- If the profiles don't match (SRTP offered, RTP expected, or the other way round), the result is `488` or a call with no audio.

---

## 5. Media: RTP, RTCP and audio processing

- **RTP header:** 12 bytes. Fields: payload type, sequence number, timestamp, SSRC, marker bit.
- **Packetisation (ptime):** 20 ms is the de facto default, giving 50 packets/s. A larger ptime saves bandwidth but adds latency.
- **RTCP:** sender and receiver reports (packet loss, jitter, RTT). RTCP-XR (RFC 3611) adds VoIP quality metrics. Use these for an in-call quality indicator. RTCP runs on the RTP port + 1 unless `rtcp-mux` is used (RFC 5761; mandatory in WebRTC).
- **Jitter buffer:** an adaptive buffer that smooths arrival-time variation. It trades latency against loss.
- **PLC:** packet-loss concealment. Opus has strong built-in PLC plus in-band FEC.
- **VAD/DTX/CNG:** silence suppression. Comfort Noise uses PT 13 (RFC 3389); Opus has its own DTX.
- **Echo cancellation (AEC), noise suppression and AGC are essential on phones**, especially on speakerphone:
  - **Android:** use the `VOICE_COMMUNICATION` audio source and `MODE_IN_COMMUNICATION`.
  - **iOS:** use the VoiceProcessingIO audio unit and the `AVAudioSession` `.voiceChat` mode.
  - **macOS and Windows:** baresip's desktop audio modules don't cancel echo, so Sippier runs WebRTC audio processing on what the device plays and records (`aec.c`; 1a.13). VoiceProcessingIO on macOS was the alternative, and the only way to get Apple's Mic Modes.
  - **WebRTC** (and therefore `flutter_webrtc`) ships its own audio-processing module.
- **Audio routes:** earpiece, speaker, Bluetooth HFP and wired headset. Turn the screen off with the proximity sensor during earpiece calls.
- **Quality targets:** one-way delay under 150 ms (ITU-T G.114), jitter under 30 ms, packet loss under 1%. MOS (1–5) and R-factor (E-model, G.107) are the usual scores.

---

## 6. Audio codecs

### 6.1 Comparison

| Codec | SDP name / PT | Audio band | Bitrate (payload) | IP bandwidth @20 ms* | Licence | Where it's used |
|---|---|---|---|---|---|---|
| **G.711 A-law** | `PCMA/8000`, PT 8 | Narrowband 8 kHz | 64 kbps | ~80 kbps | Free | Universal baseline. A-law in Europe and most of the world. |
| **G.711 µ-law** | `PCMU/8000`, PT 0 | Narrowband 8 kHz | 64 kbps | ~80 kbps | Free | Universal baseline. µ-law in North America and Japan. |
| **G.722** | `G722/8000`**, PT 9 | Wideband 16 kHz | 64 kbps | ~80 kbps | Free (patents expired) | HD voice on desk phones and PBXs. Very common. |
| **Opus** | `opus/48000/2`, dynamic PT (often 111) | NB → fullband, adaptive | 6–510 kbps (voice: ~12–32) | ~28–48 kbps for typical voice | Free (BSD, royalty-free) | WebRTC (mandatory to implement), apps, modern PBXs. Not on every trunk. |
| **G.729** (Annex A/B) | `G729/8000`, PT 18 | Narrowband | 8 kbps | ~24 kbps | Free since its patents expired (~2017) | Legacy low-bandwidth trunks. Worse quality and more CPU. |
| iLBC | `iLBC/8000`, dynamic | Narrowband | 13.33 / 15.2 kbps | ~24–31 kbps | Free | Legacy. Robust to loss. Being phased out. |
| GSM 06.10 | `GSM/8000`, PT 3 | Narrowband | 13 kbps | ~29 kbps | Free | Legacy. |
| Speex | dynamic | NB/WB | 2–44 kbps | n/a | Free | **Obsolete**, superseded by Opus. |
| AMR-NB / AMR-WB (G.722.2), EVS | dynamic | NB / WB / SWB | various | n/a | **Patent-licensed** | Mobile networks (VoLTE). Avoid in an app. |
| telephone-event | `telephone-event/8000`, dynamic (often 101) | n/a | tiny | n/a | Free | DTMF as RTP events (RFC 4733). |
| CN | `CN/8000`, PT 13 | n/a | tiny | n/a | Free | Comfort noise (RFC 3389). |

\* Approximate bandwidth per direction including IP/UDP/RTP headers (40 bytes per packet = 16 kbps at 50 pps). On Ethernet add about 7.2 kbps (giving the familiar 87.2 kbps for G.711 and 31.2 kbps for G.729). SRTP adds about 4 kbps (10-byte auth tag). Many vendor blogs quote different figures because they include different overheads.

\** **G.722 quirk:** SDP and RTP timestamps say 8000 Hz even though it samples at 16 kHz. This is a historical error in RFC 1890 that RFC 3551 kept.

### 6.2 Opus details (RFC 6716, RTP: RFC 7587)

- The SDP always says `opus/48000/2`, whatever the real bandwidth or channel count.
- Useful `fmtp` parameters: `useinbandfec=1`, `usedtx=1`, `maxaveragebitrate=`, `maxplaybackrate=`, `stereo=0`, `minptime=10`.
- Frame sizes range from 2.5 to 60 ms.
- **DTMF clock rate:** `telephone-event` must use the same clock rate as the audio codec. So you need `telephone-event/48000` alongside Opus and `telephone-event/8000` alongside G.711/G.722. WebRTC offers both.

### 6.3 Recommended codec preference for the app

1. **Opus** (best quality, adapts to bad mobile networks)
2. **G.722** (HD voice with PBXs and desk phones)
3. **PCMA** then **PCMU** (put PCMA first in Europe; swap for North America)
4. + **telephone-event** (DTMF), optionally CN

**For German providers (fonial, Vodafone), use G.722, PCMA, PCMU and telephone-event by default.** Neither lists Opus. Vodafone's SBC transcodes between G.722, AMR-WB, AMR and G.711 A-law.

Offer G.729 only if a specific trunk needs it. Avoid transcoding where you can: every transcode at the PBX adds latency, CPU load and quality loss.

---

## 7. Security

| Layer | Option | Notes |
|---|---|---|
| Signalling | **TLS** (`sips:`/`transport=tls`, port 5061) or WSS | Protects credentials metadata and SDES keys. Verify the server certificate. |
| Media | **SRTP** (RFC 3711) | AES-CM-128 + HMAC-SHA1-80 is the most common suite. |
| SRTP keying | **SDES** (`a=crypto`, RFC 4568) | Keys travel inside SDP, so it's only secure over TLS. Widely supported by PBXs and providers. |
| | **DTLS-SRTP** (RFC 5763/5764) | Keys come from a DTLS handshake. Mandatory in WebRTC, so `sip_ua` requires it. |
| | ZRTP (RFC 6189) | End-to-end with short authentication strings. Niche; supported by Linphone. |
| Auth | Digest MD5 / SHA-256 | Store credentials in the Keychain or Keystore (`flutter_secure_storage`). |

---

## 8. NAT traversal (the #1 cause of "no audio" / "one-way audio")

- **The problem:** phones sit behind NAT and mobile carrier CGNAT. SDP advertises the device's private IP and port, so the far end sends RTP into the void.
- **Signalling fixes:**
  - `rport` (RFC 3581): the server replies to the source IP and port the request came from.
  - Keep-alives every 15–30 s on UDP: CRLF, OPTIONS, or SIP Outbound (RFC 5626).
  - Prefer TCP/TLS on mobile.
- **Media fixes:**
  - **Symmetric RTP** (RFC 4961): send and receive on the same port.
  - **STUN** (RFC 8489): learn your public address.
  - **TURN** (RFC 8656): relay when nothing else works.
  - **ICE** (RFC 8445): try candidates and pick the best path. Mandatory in WebRTC.
  - Server-side **media relay/anchoring:** PBX `direct_media=no`, rtpengine, `nat=force_rport,comedia` style settings.
- **Router SIP ALG:** often breaks SIP. Recommend users disable it; TLS sidesteps it.
- **Network changes (Wi-Fi ↔ LTE):** the IP changes, so you must re-REGISTER and re-INVITE the active call (or do an ICE restart) to move the media. Plan for this from the start.

---

## 9. Mobile platform constraints

### 9.1 iOS

_Parked on 2026-11-04 (1a.13); kept as reference._

- **Incoming calls in the background need PushKit VoIP pushes.** The old background keep-alive sockets were deprecated in iOS 10.
- **Every VoIP push must be reported to CallKit right away** (`CXProvider.reportNewIncomingCall`) before the push handler returns. Otherwise iOS terminates the app, and repeated failures make the system stop delivering VoIP pushes. This has been enforced since iOS 13.
- **Start audio only after CallKit activates the audio session** (`provider(_:didActivate:)`). Starting earlier is a classic cause of "connected but no audio".
- Background modes: `voip`, `audio`. CallKit doesn't work in the Simulator; test on a device.
- **LiveCommunicationKit** (iOS 17.4+) is a newer alternative to CallKit.
- **China:** apps in the mainland-China App Store must not use CallKit, because of Chinese regulations. Plan a fallback if that market matters.

### 9.2 Android

- **Core-Telecom Jetpack library** (`androidx.core:core-telecom`) is Google's recommended way to integrate VoIP calls:
  - Declare `MANAGE_OWN_CALLS`, then use `CallsManager.addCall(...)` with callbacks for answer, disconnect, set active and set inactive.
  - You get system call UI integration, Bluetooth, Wear and Auto support, and audio routing.
  - Don't call `AudioManager.setCommunicationDevice`/`startBluetoothSco` yourself while using Telecom.
- **Foreground service types** (required since Android 14):
  - `phoneCall` (`FOREGROUND_SERVICE_PHONE_CALL`) needs `MANAGE_OWN_CALLS` or the default dialer role.
  - `microphone` needs `RECORD_AUDIO`, which is a while-in-use permission, so it **can't be started from the background**.
- **Incoming calls in the background:**
  - Send an FCM **high-priority data message**, then show an incoming-call notification with a full-screen intent, or report the call through Telecom.
  - On Android 14+, `USE_FULL_SCREEN_INTENT` is restricted to calling and alarm apps (declared in the Play Console).
- Keeping a persistent SIP connection in the background drains the battery and gets killed by Doze and OEM battery savers. Push is the reliable path.
- The built-in `android.net.sip` API is deprecated. Don't use it.
- Typical permissions: `RECORD_AUDIO`, `POST_NOTIFICATIONS` (13+), `BLUETOOTH_CONNECT` (12+), `MANAGE_OWN_CALLS`, `FOREGROUND_SERVICE_*`, `USE_FULL_SCREEN_INTENT`.

### 9.3 Push architecture

1. The app gets a push token (an APNs VoIP token or an FCM token).
2. The app hands the token to the server, either in the REGISTER Contact parameters (**RFC 8599**: `pn-provider`, `pn-prid`, `pn-param`) or through a custom API.
3. An INVITE arrives for a sleeping device, so the proxy sends a push.
4. The app wakes, reports the call to CallKit/Telecom, connects and re-REGISTERs.
5. The proxy forwards the INVITE.

Server support:
- **OpenSIPS 3.1+** implements RFC 8599.
- **Flexisip** (Belledonne/Linphone) is built for this.
- For Asterisk or Kamailio, plan an extra component (custom script or service). I didn't find native RFC 8599 support for either in this research.

---

## 10. Flutter implementation options

| Option | Signalling | Media | Licence | Platforms | Pros | Cons |
|---|---|---|---|---|---|---|
| **[sip_ua](https://pub.dev/packages/sip_ua)** 1.1.0 + flutter_webrtc ^1.2.0 | Pure Dart (JsSIP port), SIP over **WebSocket and TCP**. No UDP. | WebRTC: **DTLS-SRTP required**, ICE. Codecs: Opus, RED, G.722, iLBC, PCMU, PCMA, CN, telephone-event. | **MIT** | iOS, Android, Web, macOS, Windows, Linux | Free, all Dart, fast start, also runs on web and desktop. Listed working with Asterisk, FreeSWITCH, Kamailio, OpenSIPS and 3CX. | The server must accept WebRTC media, so you **can't call a plain RTP/UDP PBX or trunk without a gateway**. Push, CallKit and Telecom are up to you. Hold/transfer support needs verifying. |
| **[Siprix](https://pub.dev/packages/siprix_voip_sdk)** (`siprix_voip_sdk`) | Native SIP: UDP/TCP/TLS | Native RTP/SRTP, AEC | **Commercial.** The trial drops calls after 60 s; price on request. | Android, iOS, macOS, Windows, Linux | Fastest route to a "real" generic softphone: multi-account, **PushKit+CallKit and FCM built in**, BLF, recording. | Closed source, licence cost, vendor lock-in. |
| **PJSIP** (e.g. [pjsip_connect_flutter](https://pub.dev/packages/pjsip_connect_flutter), bundles PJSIP 2.15.1, or your own FFI/platform-channel bridge) | Native, complete | Complete: SRTP, ICE, Opus, G.722, G.711, G.729… | **GPLv2+ or commercial licence from Teluu** | Android, iOS (+ desktop natively) | Industry standard, most complete and proven. | GPL means your app must be GPL or you buy a licence. Heavy native build work. Community Flutter wrappers are thin or immature. |
| **Linphone SDK** (liblinphone) via platform channels | Native, complete | Complete, incl. ZRTP | **AGPLv3 or commercial** (Belledonne) | Android, iOS SDKs. The existing [Flutter plugin](https://pub.dev/documentation/linphone_flutter_plugin/latest/) is Android-only and UDP-only. | Mature; comes with the Flexisip push ecosystem. | AGPL. You write most of the Flutter bridge yourself. |
| baresip / others via FFI | Native | Native | BSD (baresip) | Build it yourself | Permissive licence | A lot of integration work. Not evaluated in depth. |

**Call-UI and OS integration plugins** (needed with `sip_ua`):
- [flutter_callkit_incoming](https://pub.dev/packages/flutter_callkit_incoming) 3.x: CallKit + PushKit on iOS, full-screen notification on Android.
- `callbundle_ios`: reports PushKit pushes to CallKit synchronously.
- Or write your own small native layer for Core-Telecom.

### 10.1 Which path?

| Scenario | Recommended stack |
|---|---|
| You control the PBX (e.g. Asterisk with `webrtc=yes` on the PJSIP endpoint and a WSS transport on 8089, FreeSWITCH WSS profile, Kamailio/OpenSIPS + rtpengine) | **sip_ua + flutter_webrtc over WSS**, plus flutter_callkit_incoming. Cheapest, MIT, pure Dart. |
| Users must connect to arbitrary SIP providers or PBXs over UDP/TCP/TLS with plain RTP or SDES-SRTP | **Native stack**: Siprix (pay to ship fast) or PJSIP (GPL/commercial, most effort). |
| Prototype or learning | sip_ua against a local Asterisk/FreeSWITCH in Docker. |

---

## 11. Sippier scope: a simple phone app (decided 2026-11-02)

**Phase 1: MVP (macOS, Windows, Android; no server)**

Milestone 1 covers macOS and Android, milestone 2 Windows (1a.13). iOS was in this list until 2026-11-04, Linux until 2026-11-07.

- **Multiple accounts.** Form fields as in 1a.5, with a registration status per account.
- **Outgoing calls** with an account picker and a default account.
- **Incoming calls:**
  - desktop: runs in the tray, while the computer is awake; unregister before sleep, register again after wake, optional "keep awake" (1a.14)
  - Android: foreground service
- **In-call:** answer, reject, hang up, mute, speaker / audio device, DTMF keypad (RFC 4733), call timer.
- **TLS + SDES-SRTP.** Codecs G.722, PCMA, PCMU + telephone-event.
- **System call UI:** Core-Telecom on Android (also handles the audio session and Bluetooth basics); notifications with Answer/Decline on desktop.
- **General account settings** (1a.12): transport incl. auto/NAPTR, SRTP mode, codec order, STUN server, registration interval, auth username, outbound proxy, country for number normalisation, DTMF mode.
- ~~**Provider presets**~~: dropped on 2026-11-05; one generic account form (1a.12).
- **Emergency numbers** handed to the native dialer on Android by default.
- **UI in English + German.** Done 2026-11-07 (section 1a.12, "Localisation").
- **Open-source licences screen** listing the native libraries' licence texts (1a.6).

**Phase 2: daily comfort**
- Call history, contacts lookup (device address book on Android and macOS; Windows has none, see 1a.15), +49 number normalisation.
- **Hold/resume**, mainly for **call waiting** (second incoming call: hold and switch).
- Bluetooth/audio-route switching, proximity sensor.
- **Network change handling** (re-REGISTER + re-INVITE when the IP changes).
- Per-call caller-ID suppression (CLIR).

**Out of scope:** **iOS** for now (1a.13; research in 1a.10 and 9.1), call transfer (blind or attended), conference, BLF/presence, video, chat/MESSAGE, fax. Voicemail indicator (MWI): maybe later.

**Optional later:** iOS, with a push server for background ringing (1a.9, 1a.10); a server for multi-device Vodafone lines (1a.11).

---

## 12. Common pitfalls (and their usual causes)

| Symptom | Usual cause |
|---|---|
| One-way or no audio | NAT: private IP in SDP, no rport/comedia on the PBX, SIP ALG, missing STUN/TURN. On iOS, audio started before CallKit activated the session. |
| `488 Not Acceptable Here` | No codec in common, or an RTP/SRTP/DTLS profile mismatch (sip_ua *requires* DTLS-SRTP). |
| Call drops after ~32 s | The ACK never arrives (Timer H). Usually NAT or `Record-Route`/`Contact` problems. |
| Call drops after 15 or 30 min | Session timer (RFC 4028) mismatch or unanswered refresh. |
| Registration silently lost | NAT binding expired (no keep-alives), the app was suspended or killed in the background, or the computer slept (1a.14). |
| Caller hears ringing, nothing rings here | The provider still holds a registration for a contact that's asleep or gone. Unregister before sleep or backgrounding (1a.10, 1a.14). |
| Large INVITEs fail over UDP | Fragmentation. Use TCP/TLS/WSS. |
| Echo on speakerphone | AEC not active: wrong audio mode or source. |
| IVR doesn't recognise DTMF | `telephone-event` PT or clock-rate mismatch, or the other side expects SIP INFO. |
| iOS app killed on incoming push | The VoIP push wasn't reported to CallKit right away. |
| Calls break when leaving Wi-Fi | No re-REGISTER or re-INVITE after the IP changed. |

---

## 13. Tooling for development and testing

- **Wireshark:** Telephony → VoIP Calls / SIP Flows / RTP Stream Analysis. It can play back decoded G.711 audio.
- **sngrep:** a terminal SIP ladder-diagram viewer on the server.
- **SIPp:** scripted SIP scenarios and load tests.
- **Asterisk or FreeSWITCH in Docker** as a local test PBX. Add an echo-test extension (Asterisk `Echo()`) to check latency and audio.
- **Homer / HEP:** SIP and RTCP capture in production.

---

## 14. RFC quick reference

| RFC | Topic |
|---|---|
| 3261 | SIP core |
| 3262 / 3311 | PRACK / UPDATE |
| 3264 | SDP offer/answer |
| 8866 (obsoletes 4566) | SDP |
| 3550 / 3551 | RTP/RTCP / RTP A/V profile (static payload types) |
| 3711 | SRTP |
| 4568 | SDES (SRTP keys in SDP) |
| 5763 / 5764 | DTLS-SRTP |
| 4733 | DTMF telephone-event (obsoletes 2833) |
| 3389 | Comfort noise |
| 6716 / 7587 | Opus / Opus RTP payload |
| 3515 / 3891 | REFER / Replaces (transfer) |
| 6665 / 3842 / 4235 | SUBSCRIBE-NOTIFY / MWI / dialog event (BLF) |
| 3428 | MESSAGE |
| 4028 | Session timers |
| 3581 | rport |
| 5626 | SIP Outbound (keep-alives, flows) |
| 8489 / 8656 / 8445 | STUN / TURN / ICE |
| 7118 | SIP over WebSocket |
| 8599 | SIP push notifications |
| 2617 / 8760 | Digest auth MD5 / SHA-256 |
| 3325 | P-Asserted-Identity |

---

## 15. Sources

**Provider and requirement research (section 1a)**
- Vodafone, *IP Anlagen-Anschluss (R.6) Interface Description* (24 Apr 2026): https://www.vodafone.de/business/media/interface-description-ip-anlagen-anschluss-r6.pdf
- fonial, *Fact Sheet Trunking*: https://www.fonial.de/hilfe/fileadmin/user_upload/bilder/Trunking/Einrichtung_Trunking/Factsheet_Trunking_fonial.pdf
- Vodafone community forum, cable SIP credentials with third-party clients: https://forum.vodafone.de/t5/Ger%C3%A4te/SIP-Zugangsdaten-Zoiper-hinter-TC4400-Modem/m-p/3091450 · https://forum.vodafone.de/t5/Archiv-Internet-Ger%C3%A4te/SIP-Daten-f%C3%BCr-Softphone/m-p/2161261/highlight/true
- ip-phone-forum, Linphone with fonial: https://www.ip-phone-forum.de/threads/linphone-mit-fonial.321016/
- Siprix VoIP SDK 1.1.5: https://pub.dev/packages/siprix_voip_sdk
- PJSIP iOS push notifications guide: https://docs.pjsip.org/en/latest/specific-guides/other/ios_push_notifications.html
- Push proxy architecture: https://docs.sessiontalk.io/pushserver/overview · https://sessiontalk.co.uk/blog/fusionpbx-push-notifications-softphone-ios-android · https://faq.acrobits.net/push-notifications-on-pbx · https://www.zoiper.com/en/support/home/article/205/Zoiper

**Open-source stack decision (sections 1a.6–1a.8)**
- baresip (BSD-3, platforms, modules): https://github.com/baresip/baresip
- libre (BSD-3, RFC list incl. RFC 3263, platform tiers): https://github.com/baresip/re
- baresip_flutter (discontinued, Android-only): https://pub.dev/packages/baresip_flutter
- iCall (PJSIP GPLv2 and App Store note): https://github.com/icall-ing/icall · https://github.com/icall-ing/icall-android
- Pidgin "Why no iOS version" (GPL vs App Store): https://developer.pidgin.im/wiki/WhyNoiOSVersion
- VLC App Store GPL dispute (2011): https://www.cultofmac.com/67128/grab-vlc-for-your-ios-device-now-it-may-soon-be-pulled/
- Linphone third-party components and licensing: https://wiki.linphone.org/xwiki/wiki/public/view/Linphone/Third%20party%20components%20/
- Dart `NativeCallable.listener`: https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html

**Backend (section 1a.9)**
- Kamailio UAC module (remote registrations): https://www.kamailio.org/docs/modules/5.1.x/modules/uac
- Kamailio push with TSILO / t_suspend (sr-users threads): https://lists.kamailio.org/pipermail/sr-users/2016-June/093343.html · https://kamailio.org/mailman3/hyperkitty/list/sr-users@lists.kamailio.org/thread/OZUWNR3BRJ5FRKKYFMKCEGCOWPRB7IVC
- OpenSIPS RFC 8599 support: https://blog.opensips.org/2020/06/03/sip-push-notification-with-opensips-3-1-lts-rfc-8599-supportpart-ii/
- APNs VoIP push headers: https://learn.microsoft.com/en-us/azure/notification-hubs/voip-apns
- FCM legacy → HTTP v1 migration: https://firebase.google.cn/docs/cloud-messaging/migrate-v1?hl=en

**iOS without a server (section 1a.10)**
- Apple, Local Push Connectivity: https://developer.apple.com/tutorials/data/documentation/networkextension/local-push-connectivity.md
- Apple forum, Local Push only on Wi-Fi (matchSSIDs): https://developer.apple.com/forums/thread/656009
- WWDC20 "Build local push connectivity for restricted networks": https://developer.apple.com/videos/play/wwdc2020/10113/
- App Review 2.5.4 background audio rejections: https://developer.apple.com/forums/thread/91872 · https://www.biznessapps.com/support-sub/hc/en-us/articles/360015551979-App-Rejection-from-Apple-on-Guideline-2-5-4-for-audio-playback-
- fonial features (parallel ringing, mobile integration): https://www.capterra.ie/software/184378/fonial
- Apple DTS on background VoIP without push (Oct 2022): https://developer.apple.com/forums/thread/717335
- Local Push entitlement denials and dev-only approvals: https://developer.apple.com/forums/thread/819261 · https://developer.apple.com/forums/thread/834979
- Linphone: pushes only from Flexisip; third-party PBX must push: https://wiki.linphone.org/xwiki/wiki/public/view/Linphone/Sending%20push%20notification%20to%20Linphone%20mobile%20Apps/ · https://www.3cx.com/community/threads/calls-do-not-ring-on-linphone-client-when-in-background.115782/
- Belledonne paid push SaaS for third-party SIP accounts: https://www.mail-archive.com/linphone-users@nongnu.org/msg10190.html
- Zoiper iOS free tier without push: https://kb.sipcall.ch/en/enddevices/telephony/software/zoiper_ios/
- Yak (baresip iOS client, own push relay): https://www.indiehackers.com/product/yak-2
- Old iOS background TCP reports: https://www.dslreports.com/forum/r32113380-Voip-ms-how-to-avoid-softphone-killed-by-IOS
- Siprix CallKit/PushKit notes: https://docs.siprix-voip.com/rst/ioscallkit.html
- AgentCall (Cloudflare Worker APNs VoIP relay, MIT): https://github.com/Schreezer/AgentCall
- sipgate.io newCall webhooks: https://github.com/sipgate-io/sipgateio-incomingcall-node
- App Review Guidelines (2.5.4 marked "ASR & NR", i.e. it also applies to Notarization): https://developer.apple.com/app-store/review/guidelines/
- Apple, changes for apps in the EU (Notarization): https://developer.apple.com/support/dma-and-apps-in-the-eu/
- Notarization vs App Review in practice: https://dev.to/temer/app-review-banned-our-core-mechanic-notarization-let-it-through-and-caught-something-else-3gef
- AltStore getting started: https://faq.altstore.io/altstore-world/your-altstore · sideloading limits overview: https://www.xda-developers.com/how-to-sideload-apps-on-iphone/
- Silent-audio keep-alive implementations: https://hexdocs.pm/dala/Dala.Background.html · https://yifan.lu/2013/12/17/unlimited-backgrounding-on-ios/
- Apple DTS on VoIP background modes (audio + voip): https://developer.apple.com/forums/thread/792115
- Linphone CallKit without PushKit notes: https://wiki.linphone.org/xwiki/wiki/public/view/Lib/Features/IOS%20push%20notification%20management/

**General research**

- sip_ua on pub.dev: https://pub.dev/packages/sip_ua
- sip_ua API docs: https://pub.dev/documentation/sip_ua/latest/
- flutter_sip_ua (separate dart-pbx package): https://pub.dev/packages/flutter_sip_ua
- Siprix VoIP SDK: https://pub.dev/packages/siprix_voip_sdk and https://pub.dev/documentation/siprix_voip_sdk/latest/
- pjsip_connect_flutter: https://pub.dev/documentation/pjsip_connect_flutter/latest/
- flutter_nmsip: https://pub.dev/documentation/flutter_nmsip/latest
- linphone_flutter_plugin: https://pub.dev/documentation/linphone_flutter_plugin/latest/
- flutter_callkit_incoming versions: https://pub.dev/packages/flutter_callkit_incoming/versions
- callbundle_ios: https://pub.dev/packages/callbundle_ios
- PJSIP licensing: https://pjsip.org/licensing.htm · https://docs.pjsip.org/en/2.16/overview/license_pjsip.html
- linphone-sdk (licence in README): https://github.com/BelledonneCommunications/linphone-sdk
- Android foreground service types: https://developer.android.com/develop/background-work/services/fgs/service-types
- Android Core-Telecom: https://developer.android.com/develop/connectivity/telecom/voip-app/telecom
- Sinch: Push notifications & CallKit (iOS reporting rules): https://developers.sinch.com/docs/in-app-calling/ios/push-notifications-callkit/
- Voximplant: iOS push notifications: https://voximplant.com/blog/push-notifications-for-ios
- RFC 8599: https://datatracker.ietf.org/doc/rfc8599
- OpenSIPS RFC 8599 support: https://blog.opensips.org/2020/05/07/sip-push-notification-with-opensips-3-1-lts-rfc-8599-supportpart-i/ · https://blog.opensips.org/2020/06/03/sip-push-notification-with-opensips-3-1-lts-rfc-8599-supportpart-ii/
- Asterisk WebRTC configuration: https://docs.asterisk.org/Configuration/WebRTC/Configuring-Asterisk-for-WebRTC-Clients/
- Codec practice: https://sippulse.com/en/blog/codecs-voz-g711-g729-opus · https://telnyx.com/resources/voip-codec-list · https://telnyx.com/resources/codecs-affect-voip-sound-quality · https://connection-technologies.co.uk/help/voip-sip-trunking/sip-trunk-codecs-explained · https://sessiontalk.co.uk/blog/voip-codecs-explained-how-to-choose-the-best-codec-for-crystal-clear-call-quality-in-2025

**Staying awake (section 1a.14)**
- Windows `PowerSetRequest` (power request types, the Modern Standby 5-minute limit on battery): https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest
- Windows Modern Standby and the Desktop Activity Moderator: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/prepare-software-for-modern-standby · https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/integrating-apps-with-modern-standby
- GNOME automatic suspend on AC power (20 min since 3.28, 15 min on Fedora 38+): https://mail.gnome.org/archives/commits-list/2018-January/msg03420.html · https://discussion.fedoraproject.org/t/gnome-suspends-after-15-minutes-of-user-inactivity-even-on-ac-power/79801
- Android Doze and App Standby: https://developer.android.com/training/monitoring-device-state/doze-standby
- OEM battery savers per vendor: https://dontkillmyapp.com

**Contacts (section 1a.15)**
- `flutter_contacts` supported platforms: https://pub.dev/packages/flutter_contacts
- Android: third-party calling apps and the call log (`EXTRA_LOG_SELF_MANAGED_CALLS`, Android 17 change): https://source.android.com/docs/core/connect/third-party-call-apps
- Windows Contacts API: https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.contacts
- Windows People app retired: https://learn.microsoft.com/en-gb/windows/apps/develop/launch/launch-people-app · My People unsupported on Windows 11: https://learn.microsoft.com/en-gb/windows/uwp/contacts-and-calendar/my-people-support

_Facts not linked above (RFC numbers, payload types, bandwidth arithmetic, the G.722 clock-rate quirk, platform behaviour) come from the standards themselves and general VoIP engineering knowledge. Check package versions and licences on pub.dev before you commit to one._

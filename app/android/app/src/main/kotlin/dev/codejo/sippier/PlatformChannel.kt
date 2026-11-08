package dev.codejo.sippier

import android.Manifest
import android.app.ActivityManager
import android.app.LocaleManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.LocaleList
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import kotlin.system.exitProcess

/**
 * The "sippier/platform" channel: what the SIP core can't do itself on
 * Android. Lives as long as the process; [activity] is set while the UI is
 * open.
 */
class PlatformChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "sippier/platform")
    private val audio = context.getSystemService(AudioManager::class.java)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private var lastDnsServers = emptyList<String>()

    // What Dart last asked for, so the service can be started later if
    // Android didn't allow it at the time.
    private var serviceWanted = false
    private var serviceText = ""
    private var serviceInCall = false
    private var serviceStayAwake = true
    private var micResult: MethodChannel.Result? = null

    var activity: MainActivity? = null

    /** An incoming call is ringing or a call is active: show over the lock screen. */
    var callActive = false
        private set(value) {
            field = value
            activity?.showOverLockScreen(value)
        }

    init {
        createNotificationChannels()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicrophone" -> requestMicrophone(result)
                "dnsServers" -> result.success(currentDnsServers())
                "setInCall" -> { setInCall(call.arguments as Boolean); result.success(null) }
                "setSpeaker" -> { setSpeaker(call.arguments as Boolean); result.success(null) }
                // The incoming call notification rings, see showIncomingCall()
                "startRinging", "stopRinging" -> result.success(null)
                "canShowCallsOnLockScreen" -> result.success(canUseFullScreenIntent())
                "openLockScreenSettings" -> { openLockScreenSettings(); result.success(null) }
                "openRingtoneSettings" -> { openRingtoneSettings(); result.success(null) }
                "isBackgroundRestricted" -> result.success(isBackgroundRestricted())
                "openBatterySettings" -> { openBatterySettings(); result.success(null) }
                "isBatteryUnrestricted" -> result.success(isBatteryUnrestricted())
                "requestUnrestrictedBattery" -> {
                    requestUnrestrictedBattery(); result.success(null)
                }
                "updateStatus" -> { updateStatus(call.arguments as Map<*, *>); result.success(null) }
                "showIncomingCall" -> {
                    showIncomingCall(call.arguments as Map<*, *>); result.success(null)
                }
                "cancelIncomingCall" -> {
                    notifications.cancel(INCOMING_CALL_ID); result.success(null)
                }
                "quit" -> { quit(); result.success(null) }
                "setLanguage" -> { setLanguage(call.arguments as String?); result.success(null) }
                "openUrl" -> { openUrl(call.arguments as String); result.success(null) }
                "saveFile" -> {
                    val args = call.arguments as Map<*, *>
                    saveFile(
                        args["name"] as String, args["mimeType"] as String,
                        (args["content"] as String).toByteArray(), result)
                }
                else -> result.notImplemented()
            }
        }
        watchNetwork()
    }

    /** Answer or decline from the notification. */
    fun callAction(method: String, callId: String) {
        notifications.cancel(INCOMING_CALL_ID)
        channel.invokeMethod(method, callId)
    }

    fun requestQuit() = channel.invokeMethod("quit", null)

    /**
     * Battery saver alarm: the core registers again where due and answers
     * with the milliseconds until the next alarm (a minute if Dart doesn't).
     */
    fun keepAlive(next: (Long) -> Unit) {
        channel.invokeMethod("keepAlive", null, object : MethodChannel.Result {
            override fun success(result: Any?) = next((result as? Number)?.toLong() ?: 60_000L)
            override fun error(code: String, message: String?, details: Any?) = next(60_000L)
            override fun notImplemented() = next(60_000L)
        })
    }

    // Microphone permission (needs the activity)

    private fun requestMicrophone(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        val a = activity ?: return result.success(false)
        micResult?.success(false)
        micResult = result
        a.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
    }

    // Saving a file where the user picks: the system's "create document"
    // screen (needs the activity). Answers false if they cancel.

    private var saveResult: MethodChannel.Result? = null
    private var saveContent: ByteArray? = null

    private fun saveFile(
        name: String, mimeType: String, content: ByteArray, result: MethodChannel.Result
    ) {
        val a = activity ?: return result.success(false)
        saveResult?.success(false)
        saveResult = result
        saveContent = content
        a.startActivityForResult(
            Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(mimeType)
                .putExtra(Intent.EXTRA_TITLE, name),
            SAVE_REQUEST)
    }

    fun onSaveResult(uri: Uri?) {
        val result = saveResult ?: return
        val content = saveContent
        saveResult = null
        saveContent = null
        if (uri == null || content == null) return result.success(false)
        try {
            val out = context.contentResolver.openOutputStream(uri, "wt")
                ?: throw IOException("Can't write $uri")
            out.use { it.write(content) }
            result.success(true)
        } catch (e: Exception) {
            result.error("saveFile", e.message, null)
        }
    }

    fun onMicrophoneResult(granted: Boolean) {
        micResult?.success(granted)
        micResult = null
    }

    // DNS

    // Link-local servers would need a scope id, which libre can't take.
    private fun dnsServers(lp: LinkProperties?): List<String> =
        lp?.dnsServers?.filterNot { it.isLinkLocalAddress }?.mapNotNull { it.hostAddress }
            ?: emptyList()

    // activeNetwork is null while Android blocks the app's network (e.g. it
    // started in Doze), so fall back to what the callback last reported.
    private fun currentDnsServers(): List<String> =
        dnsServers(connectivity.getLinkProperties(connectivity.activeNetwork))
            .ifEmpty { lastDnsServers }

    /** The UI is visible: the app may start its service and has network. */
    fun onUiVisible() {
        applyService()
        sendDnsServers(currentDnsServers())
    }

    private fun sendDnsServers(servers: List<String>) {
        if (servers.isEmpty()) return
        lastDnsServers = servers
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod("dnsServersChanged", servers)
        }
    }

    /** Tells Dart about the default network's DNS servers: on start, on
     * Wi-Fi <-> mobile changes and when Android unblocks the app's network. */
    /** Default network and its addresses, last sent to Dart. */
    private var networkKey: String? = null

    private fun watchNetwork() {
        connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val lp = connectivity.getLinkProperties(network)
                sendDnsServers(dnsServers(lp))
                checkAddresses(network, lp)
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                sendDnsServers(dnsServers(lp))
                checkAddresses(network, lp)
            }

            override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
                if (!blocked) sendDnsServers(dnsServers(connectivity.getLinkProperties(network)))
            }
        })
    }

    /**
     * Another network, or new addresses on it (IPv6 privacy addresses
     * rotate): the core's SIP sockets are still bound to the old ones. The
     * first network after start needs nothing; the core just bound to it.
     */
    private fun checkAddresses(network: Network, lp: LinkProperties?) {
        val addresses = lp?.linkAddresses?.map { it.address.hostAddress }?.sorted() ?: return
        val key = "$network ${addresses.joinToString(",")}"
        if (key == networkKey) return
        val first = networkKey == null
        networkKey = key
        if (!first) Handler(Looper.getMainLooper()).post { channel.invokeMethod("networkChanged", null) }
    }

    // Audio

    private fun setInCall(inCall: Boolean) {
        audio.mode = if (inCall) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
        if (!inCall) setSpeaker(false)
    }

    private fun setSpeaker(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (on) {
                audio.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let { audio.setCommunicationDevice(it) }
            } else {
                audio.clearCommunicationDevice()
            }
        } else {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = on
        }
    }

    // Background service and notifications

    /** {text, registered, background, inCall} from Dart on every state change. */
    private fun updateStatus(args: Map<*, *>) {
        serviceText = args["text"] as? String ?: ""
        serviceInCall = args["inCall"] as? Boolean ?: false
        serviceStayAwake = args["stayAwake"] as? Boolean ?: true
        serviceWanted = (args["background"] as? Boolean ?: false) || serviceInCall
        callActive = serviceInCall
        applyService()
    }

    private fun applyService() {
        if (!serviceWanted) {
            context.stopService(Intent(context, SipService::class.java))
            return
        }
        SipService.instance?.let {
            it.update(serviceText, serviceInCall, serviceStayAwake)
            return
        }
        try {
            ContextCompat.startForegroundService(context,
                Intent(context, SipService::class.java)
                    .putExtra(SipService.EXTRA_TEXT, serviceText)
                    .putExtra(SipService.EXTRA_IN_CALL, serviceInCall)
                    .putExtra(SipService.EXTRA_STAY_AWAKE, serviceStayAwake))
        } catch (e: IllegalStateException) {
            // Not allowed in the background, e.g. when the app started with
            // the screen locked. onUiVisible() tries again.
        }
    }

    /**
     * Posted for every incoming call, also with the app open: Android drops
     * audio and vibration from apps it doesn't consider in front, so the
     * system rings through the notification channel instead.
     */
    private fun showIncomingCall(args: Map<*, *>) {
        val callId = args["callId"] as String
        val caller = args["caller"] as? String ?: ""
        callActive = true

        val open = PendingIntent.getActivity(context, 0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val answer = PendingIntent.getActivity(context, 1,
            Intent(context, MainActivity::class.java)
                .setAction(MainActivity.ACTION_ANSWER)
                .putExtra(EXTRA_CALL_ID, callId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val decline = PendingIntent.getBroadcast(context, 2,
            Intent(context, CallActionReceiver::class.java)
                .setAction(CallActionReceiver.ACTION_DECLINE)
                .putExtra(EXTRA_CALL_ID, callId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val person = Person.Builder()
            .setName(caller.ifEmpty { context.getString(R.string.caller_unknown) }).build()
        val notification = NotificationCompat.Builder(context, CALLS_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_sippier)
            .setContentTitle(caller)
            .setContentText(context.getString(R.string.notification_incoming_call))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, decline, answer))
            .build()
        // Repeat the channel's ringtone until the call is answered or ends
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        notifications.notify(INCOMING_CALL_ID, notification)
        Log.i(TAG, "incoming call notification: ringer=${audio.ringerMode} " +
            "dnd=${notifications.currentInterruptionFilter} " +
            "channel=${notifications.getNotificationChannel(CALLS_CHANNEL)?.importance} " +
            "enabled=${notifications.areNotificationsEnabled()} " +
            "fullScreen=${canUseFullScreenIntent()}")
    }

    /** Needed to show the call screen over the lock screen (Android 14+). */
    private fun canUseFullScreenIntent(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            notifications.canUseFullScreenIntent()

    private fun openLockScreenSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
            .setData(android.net.Uri.fromParts("package", context.packageName, null))
        (activity ?: context).startActivity(
            if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) else intent)
    }

    /**
     * Battery usage "Restricted": Android stops the app in the background,
     * foreground service included, so no calls come in.
     */
    private fun isBackgroundRestricted(): Boolean =
        context.getSystemService(ActivityManager::class.java).isBackgroundRestricted

    /**
     * Battery usage "Unrestricted": Sippier is on the power allowlist, so
     * its keep-alive alarms are exact and not limited while the phone dozes.
     * Under "Optimized" they're inexact and capped (72 an hour on Android 12+).
     */
    private fun isBatteryUnrestricted(): Boolean =
        context.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(context.packageName)

    /** The system's "Let app always run in background?" dialog. */
    private fun requestUnrestrictedBattery() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(android.net.Uri.fromParts("package", context.packageName, null))
        try {
            (activity ?: context).startActivity(
                if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) else intent)
        } catch (e: android.content.ActivityNotFoundException) {
            // some vendors drop the dialog; App info still has the setting
            openBatterySettings()
        }
    }

    /** App info; its "App battery usage" page has no intent of its own. */
    private fun openBatterySettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(android.net.Uri.fromParts("package", context.packageName, null))
        (activity ?: context).startActivity(
            if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) else intent)
    }

    /** The incoming-call channel's settings, where the user picks its sound. */
    private fun openUrl(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        try {
            (activity ?: context).startActivity(
                if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) else intent)
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "No app opens $url")
        }
    }

    private fun openRingtoneSettings() {
        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, CALLS_CHANNEL)
        (activity ?: context).startActivity(
            if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) else intent)
    }

    private fun createNotificationChannels() {
        notifications.createNotificationChannel(
            NotificationChannel(SERVICE_CHANNEL, context.getString(R.string.channel_service),
                NotificationManager.IMPORTANCE_LOW).apply {
                description = context.getString(R.string.channel_service_description)
                setShowBadge(false)
            })
        // Channel settings can't change after creation; this one rings.
        notifications.deleteNotificationChannel("calls")
        notifications.createNotificationChannel(
            NotificationChannel(CALLS_CHANNEL, context.getString(R.string.channel_calls),
                NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    RINGTONE_ATTRIBUTES)
                enableVibration(true)
                vibrationPattern = VIBRATION_PATTERN
            })
    }

    /**
     * The language picked in Sippier's settings ("de"), or null for the
     * system's. Android 13+ keeps it as the app's language, so the
     * notifications (res/values*) follow it; older versions stay with the
     * system's. MainActivity handles the locale change itself (configChanges).
     */
    private fun setLanguage(tag: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        context.getSystemService(LocaleManager::class.java).applicationLocales =
            if (tag == null) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
    }

    /** Dart has shut down the SIP core; end the process. */
    private fun quit() {
        notifications.cancel(INCOMING_CALL_ID)
        context.stopService(Intent(context, SipService::class.java))
        activity?.finishAndRemoveTask()
        Handler(Looper.getMainLooper()).postDelayed({ exitProcess(0) }, 300)
    }

    companion object {
        private const val TAG = "sippier"
        const val SERVICE_CHANNEL = "service"
        const val CALLS_CHANNEL = "incoming_calls"
        val VIBRATION_PATTERN = longArrayOf(0, 800, 800)
        val RINGTONE_ATTRIBUTES: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        const val INCOMING_CALL_ID = 2
        const val EXTRA_CALL_ID = "callId"
        const val MIC_REQUEST = 1
        const val SAVE_REQUEST = 3
    }
}

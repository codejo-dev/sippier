package dev.codejo.sippier

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the process, and with it the SIP registration, alive while Sippier
 * is in the background, in one of two ways (per account in the app):
 * - Stay awake (the default): a partial wake lock, because libre's timers
 *   stop while the CPU sleeps. Reliable, but the CPU never sleeps. Android
 *   keeps wake locks of foreground-service apps working in Doze.
 * - Battery saver: no wake lock. An alarm wakes the CPU shortly before a
 *   registration refresh is due and the core registers again
 *   (sc_keepalive); incoming calls wake the device through the network.
 * Ringing and calls always hold the wake lock.
 */
class SipService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var keepAliveLock: PowerManager.WakeLock? = null
    private var text = ""
    private var inCall = false
    private var stayAwake = true
    private var alarmSet = false

    private val alarm by lazy {
        PendingIntent.getBroadcast(this, 4, Intent(this, KeepAliveReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val power = getSystemService(PowerManager::class.java)
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sippier:registration")
            .apply { setReferenceCounted(false) }
        keepAliveLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sippier:keepalive")
            .apply { setReferenceCounted(false) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        text = intent?.getStringExtra(EXTRA_TEXT) ?: text
        inCall = intent?.getBooleanExtra(EXTRA_IN_CALL, inCall) ?: inCall
        stayAwake = intent?.getBooleanExtra(EXTRA_STAY_AWAKE, stayAwake) ?: stayAwake
        startInForeground()
        applyPower()
        return START_STICKY
    }

    override fun onDestroy() {
        cancelKeepAlive()
        wakeLock?.release()
        keepAliveLock?.release()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    fun update(text: String, inCall: Boolean, stayAwake: Boolean) {
        this.text = text
        this.inCall = inCall
        this.stayAwake = stayAwake
        startInForeground()
        applyPower()
    }

    private fun applyPower() {
        if (stayAwake || inCall) {
            cancelKeepAlive()
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire()
                Log.i(TAG, "background: keeping the phone awake")
            }
        } else {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.i(TAG, "background: battery saver")
            }
            if (!alarmSet) scheduleKeepAlive(FIRST_KEEPALIVE_MS)
        }
    }

    /** From the alarm: the core registers again where due. */
    fun keepAlive() {
        alarmSet = false
        if (stayAwake || inCall) return
        keepAliveLock?.acquire(KEEPALIVE_LOCK_MS)
        (application as SippierApplication).platform.keepAlive { ms ->
            if (!stayAwake && !inCall) scheduleKeepAlive(ms)
        }
    }

    private fun scheduleKeepAlive(ms: Long) {
        val alarms = getSystemService(AlarmManager::class.java)
        val at = SystemClock.elapsedRealtime() + ms
        // Android 14+ grants exact alarms when battery usage is Unrestricted
        // (or "Alarms & reminders" is allowed). Inexact ones can come minutes
        // late, and while the phone dozes Optimized apps get 72 an hour.
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        if (exact) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, alarm)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, alarm)
        }
        alarmSet = true
        Log.i(TAG, "battery saver: next wake-up in ${ms / 1000} s (${if (exact) "exact" else "inexact"})")
    }

    private fun cancelKeepAlive() {
        if (!alarmSet) return
        getSystemService(AlarmManager::class.java).cancel(alarm)
        alarmSet = false
    }

    private fun startInForeground() {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE)
        val quit = PendingIntent.getBroadcast(this, 3,
            Intent(this, CallActionReceiver::class.java).setAction(CallActionReceiver.ACTION_QUIT),
            PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, PlatformChannel.SERVICE_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_sippier)
            .setContentTitle(getString(
                if (inCall) R.string.notification_in_call else R.string.notification_ready))
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, getString(R.string.notification_quit), quit)
            .build()

        // The microphone type is only allowed while a call is running, and
        // only when the call started with the app in front (it does: dialing
        // and answering both open the app).
        val mic = inCall && ContextCompat.checkSelfPermission(
            this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            type = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        }
        if (mic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        if (type == 0) {
            startForeground(NOTIFICATION_ID, notification)
        } else {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        }
    }

    companion object {
        const val EXTRA_TEXT = "text"
        const val EXTRA_IN_CALL = "inCall"
        const val EXTRA_STAY_AWAKE = "stayAwake"
        private const val TAG = "sippier"
        private const val FIRST_KEEPALIVE_MS = 30_000L
        private const val KEEPALIVE_LOCK_MS = 10_000L
        const val NOTIFICATION_ID = 1
        var instance: SipService? = null
            private set
    }
}

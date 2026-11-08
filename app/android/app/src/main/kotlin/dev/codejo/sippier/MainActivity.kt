package dev.codejo.sippier

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/** The UI. Uses the engine owned by [SippierApplication], which outlives it. */
class MainActivity : FlutterActivity() {
    private val platform get() = (application as SippierApplication).platform

    override fun getCachedEngineId() = SippierApplication.ENGINE_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        platform.activity = this
        showOverLockScreen(platform.callActive)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
        }
        handleCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        platform.activity = this
        platform.onUiVisible()
    }

    override fun onDestroy() {
        if (platform.activity == this) platform.activity = null
        super.onDestroy()
    }

    // The file PlatformChannel.saveFile asked the user for
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PlatformChannel.SAVE_REQUEST) {
            platform.onSaveResult(if (resultCode == RESULT_OK) data?.data else null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PlatformChannel.MIC_REQUEST) {
            platform.onMicrophoneResult(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }

    /** While a call rings or runs, the call screen shows over the lock screen. */
    fun showOverLockScreen(show: Boolean) {
        setShowWhenLocked(show)
        setTurnScreenOn(show)
    }

    private fun handleCallIntent(intent: Intent?) {
        if (intent?.action != ACTION_ANSWER) return
        intent.getStringExtra(PlatformChannel.EXTRA_CALL_ID)
            ?.let { platform.callAction("answer", it) }
        intent.action = null
    }

    companion object {
        const val ACTION_ANSWER = "dev.codejo.sippier.ANSWER"
        private const val NOTIFY_REQUEST = 2
    }
}

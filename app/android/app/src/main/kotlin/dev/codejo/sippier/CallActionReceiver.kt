package dev.codejo.sippier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Notification buttons that don't need the UI: decline a call, quit. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val platform = (context.applicationContext as SippierApplication).platform
        when (intent.action) {
            ACTION_DECLINE -> intent.getStringExtra(PlatformChannel.EXTRA_CALL_ID)
                ?.let { platform.callAction("hangup", it) }
            ACTION_QUIT -> platform.requestQuit()
        }
    }

    companion object {
        const val ACTION_DECLINE = "dev.codejo.sippier.DECLINE"
        const val ACTION_QUIT = "dev.codejo.sippier.QUIT"
    }
}

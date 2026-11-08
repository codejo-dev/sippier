package dev.codejo.sippier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Battery saver: the alarm that wakes the CPU for registration refreshes. */
class KeepAliveReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        SipService.instance?.keepAlive()
    }
}

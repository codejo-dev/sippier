package dev.codejo.sippier

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns the Flutter engine, so Dart (and with it the SIP core's event
 * handling) keeps running when the activity is closed. SipService keeps the
 * process alive.
 */
class SippierApplication : Application() {
    lateinit var platform: PlatformChannel
        private set

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        platform = PlatformChannel(this, engine.dartExecutor.binaryMessenger)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "main"
    }
}

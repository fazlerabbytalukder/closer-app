package app.closer.widget

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import app.closer.widget.work.WidgetRefreshWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var guard: MethodChannel? = null

    /** Android 14+: told when the user takes a screenshot of the app. */
    private val screenCapture: Any? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            Activity.ScreenCaptureCallback { guard?.invokeMethod("screenshot", null) }
        } else {
            null
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the periodic + midnight widget refresh armed (idempotent, KEEP policy).
        WidgetRefreshWorker.schedule(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Chat privacy: block screenshots on a snap, report screenshots in chat.
        guard = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.closer/screen_guard").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    "canDetect" -> result.success(screenCapture != null)
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerScreenCaptureCallback(mainExecutor, screenCapture as Activity.ScreenCaptureCallback)
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            unregisterScreenCaptureCallback(screenCapture as Activity.ScreenCaptureCallback)
        }
        super.onStop()
    }
}

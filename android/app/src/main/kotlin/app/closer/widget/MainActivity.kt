package app.closer.widget

import android.os.Bundle
import app.closer.widget.work.WidgetRefreshWorker
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the periodic + midnight widget refresh armed (idempotent, KEEP policy).
        WidgetRefreshWorker.schedule(this)
    }
}

package PKG

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        QzPlayer.setup(this, flutterEngine)
    }

    override fun onDestroy() {
        QzPlayer.release()
        super.onDestroy()
    }
}

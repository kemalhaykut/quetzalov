package PKG

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView

/**
 * Tam ekran oynatıcı ekranı (tamamen Android'in kendi arayüzü — üstüne Flutter çizmez).
 * Canlı: ▲▼ / CH+ CH- kanal değiştir, OK kontrolleri göster.
 * Film/dizi: ◀▶ 10 sn sar (basılı tut: hızlanır), ▼ / OK kontrol çubuğu, altyazı ve ses: çubuktaki düğmeler.
 */
class PlayerActivity : Activity() {
    private lateinit var pv: PlayerView
    private lateinit var info: TextView
    private val h = Handler(Looper.getMainLooper())
    private var live = false
    private var names: ArrayList<String> = arrayListOf()
    private var urls: ArrayList<String> = arrayListOf()
    private var alts: ArrayList<String> = arrayListOf()
    private var index = 0
    private var retries = 0
    private var pending: Runnable? = null
    private val hideInfo = Runnable { info.visibility = View.GONE }

    private val listener = object : Player.Listener {
        override fun onPlayerError(error: PlaybackException) {
            if (!live) {
                showInfo("Oynatılamadı (${error.errorCodeName}). Geri tuşuyla çıkıp tekrar deneyin.", 8000)
                return
            }
            retry()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (live && playbackState == Player.STATE_ENDED) retry()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying && retries > 0) {
                retries = 0
                h.removeCallbacks(hideInfo)
                info.visibility = View.GONE
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        live = intent.getBooleanExtra("live", false)
        names = intent.getStringArrayListExtra("names") ?: arrayListOf()
        urls = intent.getStringArrayListExtra("urls") ?: arrayListOf()
        alts = intent.getStringArrayListExtra("alts") ?: arrayListOf()
        index = intent.getIntExtra("index", 0)

        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)
        pv = PlayerView(this)
        pv.setBackgroundColor(Color.BLACK)
        pv.setShutterBackgroundColor(Color.BLACK)
        pv.setKeepContentOnPlayerReset(true)
        pv.setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
        pv.controllerShowTimeoutMs = if (live) 3000 else 5000
        pv.controllerAutoShow = !live
        pv.setShowSubtitleButton(true)
        pv.setShowNextButton(false)
        pv.setShowPreviousButton(false)
        pv.setShowFastForwardButton(!live)
        pv.setShowRewindButton(!live)
        pv.player = QzPlayer.ensure()
        QzPlayer.attach(pv)
        root.addView(pv, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        info = TextView(this)
        info.setTextColor(Color.WHITE)
        info.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
        info.setBackgroundColor(0xCC0B0B10.toInt())
        info.setPadding(28, 14, 28, 14)
        info.visibility = View.GONE
        val lp = FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.START)
        lp.setMargins(48, 36, 48, 0)
        root.addView(info, lp)
        setContentView(root)

        pv.player?.addListener(listener)
        val title = intent.getStringExtra("title") ?: ""
        val sub = intent.getStringExtra("subtitle") ?: ""
        if (live && names.isNotEmpty()) {
            showInfo("${index + 1}   ${names.getOrElse(index) { title }}", 3500)
        } else if (title.isNotEmpty()) {
            showInfo(if (sub.isNotEmpty()) "$title\n$sub" else title, 4000)
        }
        pv.requestFocus()
    }

    private fun showInfo(text: String, ms: Long) {
        info.text = text
        info.visibility = View.VISIBLE
        h.removeCallbacks(hideInfo)
        h.postDelayed(hideInfo, ms)
    }

    private fun openChannel(alt: Boolean) {
        if (urls.isEmpty()) return
        index = (index + urls.size) % urls.size
        val u = if (alt && alts.size == urls.size) alts[index] else urls[index]
        QzPlayer.openUrl(u)
    }

    private fun schedule(delay: Long, r: Runnable) {
        pending?.let { h.removeCallbacks(it) }
        pending = r
        h.postDelayed(r, delay)
    }

    private fun retry() {
        if (retries >= 8) {
            showInfo("Yayına ulaşılamıyor. Başka bir kanal deneyin.", 10000)
            return
        }
        retries++
        showInfo("Yayın kesildi, yeniden bağlanılıyor… ($retries)", 5000)
        val alt = retries % 2 == 0
        QzPlayer.stopNow()
        schedule(800L + 700L * retries, Runnable { if (!isFinishing) openChannel(alt) })
    }

    private fun switchChannel(d: Int) {
        if (urls.isEmpty()) return
        retries = 0
        index = (index + d + urls.size) % urls.size
        showInfo("${index + 1}   ${names.getOrElse(index) { "" }}", 3000)
        // Tek bağlantı izinli hesaplar: önce eski bağlantıyı kapat, kısa süre bekle (hızlı zapping'de son seçilen açılır)
        QzPlayer.stopNow()
        schedule(450L, Runnable { if (!isFinishing) openChannel(false) })
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val visible = pv.isControllerFullyVisible
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    if (visible) {
                        pv.hideController()
                        return true
                    }
                }
                KeyEvent.KEYCODE_CHANNEL_UP, KeyEvent.KEYCODE_PAGE_UP -> if (live) {
                    switchChannel(-1)
                    return true
                }
                KeyEvent.KEYCODE_CHANNEL_DOWN, KeyEvent.KEYCODE_PAGE_DOWN -> if (live) {
                    switchChannel(1)
                    return true
                }
                KeyEvent.KEYCODE_DPAD_UP -> if (live && !visible) {
                    if (event.repeatCount == 0) switchChannel(-1)
                    return true
                }
                KeyEvent.KEYCODE_DPAD_DOWN -> if (live && !visible) {
                    if (event.repeatCount == 0) switchChannel(1)
                    return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    // Film/dizi: kontrol çubuğu kapalıyken ya da odak oynat/duraklat düğmesindeyken ◀▶ doğrudan sarar
                    val f = currentFocus?.id
                    val onPlay = f == androidx.media3.ui.R.id.exo_play_pause || f == null || f == View.NO_ID
                    if (!live && (!visible || onPlay)) {
                        val p = pv.player
                        if (p != null) {
                            val step = when {
                                event.repeatCount > 20 -> 60000L
                                event.repeatCount > 8 -> 30000L
                                else -> 10000L
                            }
                            val dir = if (event.keyCode == KeyEvent.KEYCODE_DPAD_LEFT) -1 else 1
                            var t = p.currentPosition + dir * step
                            if (t < 0) t = 0
                            val d = p.duration
                            if (d > 0 && t > d - 2000) t = d - 2000
                            p.seekTo(t)
                        }
                        pv.showController()
                        return true
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        h.removeCallbacksAndMessages(null)
        val p = pv.player
        val pos = p?.currentPosition ?: 0L
        val dur = p?.duration?.let { if (it < 0) 0L else it } ?: 0L
        p?.removeListener(listener)
        pv.player = null
        QzPlayer.detach(pv)
        QzPlayer.playerClosed(pos, dur, index)
        super.onDestroy()
    }
}

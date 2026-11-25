package PKG

import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Android TV için ExoPlayer (Media3) tabanlı oynatıcı. Flutter ile kanal üzerinden konuşur. */
object QzPlayer : Player.Listener {
    private var ctx: Context? = null
    private var player: ExoPlayer? = null
    private var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val views = mutableListOf<PlayerView>()
    private var builtLevel = -1
    private var bufferLevel = 1
    private var ua = "Quetzalov"
    private var subSize = 22f
    private var errorSeq = 0
    private var lastError = ""
    private var endedSeq = 0
    private var tracksSeq = 0

    /** Flutter her 400 ms'de bir bunu sorar (olay kanalına güvenmeden). */
    private fun state(): Map<String, Any?> {
        val p = player
        val dur = p?.duration ?: 0L
        return mapOf(
            "pos" to (p?.currentPosition ?: 0L),
            "dur" to (if (dur == C.TIME_UNSET || dur < 0) 0L else dur),
            "buf" to (p?.bufferedPosition ?: 0L),
            "playing" to (p?.isPlaying ?: false),
            "buffering" to (p?.playbackState == Player.STATE_BUFFERING),
            "errorSeq" to errorSeq,
            "error" to lastError,
            "endedSeq" to endedSeq,
            "tracksSeq" to tracksSeq,
        )
    }

    private fun tracksMap(): Map<String, Any?> {
        val p = player ?: return mapOf("list" to emptyList<Any>(), "subOff" to false)
        val list = ArrayList<Map<String, Any?>>()
        p.currentTracks.groups.forEachIndexed { gi, g ->
            val type = when (g.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "sub"
                C.TRACK_TYPE_VIDEO -> "video"
                else -> null
            } ?: return@forEachIndexed
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                list.add(
                    mapOf(
                        "type" to type,
                        "id" to "$gi:$i",
                        "label" to f.label,
                        "lang" to f.language,
                        "h" to (if (f.height > 0) f.height else null),
                        "codec" to (f.sampleMimeType ?: f.codecs),
                        "ch" to (if (f.channelCount > 0) f.channelCount else null),
                        "sel" to g.isTrackSelected(i),
                    ),
                )
            }
        }
        return mapOf("list" to list, "subOff" to p.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    private val ticker = object : Runnable {
        override fun run() {
            sendPos()
            handler.postDelayed(this, 500)
        }
    }

    fun setup(context: Context, engine: FlutterEngine) {
        ctx = context.applicationContext
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "qz/player").setMethodCallHandler { call, result ->
            try {
                @Suppress("UNCHECKED_CAST")
                val a = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                when (call.method) {
                    "state" -> result.success(state())
                    "tracks" -> result.success(tracksMap())
                    else -> {
                        handle(call.method, a)
                        result.success(null)
                    }
                }
            } catch (e: Throwable) {
                result.error("qz", e.message, null)
            }
        }
        EventChannel(messenger, "qz/player/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
        engine.platformViewsController.registry.registerViewFactory("qz/video", VideoFactory)
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    fun release() {
        handler.removeCallbacks(ticker)
        player?.release()
        player = null
        builtLevel = -1
    }

    fun ensure(): ExoPlayer {
        val existing = player
        if (existing != null && builtLevel == bufferLevel) return existing
        existing?.release()
        val c = ctx!!
        val (minB, maxB, startB, rebufB) = when (bufferLevel) {
            0 -> listOf(15000, 50000, 1500, 3000)
            2 -> listOf(50000, 180000, 3000, 6000)
            else -> listOf(30000, 120000, 2000, 4000)
        }
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(minB, maxB, startB, rebufB)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(ua)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(30000)
        val extractors = DefaultExtractorsFactory()
            .setTsExtractorFlags(DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES)
            .setConstantBitrateSeekingEnabled(true)
        val renderers = DefaultRenderersFactory(c).setEnableDecoderFallback(true)
        val p = ExoPlayer.Builder(c, renderers)
            .setLoadControl(load)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http, extractors))
            .build()
        p.addListener(this)
        p.setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            true,
        )
        p.setWakeMode(C.WAKE_MODE_NETWORK)
        for (v in views) v.player = p
        player = p
        builtLevel = bufferLevel
        return p
    }

    private fun handle(m: String, a: Map<String, Any?>) {
        when (m) {
            "open" -> {
                bufferLevel = (a["buffer"] as? Number)?.toInt() ?: 1
                ua = (a["ua"] as? String) ?: ua
                (a["subSize"] as? Number)?.let { subSize = it.toFloat(); views.forEach { v -> styleSubs(v) } }
                val p = ensure()
                p.stop()
                p.clearMediaItems()
                val url = a["url"] as String
                val subLang = (a["subLang"] as? String) ?: "tur"
                val audioLang = (a["audioLang"] as? String) ?: ""
                val b = p.trackSelectionParameters.buildUpon()
                    .clearOverrides()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, subLang == "no")
                    .setSelectUndeterminedTextLanguage(true)
                if (subLang != "no") b.setPreferredTextLanguages(subLang, "tr", "en")
                if (audioLang.isNotEmpty()) b.setPreferredAudioLanguages(audioLang)
                p.trackSelectionParameters = b.build()
                val item = MediaItem.Builder().setUri(url)
                if (url.endsWith(".m3u8")) item.setMimeType(MimeTypes.APPLICATION_M3U8)
                val start = (a["start"] as? Number)?.toLong()
                if (start != null && start > 0) p.setMediaItem(item.build(), start) else p.setMediaItem(item.build())
                p.prepare()
                p.playWhenReady = true
            }
            "play" -> player?.play()
            "pause" -> player?.pause()
            "toggle" -> player?.let { if (it.isPlaying || it.playWhenReady) it.pause() else it.play() }
            "seek" -> player?.seekTo((a["ms"] as Number).toLong())
            "stop" -> player?.let {
                it.stop()
                it.clearMediaItems()
            }
            "track" -> selectTrack(a["type"] as String, a["id"] as String)
            "subSize" -> {
                subSize = (a["size"] as Number).toFloat()
                views.forEach { styleSubs(it) }
            }
            "fit" -> {
                val mode = when (a["mode"] as? String) {
                    "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                    "zoom" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
                views.forEach { it.resizeMode = mode }
            }
        }
    }

    private fun selectTrack(type: String, id: String) {
        val p = player ?: return
        val tt = when (type) {
            "audio" -> C.TRACK_TYPE_AUDIO
            "sub" -> C.TRACK_TYPE_TEXT
            else -> C.TRACK_TYPE_VIDEO
        }
        val b = p.trackSelectionParameters.buildUpon()
        when (id) {
            "off" -> b.setTrackTypeDisabled(tt, true)
            "auto" -> b.setTrackTypeDisabled(tt, false).clearOverridesOfType(tt)
            else -> {
                val parts = id.split(":")
                val g = p.currentTracks.groups[parts[0].toInt()]
                b.setTrackTypeDisabled(tt, false)
                    .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, parts[1].toInt()))
            }
        }
        p.trackSelectionParameters = b.build()
    }

    private fun send(m: Map<String, Any?>) {
        try {
            sink?.success(m)
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    private fun sendPos() {
        val p = player ?: return
        val dur = p.duration
        send(
            mapOf(
                "t" to "pos",
                "pos" to p.currentPosition,
                "dur" to (if (dur == C.TIME_UNSET || dur < 0) 0L else dur),
                "buf" to p.bufferedPosition,
                "playing" to p.isPlaying,
                "buffering" to (p.playbackState == Player.STATE_BUFFERING),
            ),
        )
    }

    private fun sendTracks(tracks: Tracks) {
        val p = player ?: return
        val list = ArrayList<Map<String, Any?>>()
        tracks.groups.forEachIndexed { gi, g ->
            val type = when (g.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "sub"
                C.TRACK_TYPE_VIDEO -> "video"
                else -> null
            } ?: return@forEachIndexed
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                list.add(
                    mapOf(
                        "type" to type,
                        "id" to "$gi:$i",
                        "label" to f.label,
                        "lang" to f.language,
                        "h" to (if (f.height > 0) f.height else null),
                        "codec" to (f.sampleMimeType ?: f.codecs),
                        "ch" to (if (f.channelCount > 0) f.channelCount else null),
                        "sel" to g.isTrackSelected(i),
                    ),
                )
            }
        }
        val disabled = p.trackSelectionParameters.disabledTrackTypes
        send(
            mapOf(
                "t" to "tracks",
                "list" to list,
                "subOff" to disabled.contains(C.TRACK_TYPE_TEXT),
            ),
        )
    }

    override fun onTracksChanged(tracks: Tracks) {
        tracksSeq++
        sendTracks(tracks)
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        sendPos()
        if (playbackState == Player.STATE_ENDED) {
            endedSeq++
            send(mapOf("t" to "ended"))
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) = sendPos()

    override fun onPlayerError(error: PlaybackException) {
        val p = player
        if (p != null && error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            p.seekToDefaultPosition()
            p.prepare()
            return
        }
        errorSeq++
        lastError = "${error.errorCodeName}: ${error.message}"
        send(mapOf("t" to "error", "msg" to lastError))
    }

    fun styleSubs(v: PlayerView) {
        val s = v.subtitleView ?: return
        s.setApplyEmbeddedStyles(false)
        s.setApplyEmbeddedFontSizes(false)
        s.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                Color.TRANSPARENT,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                Color.BLACK,
                null,
            ),
        )
        s.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, subSize)
        s.setBottomPaddingFraction(0.06f)
    }

    object VideoFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val v = PlayerView(context)
            v.useController = false
            v.setShutterBackgroundColor(Color.BLACK)
            v.setBackgroundColor(Color.BLACK)
            v.setKeepContentOnPlayerReset(true)
            v.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            v.isFocusable = false
            v.isFocusableInTouchMode = false
            v.descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
            QzPlayer.styleSubs(v)
            v.player = QzPlayer.ensure()
            QzPlayer.views.add(v)
            return object : PlatformView {
                override fun getView(): View = v

                override fun dispose() {
                    v.player = null
                    QzPlayer.views.remove(v)
                }
            }
        }
    }
}

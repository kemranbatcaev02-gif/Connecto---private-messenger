package com.example.app

import android.app.KeyguardManager
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 1) Смена иконки приложения: в AndroidManifest у каждой иконки свой activity-alias
 *    (.IconClassic, .IconNeon …), включён ровно один. Выбор из Flutter запоминаем
 *    и применяем, когда приложение уходит в фон — так лаунчер не закрывает приложение.
 * 2) Звонки (канал connecto/call): рингтон и вибрация, гудки, экран не гаснет,
 *    показ поверх блокировки, датчик приближения, сервис идущего звонка,
 *    картинка-в-картинке для видеозвонка.
 */
class MainActivity : FlutterActivity() {
    private val icons = listOf(
        "classic", "night", "light", "neon", "gold",
        "glass", "space", "sakura", "lava", "aurora"
    )
    private var pending: String? = null

    private var callChannel: MethodChannel? = null
    private var ringer: MediaPlayer? = null
    private var vibrating = false
    private var toneGen: ToneGenerator? = null
    private var proximityLock: PowerManager.WakeLock? = null
    private var pipAllowed = false
    private var pipRatio = Rational(9, 16)

    private fun alias(id: String): ComponentName {
        val base = MainActivity::class.java.name.substringBeforeLast('.')
        return ComponentName(this, "$base.Icon${id.replaceFirstChar { it.uppercase() }}")
    }

    private fun current(): String {
        val pm = packageManager
        for (id in icons) {
            val state = pm.getComponentEnabledSetting(alias(id))
            val enabled = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && id == "classic")
            if (enabled) return id
        }
        return "classic"
    }

    private fun apply(id: String) {
        if (id == current()) return
        val pm = packageManager
        // сначала включаем новую, потом выключаем остальные — чтобы иконка не пропала совсем
        pm.setComponentEnabledSetting(
            alias(id),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        for (other in icons) {
            if (other == id) continue
            pm.setComponentEnabledSetting(
                alias(other),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "connecto/app_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(pending ?: current())
                    "set" -> {
                        val id = call.argument<String>("id")
                        if (id == null || id !in icons) {
                            result.error("bad_icon", "Неизвестная иконка", null)
                        } else {
                            pending = if (id == current()) null else id
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "connecto/call")
        callChannel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ring" -> {
                        if (call.argument<Boolean>("on") == true) {
                            startRing(call.argument<Boolean>("sound") != false,
                                call.argument<Boolean>("vibrate") != false)
                        } else {
                            stopRing()
                        }
                        result.success(true)
                    }
                    "tone" -> {
                        tone(call.argument<String>("kind") ?: "none")
                        result.success(true)
                    }
                    "keepOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(true)
                    }
                    "lockScreen" -> {
                        showOverLock(call.argument<Boolean>("on") == true)
                        result.success(true)
                    }
                    "proximity" -> {
                        setProximity(call.argument<Boolean>("on") == true)
                        result.success(true)
                    }
                    "service" -> {
                        if (call.argument<Boolean>("on") == true) {
                            val i = Intent(this, CallService::class.java).apply {
                                putExtra("title", call.argument<String>("title") ?: "Connecto")
                                putExtra("text", call.argument<String>("text") ?: "Идёт звонок")
                                putExtra("since", (call.argument<Number>("since") ?: System.currentTimeMillis()).toLong())
                                putExtra("mic", call.argument<Boolean>("mic") != false)
                                putExtra("camera", call.argument<Boolean>("camera") == true)
                                putExtra("screen", call.argument<Boolean>("screen") == true)
                            }
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                        } else {
                            val i = Intent(this, CallService::class.java).apply {
                                action = CallService.ACTION_STOP
                            }
                            try {
                                startService(i)
                            } catch (e: Exception) {
                                stopService(Intent(this, CallService::class.java))
                            }
                        }
                        result.success(true)
                    }
                    "pip" -> {
                        pipAllowed = call.argument<Boolean>("on") == true
                        val w = call.argument<Int>("w") ?: 9
                        val h = call.argument<Int>("h") ?: 16
                        pipRatio = Rational(w.coerceIn(1, 100), h.coerceIn(1, 100))
                        updatePipParams()
                        result.success(Build.VERSION.SDK_INT >= 26)
                    }
                    "enterPip" -> result.success(enterPip())
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    "dismissKeyguard" -> {
                        if (Build.VERSION.SDK_INT >= 26) {
                            val km = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
                            if (km.isKeyguardLocked) km.requestDismissKeyguard(this, null)
                        }
                        result.success(true)
                    }
                    "requestBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("call_native", e.message, null)
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        if (i?.action == CallService.ACTION_END) {
            i.action = null
            callChannel?.invokeMethod("endCall", null)
        }
    }

    // ── рингтон входящего ──

    private fun startRing(sound: Boolean, vibrate: Boolean) {
        stopRing()
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val mode = am.ringerMode
        if (sound && mode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                val mp = MediaPlayer()
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                mp.setDataSource(this, uri)
                mp.isLooping = true
                mp.prepare()
                mp.start()
                ringer = mp
            } catch (e: Exception) {
                ringer = null
            }
        }
        if (vibrate && mode != AudioManager.RINGER_MODE_SILENT) {
            try {
                @Suppress("DEPRECATION")
                val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
                val pattern = longArrayOf(0, 900, 1100)
                if (Build.VERSION.SDK_INT >= 26) {
                    v.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } else {
                    legacyVibrate(v, pattern)
                }
                vibrating = true
            } catch (e: Exception) {
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyVibrate(v: Vibrator, pattern: LongArray) {
        v.vibrate(pattern, 0)
    }

    private fun stopRing() {
        try {
            ringer?.stop()
        } catch (e: Exception) {
        }
        try {
            ringer?.release()
        } catch (e: Exception) {
        }
        ringer = null
        if (vibrating) {
            try {
                @Suppress("DEPRECATION")
                val vib = getSystemService(VIBRATOR_SERVICE) as Vibrator
                vib.cancel()
            } catch (e: Exception) {
            }
            vibrating = false
        }
    }

    // ── гудки: «вызов», «занято», короткие сигналы ──

    private fun tone(kind: String) {
        try {
            toneGen?.stopTone()
            toneGen?.release()
        } catch (e: Exception) {
        }
        toneGen = null
        val type = when (kind) {
            "ringback" -> ToneGenerator.TONE_SUP_RINGTONE
            "busy" -> ToneGenerator.TONE_SUP_BUSY
            "end" -> ToneGenerator.TONE_PROP_PROMPT
            "connect" -> ToneGenerator.TONE_PROP_BEEP2
            else -> return
        }
        val duration = when (kind) {
            "ringback" -> -1
            "busy" -> 2600
            else -> 300
        }
        try {
            val g = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 55)
            g.startTone(type, duration)
            toneGen = g
        } catch (e: Exception) {
        }
    }

    // ── экран ──

    private fun showOverLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            legacyLockFlags(on)
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyLockFlags(on: Boolean) {
        val f = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        if (on) window.addFlags(f) else window.clearFlags(f)
    }

    private fun setProximity(on: Boolean) {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (on) {
            if (proximityLock == null &&
                pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                val lock = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "connecto:proximity")
                lock.setReferenceCounted(false)
                lock.acquire(4 * 60 * 60 * 1000L)
                proximityLock = lock
            }
        } else {
            val lock = proximityLock
            proximityLock = null
            try {
                if (lock != null && lock.isHeld) {
                    lock.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
                }
            } catch (e: Exception) {
            }
        }
    }

    // ── картинка в картинке (видеозвонок, когда сворачиваешь приложение) ──

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT >= 31) {
            try {
                setPictureInPictureParams(
                    PictureInPictureParams.Builder()
                        .setAspectRatio(pipRatio)
                        .setAutoEnterEnabled(pipAllowed)
                        .setSeamlessResizeEnabled(true)
                        .build()
                )
            } catch (e: Exception) {
            }
        }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        if (isInPictureInPictureMode) return true
        return try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(pipRatio).build()
            )
        } catch (e: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed && Build.VERSION.SDK_INT in 26..30) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callChannel?.invokeMethod("pip", mapOf("on" to isInPictureInPictureMode))
    }

    override fun onStop() {
        super.onStop()
        val id = pending ?: return
        pending = null
        try {
            apply(id)
        } catch (e: Exception) {
        }
    }

    override fun onDestroy() {
        stopRing()
        tone("none")
        setProximity(false)
        if (isFinishing) {
            // приложение закрыли совсем — уведомление «идёт звонок» больше не нужно
            try {
                stopService(Intent(this, CallService::class.java))
            } catch (e: Exception) {
            }
        }
        super.onDestroy()
    }
}

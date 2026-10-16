package com.example.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder

/**
 * Идущий звонок. Android не даёт свёрнутому приложению пользоваться микрофоном,
 * камерой и захватом экрана без такого сервиса — поэтому на время звонка
 * висит уведомление «Звонок · Имя» с таймером и кнопкой «Завершить».
 */
class CallService : Service() {
    companion object {
        const val ACTION_STOP = "connecto.CALL_STOP"
        const val ACTION_END = "connecto.END_CALL"
        private const val CHANNEL = "calls_ongoing"
        private const val NOTIF_ID = 4201
    }

    private var running = false // уже в режиме переднего плана

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == ACTION_STOP) {
            stopNow()
            return START_NOT_STICKY
        }
        val title = intent.getStringExtra("title") ?: "Connecto"
        val text = intent.getStringExtra("text") ?: "Идёт звонок"
        val since = intent.getLongExtra("since", System.currentTimeMillis())
        val mic = intent.getBooleanExtra("mic", true)
        val camera = intent.getBooleanExtra("camera", false)
        val screen = intent.getBooleanExtra("screen", false)
        val notification = build(title, text, since)

        if (Build.VERSION.SDK_INT >= 30) {
            // пробуем от полного набора к меньшему: без разрешения на камеру
            // Android 14 не даст запустить сервис с типом «камера»
            val attempts = mutableListOf<Int>()
            var full = 0
            if (mic) full = full or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (camera) full = full or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (screen) full = full or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            attempts.add(full)
            if (screen) attempts.add(ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                (if (mic) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0))
            if (mic) attempts.add(ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            var started = false
            for (type in attempts) {
                if (type == 0) continue
                try {
                    startForeground(NOTIF_ID, notification, type)
                    started = true
                    break
                } catch (e: Exception) {
                }
            }
            if (started) {
                running = true
            } else if (!running) {
                stopSelf()
                return START_NOT_STICKY
            }
            // уже работали — оставляем прежние разрешения (например, микрофон), не рвём звонок
        } else if (Build.VERSION.SDK_INT == 29) {
            try {
                if (screen) {
                    startForeground(NOTIF_ID, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
                } else {
                    startForeground(NOTIF_ID, notification)
                }
                running = true
            } catch (e: Exception) {
                if (!running) {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        } else {
            try {
                startForeground(NOTIF_ID, notification)
                running = true
            } catch (e: Exception) {
                if (!running) {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun stopNow() {
        running = false
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
        }
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // приложение смахнули из списка задач — звонок заканчивается вместе с ним
        stopNow()
        super.onTaskRemoved(rootIntent)
    }

    private fun build(title: String, text: String, since: Long): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        val openPi = PendingIntent.getActivity(this, 1, open, flags)
        val end = Intent(this, MainActivity::class.java).apply {
            action = ACTION_END
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        val endPi = PendingIntent.getActivity(this, 2, end, flags)

        val builder: Notification.Builder = if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val ch = NotificationChannel(CHANNEL, "Идущий звонок", NotificationManager.IMPORTANCE_LOW)
                ch.description = "Уведомление во время звонка"
                ch.setSound(null, null)
                ch.enableVibration(false)
                nm.createNotificationChannel(ch)
            }
            Notification.Builder(this, CHANNEL)
        } else {
            legacyBuilder()
        }
        builder
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setShowWhen(true)
            .setWhen(since)
            .setUsesChronometer(true)
            .setContentIntent(openPi)
            .setCategory(Notification.CATEGORY_CALL)
        val noIcon: Icon? = null
        builder.addAction(Notification.Action.Builder(noIcon, "Завершить", endPi).build())
        return builder.build()
    }

    @Suppress("DEPRECATION")
    private fun legacyBuilder(): Notification.Builder =
        Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
}

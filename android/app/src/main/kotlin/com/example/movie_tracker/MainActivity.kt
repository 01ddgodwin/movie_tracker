package com.example.movie_tracker

import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import com.example.live_activities.LiveActivityManager
import com.example.live_activities.LiveActivityManagerHolder

// This class keeps the background engine alive independently of the UI
class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Bind the layout manager to the application lifecycle
        LiveActivityManagerHolder.instance = CustomLiveActivityManager(this)
    }
}

class CustomLiveActivityManager(context: Context) : LiveActivityManager(context) {
    private val mContext = context 
    private val remoteViews = RemoteViews(context.packageName, R.layout.live_activity)

    override suspend fun buildNotification(
        notification: Notification.Builder,
        event: String,
        data: Map<String, Any>
    ): Notification {
        Log.d("MOVIE_NATIVE", "=== KOTLIN TRIGGERED ===")
        
        // 1. Setup High-Importance Channel for Always-On Display (AOD)
        val channelId = "live_activity_channel"
        val notificationManager = mContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, 
                "Movie Live Tracking", 
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows real-time movie progress on lock screen"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }

        val title = data["title"] as? String ?: "Movie"
        val body = data["body"] as? String ?: ""
        val progress = (data["progress"] as? Number)?.toDouble() ?: 0.0

        try {
            remoteViews.setTextViewText(R.id.movie_title, "🎬 $title")
            remoteViews.setTextViewText(R.id.status_text, body)

            val segments = arrayOf(R.id.seg1, R.id.seg2, R.id.seg3, R.id.seg4, R.id.seg5)
            for (seg in segments) {
                remoteViews.setInt(seg, "setBackgroundColor", Color.parseColor("#333333"))
            }

            // 2. Safe progress handling to prevent UI overflows
            val safeProgress = progress.coerceIn(0.0, 100.0)
            val activeCount = (safeProgress / 20).toInt()
            for (i in 0 until activeCount) {
                if (i < segments.size) {
                    remoteViews.setInt(segments[i], "setBackgroundColor", Color.parseColor("#E50914"))
                }
            }
        } catch (e: Exception) {
            Log.e("MOVIE_NATIVE", "XML PAINT CRASH: ${e.message}")
        }

        val intent = Intent(mContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            mContext, 200, intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Close button logic
        val dismissIntent = Intent(mContext, LiveActivityManager::class.java).apply {
            action = "END_ACTIVITY" 
        }
        val dismissPendingIntent = PendingIntent.getBroadcast(
            mContext, 300, dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        remoteViews.setOnClickPendingIntent(R.id.btn_close, dismissPendingIntent)

        // 3. Final build with Category Progress for high-priority background delivery
        val finalNotification = notification
            .setChannelId(channelId)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(remoteViews)
            .setContentIntent(pendingIntent)
            .setSmallIcon(R.drawable.notification_icon)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_MAX) 
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()

        Log.d("MOVIE_NATIVE", "=== HANDING OFF TO ANDROID OS ===")
        return finalNotification
    }
}

class MainActivity: FlutterActivity() {
    // Background management is handled by MainApplication
}
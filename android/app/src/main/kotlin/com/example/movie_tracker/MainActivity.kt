package com.example.movie_tracker

import android.app.Application
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.live_activities.LiveActivityManager
import com.example.live_activities.LiveActivityManagerHolder

// This class stays alive in the background to handle the "headless" alarms
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

            val activeCount = (progress / 20).toInt()
            for (i in 0 until activeCount) {
                remoteViews.setInt(segments[i], "setBackgroundColor", Color.parseColor("#E50914"))
            }
        } catch (e: Exception) {
            Log.e("MOVIE_NATIVE", "XML PAINT CRASH: ${e.message}")
        }

        // CRITICAL FIX: Application context requires NEW_TASK to open the activity from background
        val intent = Intent(mContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        
        val pendingIntent = PendingIntent.getActivity(
            mContext, 
            200, 
            intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Setup the "X" button to dismiss the notification
        val dismissIntent = Intent(mContext, LiveActivityManager::class.java).apply {
            action = "END_ACTIVITY" 
        }
        val dismissPendingIntent = PendingIntent.getBroadcast(
            mContext,
            300,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        remoteViews.setOnClickPendingIntent(R.id.btn_close, dismissPendingIntent)

        return notification
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(remoteViews)
            .setCustomBigContentView(remoteViews)
            .setContentIntent(pendingIntent)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
    }
}

class MainActivity: FlutterActivity() {
    // Initialization is now handled by MainApplication
}
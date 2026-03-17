import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:live_activities/live_activities.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- BACKGROUND WORKER ---
// This MUST remain a top-level function so the Android background service can find it.
@pragma('vm:entry-point')
void updateLiveActivityBackground(int alarmId) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final dataStr = prefs.getString('alarm_$alarmId');

    if (dataStr != null) {
      final data = jsonDecode(dataStr);

      final startTime = DateTime.parse(data['startTimeIso']);
      final runtime = data['runtimeMinutes'] as int;
      final now = DateTime.now();

      // Calculate the fresh countdown time right as the background task runs
      final int minsUntil = startTime.difference(now).inMinutes;
      String timeStatus;
      if (minsUntil > 0) {
        timeStatus = "In $minsUntil min";
      } else if (minsUntil > -runtime) {
        timeStatus = "Playing Now";
      } else {
        timeStatus = "Finished";
      }

      final displayTitle = "${data['baseTitle']} ($timeStatus)";

      // Boot up the native plugin in the background
      final plugin = LiveActivities();
      await plugin.init(appGroupId: "YOUR_GROUP_ID");

      await plugin.createOrUpdateActivity(data['activityId'], {
        'title': displayTitle,
        'body': data['body'],
        'progress': data['progress'],
      });
    }
  } catch (e) {
    debugPrint("Background Alarm Error: $e");
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _liveActivitiesPlugin = LiveActivities();

  Future<void> init() async {
    await _liveActivitiesPlugin.init(appGroupId: "YOUR_GROUP_ID");
  }

  Future<void> scheduleMovieFlow(
    Map<String, dynamic> item,
    int runtimeMinutes,
  ) async {
    try {
      final String rawDate = item['date'] ?? "Unknown";
      final String rawTime = item['time'] ?? "Unknown";

      final DateTime movieStartTime = _parseDateTime(rawDate, rawTime);
      final DateTime now = DateTime.now();

      final String baseTitle = item['title'] ?? "Movie";
      final String activityId = item['id'].toString();

      // 1. Calculate time remaining for the immediate layout
      final int minsUntil = movieStartTime.difference(now).inMinutes;
      String timeStatus;
      if (minsUntil > 0) {
        timeStatus = "In $minsUntil min";
      } else if (minsUntil > -runtimeMinutes) {
        timeStatus = "Playing Now";
      } else {
        timeStatus = "Finished";
      }
      final String displayTitle = "$baseTitle ($timeStatus)";

      final List<Map<String, dynamic>> phases = [
        {
          'time': movieStartTime.subtract(const Duration(minutes: 60)),
          'body': "Time to get ready! 🚿",
          'progress': 20.0,
        },
        {
          'time': movieStartTime.subtract(const Duration(minutes: 15)),
          'body': "Grab the popcorn & soda! 🍿🥤",
          'progress': 40.0,
        },
        {
          'time': movieStartTime.subtract(const Duration(minutes: 5)),
          'body': "Dimming lights... find your seat! 🛋️",
          'progress': 60.0,
        },
        {
          'time': movieStartTime,
          'body': "Enjoy the show! 🤫",
          'progress': 80.0,
        },
        {
          'time': movieStartTime.add(Duration(minutes: runtimeMinutes)),
          'body': "Credits rolling. Don't forget your trash! 🚮",
          'progress': 100.0,
        },
      ];

      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? currentActivePhase;
      int phaseIndex = 0;

      for (var phase in phases) {
        final DateTime phaseTime = phase['time'] as DateTime;

        if (now.isAfter(phaseTime)) {
          // Keep updating the current active phase as we loop through the past ones
          currentActivePhase = phase;
        } else {
          // --- SCHEDULE BACKGROUND ALARM FOR FUTURE PHASES ---
          final int alarmId = (item['id'].hashCode + phaseIndex).abs() % 100000;

          final alarmData = {
            'activityId': activityId,
            'baseTitle': baseTitle,
            'startTimeIso': movieStartTime.toIso8601String(),
            'runtimeMinutes': runtimeMinutes,
            'body': phase['body'],
            'progress': phase['progress'],
          };

          await prefs.setString('alarm_$alarmId', jsonEncode(alarmData));

          await AndroidAlarmManager.oneShotAt(
            phaseTime,
            alarmId,
            updateLiveActivityBackground,
            exact: true,
            wakeup: true,
            allowWhileIdle: true,
          );
        }
        phaseIndex++;
      }

      // --- ONLY PAINT IF WITHIN 1 HOUR OF SHOWTIME ---
      if (currentActivePhase != null) {
        await updateLiveActivity(
          activityId,
          displayTitle,
          currentActivePhase['body'] as String,
          currentActivePhase['progress'] as double,
        );
      } else {
        // Automatically clears the lock screen widget if it isn't time yet
        await _liveActivitiesPlugin.endActivity(activityId);
      }
    } catch (e) {
      debugPrint("Notification Flow Error: $e");
    }
  }

  Future<void> updateLiveActivity(
    String activityId,
    String title,
    String body,
    double progress,
  ) async {
    final Map<String, dynamic> activityModel = {
      'title': title,
      'body': body,
      'progress': progress,
    };

    await _liveActivitiesPlugin.createOrUpdateActivity(
      activityId,
      activityModel,
    );
  }

  DateTime _parseDateTime(String dateStr, String timeStr) {
    const int currentYear = 2026;
    String cleanDate = dateStr.trim();
    String cleanTime = timeStr.trim().toUpperCase();

    try {
      DateTime d;
      try {
        d = DateFormat('MMMM d, yyyy').parse(cleanDate);
      } catch (_) {
        try {
          d = DateFormat('M/d/yyyy').parse(cleanDate);
        } catch (_) {
          d = DateTime.now();
        }
      }

      int hour = 0;
      int minute = 0;
      final RegExp timeRegex = RegExp(r'(\d+):(\d+)\s*(AM|PM)?');
      final match = timeRegex.firstMatch(cleanTime);

      if (match != null) {
        hour = int.parse(match.group(1)!);
        minute = int.parse(match.group(2)!);
        String? period = match.group(3);
        if (period == "PM" && hour < 12) hour += 12;
        if (period == "AM" && hour == 12) hour = 0;
      }
      return DateTime(currentYear, d.month, d.day, hour, minute, 0, 0, 0);
    } catch (e) {
      return DateTime.now().add(const Duration(days: 1));
    }
  }
}

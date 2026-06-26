import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 封裝本地通知,並處理各平台差異。
///
/// 重要平台差異:`zonedSchedule`(排程通知)在 iOS / Android / macOS 支援,
/// 但 **Windows 不支援**(無 scheduler API)。因此:
///   - 排程通知(App 關閉也會響):僅 iOS / Android / macOS。
///   - Windows:只在 App 執行中由前景計時器呼叫 [showNow]。
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 共用單一通知 ID:確保前景立即通知與排程通知不會重複堆疊。
  static const int _notificationId = 1001;

  static const String _channelId = 'timer_done';
  static const String _channelName = '計時完成';

  bool _initialized = false;

  /// 此平台是否支援排程通知(App 關閉也會響)。
  bool get supportsScheduling =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> init() async {
    if (_initialized) return;

    // 設定 timezone 資料庫與本地時區,供 zonedSchedule 使用。
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 取不到時退回 UTC,避免崩潰。
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final windows = WindowsInitializationSettings(
      appName: 'Cross Platform Alarm',
      appUserModelId: 'com.philio.crossPlatformAlarm',
      // 固定 GUID,用於 Windows 通知啟動回呼識別。
      guid: '5d4f3c2b-1a09-4e8d-9b7a-6c5d4e3f2a10',
    );

    await _plugin.initialize(
      InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        windows: windows,
      ),
    );

    _initialized = true;
  }

  /// 請求通知權限(iOS / macOS / Android 13+)。在 App 啟動後呼叫。
  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        break;
      case TargetPlatform.macOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        break;
      case TargetPlatform.android:
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        break;
      default:
        break;
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '倒數計時時間到的通知',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      );

  /// 在指定的絕對時間排程通知(App 關閉也會響)。Windows 上會略過(回 false)。
  /// 回傳是否成功排程。
  Future<bool> scheduleAt(DateTime deadline,
      {String title = '時間到!', String body = '倒數計時結束'}) async {
    await init();
    if (!supportsScheduling) return false;

    final when = tz.TZDateTime.from(deadline, tz.local);
    // 已過期的時間不排程。
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return false;

    await _plugin.zonedSchedule(
      _notificationId,
      title,
      body,
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    return true;
  }

  /// 立即顯示通知(前景計時器數到 0 時,以及 Windows 使用)。
  Future<void> showNow(
      {String title = '時間到!', String body = '倒數計時結束'}) async {
    await init();
    await _plugin.show(_notificationId, title, body, _details);
  }

  /// 取消所有(此 App 的單一)通知。deadline 被清除或變更時呼叫。
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancel(_notificationId);
  }
}

/// The Android side of the daily report that never opens anything on screen:
/// writing to the chosen folder (Storage Access Framework) or to
/// Downloads/Souqi/Reports (MediaStore), WorkManager scheduling, the
/// notification, and the job's status.
///
/// It is usable from the BACKGROUND engine that WorkManager starts — no
/// activity, no Riverpod. What does open something (the folder picker, the
/// share sheet, a file manager, the battery settings) is on `NativeBridge`,
/// where the PIN locks are told about it first.
///
/// The Android half: android/app/src/main/kotlin/com/souqi/souqi/
/// ReportChannel.kt and its neighbours.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// Where report files go. [treeUri] null = Download/Souqi/Reports.
class ReportDestination {
  const ReportDestination.folder(String this.treeUri);

  const ReportDestination.downloads() : treeUri = null;

  final String? treeUri;

  bool get isDownloads => treeUri == null;

  Map<String, Object?> toArgs() => {'uri': treeUri};

  @override
  bool operator ==(Object other) =>
      other is ReportDestination && other.treeUri == treeUri;

  @override
  int get hashCode => treeUri.hashCode;
}

/// The folder is gone: its permission was revoked, the SD card or USB drive
/// is out, the cloud app was removed.
class ReportDestinationUnavailable implements Exception {
  const ReportDestinationUnavailable([this.detail]);

  final String? detail;

  @override
  String toString() => 'ReportDestinationUnavailable($detail)';
}

/// The folder is there but a file could not be written (full, read-only…).
class ReportWriteFailed implements Exception {
  const ReportWriteFailed([this.detail]);

  final String? detail;

  @override
  String toString() => 'ReportWriteFailed($detail)';
}

/// The one notification the job posts (a new one replaces the last).
class ReportNotice {
  const ReportNotice({
    required this.channelName,
    required this.title,
    required this.text,
    required this.publicTitle,
    this.shareLabel,
    this.openFolderLabel,
  });

  /// The name of the notification channel in the phone's settings.
  final String channelName;
  final String title;
  final String text;

  /// What the LOCK SCREEN shows instead: the text names customers' debts.
  final String publicTitle;

  /// The two actions; null leaves an action out.
  final String? shareLabel;
  final String? openFolderLabel;

  Map<String, Object?> toArgs() => {
        'channelName': channelName,
        'title': title,
        'text': text,
        'publicTitle': publicTitle,
        'shareLabel': shareLabel,
        'openFolderLabel': openFolderLabel,
      };
}

/// What tapping the notification (or one of its actions) asks the app to do.
enum ReportLaunchAction {
  /// The notification itself: the debtors list.
  openDebtors('debtors'),
  share('share'),
  openFolder('folder');

  const ReportLaunchAction(this.wire);

  final String wire;

  static ReportLaunchAction? fromWire(Object? value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

abstract class ReportPlatform {
  /// One run at a time across BOTH engines (the app's and WorkManager's):
  /// false while another run holds the lock.
  Future<bool> tryBeginRun();

  Future<void> endRun();

  /// The chosen folder can still be written to: its permission is held and
  /// the storage behind it answers.
  Future<bool> folderAvailable(String treeUri);

  /// Copies the file at [sourcePath] into [destination] as [name],
  /// OVERWRITING a file of that name. Returns where it went, to show.
  /// Throws [ReportDestinationUnavailable] or [ReportWriteFailed].
  Future<String> writeFile(
    ReportDestination destination, {
    required String name,
    required String sourcePath,
    required String mimeType,
  });

  /// The names of the files in [destination] (for the keep-N rule).
  Future<List<String>> listFiles(ReportDestination destination);

  Future<void> deleteFile(ReportDestination destination, String name);

  /// Gives up the persisted permission of a folder no longer used.
  Future<void> releaseFolder(String treeUri);

  /// Daily at [minuteOfDay] (WorkManager). [replace] re-plans even when a
  /// run is already planned for that time.
  Future<void> schedule(int minuteOfDay, {bool replace = false});

  Future<void> cancelSchedule();

  Future<void> showNotice(ReportNotice notice);

  Future<bool> notificationsAllowed();

  Future<bool> batteryOptimizationIgnored();

  /// The job's status, kept by Android (SharedPreferences) — not in the
  /// database, which the background engine only reads.
  Future<Map<String, Object?>?> loadStatus();

  Future<void> saveStatus(Map<String, Object?> status);

  /// The notification action the app was opened with, once.
  Future<ReportLaunchAction?> takeLaunchAction();

  /// Called when the app is opened from the notification while it is
  /// already running, and when the background job has finished.
  void setListener({
    void Function()? onLaunchAction,
    void Function()? onJobFinished,
  });

  /// Background engine only: tells WorkManager's worker it may end.
  Future<void> workerFinished();
}

class MethodChannelReportPlatform implements ReportPlatform {
  const MethodChannelReportPlatform();

  static const _channel = MethodChannel('souqi/report');

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'UNAVAILABLE':
          throw ReportDestinationUnavailable(e.message);
        case 'WRITE_FAILED':
          throw ReportWriteFailed(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<bool> tryBeginRun() async => await _call<bool>('tryBeginRun') ?? false;

  @override
  Future<void> endRun() => _call<void>('endRun');

  @override
  Future<bool> folderAvailable(String treeUri) async =>
      await _call<bool>('folderAvailable', {'uri': treeUri}) ?? false;

  @override
  Future<String> writeFile(
    ReportDestination destination, {
    required String name,
    required String sourcePath,
    required String mimeType,
  }) async =>
      await _call<String>('writeFile', {
        ...destination.toArgs(),
        'name': name,
        'path': sourcePath,
        'mimeType': mimeType,
      }) ??
      name;

  @override
  Future<List<String>> listFiles(ReportDestination destination) async {
    final list =
        await _call<List<Object?>>('listFiles', destination.toArgs()) ?? [];
    return list.whereType<String>().toList();
  }

  @override
  Future<void> deleteFile(ReportDestination destination, String name) =>
      _call<void>('deleteFile', {...destination.toArgs(), 'name': name});

  @override
  Future<void> releaseFolder(String treeUri) =>
      _call<void>('releaseFolder', {'uri': treeUri});

  @override
  Future<void> schedule(int minuteOfDay, {bool replace = false}) =>
      _call<void>('schedule', {'minute': minuteOfDay, 'replace': replace});

  @override
  Future<void> cancelSchedule() => _call<void>('cancelSchedule');

  @override
  Future<void> showNotice(ReportNotice notice) =>
      _call<void>('notify', notice.toArgs());

  @override
  Future<bool> notificationsAllowed() async =>
      await _call<bool>('notificationsAllowed') ?? false;

  @override
  Future<bool> batteryOptimizationIgnored() async =>
      await _call<bool>('batteryOptimizationIgnored') ?? false;

  @override
  Future<Map<String, Object?>?> loadStatus() async {
    final raw = await _call<String>('loadStatus');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveStatus(Map<String, Object?> status) =>
      _call<void>('saveStatus', {'json': jsonEncode(status)});

  @override
  Future<ReportLaunchAction?> takeLaunchAction() async =>
      ReportLaunchAction.fromWire(await _call<String>('takeLaunchAction'));

  @override
  void setListener({
    void Function()? onLaunchAction,
    void Function()? onJobFinished,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'launchAction':
          onLaunchAction?.call();
        case 'jobFinished':
          onJobFinished?.call();
      }
      return null;
    });
  }

  @override
  Future<void> workerFinished() => _call<void>('workerFinished');
}

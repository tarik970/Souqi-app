import 'dart:io';
import 'dart:typed_data';

import 'package:souqi/core/platform/report_platform.dart';
import 'package:souqi/features/debts/report/debt_report_pdf.dart';

/// The Android side of the daily report, in memory: folders are maps of
/// file name → bytes (the `null` key is Download/Souqi/Reports).
class FakeReportPlatform implements ReportPlatform {
  final folders = <String?, Map<String, Uint8List>>{};

  /// The chosen folder answers (its permission is held, the card is in).
  bool folderOk = true;

  /// Writes to the chosen folder fail although it answers (full…).
  bool folderWritesFail = false;
  bool downloadsFail = false;

  bool locked = false;
  Map<String, Object?>? status;
  final notices = <ReportNotice>[];
  final schedules = <({int minute, bool replace})>[];
  int cancels = 0;
  final released = <String>[];
  bool notifications = true;
  bool batteryExempt = true;
  ReportLaunchAction? launch;
  int workerFinishedCalls = 0;

  static const downloadsLabel = 'Download/Souqi/Reports';

  Map<String, Uint8List> folder(String? uri) => folders.putIfAbsent(uri, () => {});

  @override
  Future<bool> tryBeginRun() async {
    if (locked) return false;
    locked = true;
    return true;
  }

  @override
  Future<void> endRun() async => locked = false;

  @override
  Future<bool> folderAvailable(String treeUri) async => folderOk;

  @override
  Future<String> writeFile(
    ReportDestination destination, {
    required String name,
    required String sourcePath,
    required String mimeType,
  }) async {
    if (destination.isDownloads) {
      if (downloadsFail) throw const ReportWriteFailed('downloads');
    } else {
      if (!folderOk) throw const ReportDestinationUnavailable('gone');
      if (folderWritesFail) throw const ReportWriteFailed('full');
    }
    folder(destination.treeUri)[name] = File(sourcePath).readAsBytesSync();
    return destination.isDownloads ? downloadsLabel : 'Backup card';
  }

  @override
  Future<List<String>> listFiles(ReportDestination destination) async =>
      folder(destination.treeUri).keys.toList();

  @override
  Future<void> deleteFile(ReportDestination destination, String name) async =>
      folder(destination.treeUri).remove(name);

  @override
  Future<void> releaseFolder(String treeUri) async => released.add(treeUri);

  @override
  Future<void> schedule(int minuteOfDay, {bool replace = false}) async =>
      schedules.add((minute: minuteOfDay, replace: replace));

  @override
  Future<void> cancelSchedule() async => cancels++;

  @override
  Future<void> showNotice(ReportNotice notice) async => notices.add(notice);

  @override
  Future<bool> notificationsAllowed() async => notifications;

  @override
  Future<bool> batteryOptimizationIgnored() async => batteryExempt;

  @override
  Future<Map<String, Object?>?> loadStatus() async => status;

  @override
  Future<void> saveStatus(Map<String, Object?> value) async => status = value;

  @override
  Future<ReportLaunchAction?> takeLaunchAction() async {
    final action = launch;
    launch = null;
    return action;
  }

  @override
  void setListener({
    void Function()? onLaunchAction,
    void Function()? onJobFinished,
  }) {}

  @override
  Future<void> workerFinished() async => workerFinishedCalls++;
}

ByteData _bytes(String path) {
  final data = File(path).readAsBytesSync();
  return ByteData.sublistView(data);
}

/// The bundled fonts, read straight from the assets folder.
Future<ReportFonts> testReportFonts() async => ReportFonts.fromBytes(
      regular: _bytes(ReportFonts.regularAsset),
      bold: _bytes(ReportFonts.boldAsset),
    );

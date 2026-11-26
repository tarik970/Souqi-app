/// Wires [ErrorLog] to this Flutter engine: every error nobody caught ends
/// in the log file. Called first thing in `main()` and in the background
/// engine's entry point.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'error_log.dart';

/// Where the log files live: `<app files>/logs`. The Android side writes
/// its own crashes to the same folder (CrashLog.kt, `errors-native.log`).
Future<Directory> errorLogDirectory() async =>
    Directory(p.join((await getApplicationSupportDirectory()).path, 'logs'));

/// Starts the error log of this engine ([engine] = `app` or `worker`) and
/// takes over the two places an uncaught error arrives at:
///
/// - [FlutterError.onError]: errors inside the framework's callbacks —
///   build, layout, paint, gestures. The previous handler still runs (in a
///   debug build it prints the red-screen report to the console).
/// - [PlatformDispatcher.onError]: everything else — an exception in a
///   Future nobody awaited, a timer, a platform-channel reply.
///
/// Never throws: a phone on which the log cannot start still runs the app.
Future<void> startErrorLog({String engine = 'app'}) async {
  try {
    ErrorLog.instance.init(
      directory: await errorLogDirectory(),
      appVersion: '?',
      engine: engine,
    );
  } on Object {
    // No storage path from the platform: no log, the app goes on.
  }

  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    // "Silent" errors are ones the framework itself handles and only
    // mentions (an image that failed to decode).
    if (details.silent) return;
    final library = details.library;
    ErrorLog.instance.record(
      details.exception,
      details.stack,
      context: library == null ? 'flutter' : 'flutter ($library)',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLog.instance.record(error, stack, context: 'uncaught');
    if (kDebugMode) {
      // Still on the console while developing.
      debugPrint('Uncaught error: $error\n$stack');
    }
    return true;
  };

  // The version is asked from the platform; errors in the first moments
  // carry "?" instead.
  unawaited(_readVersion());
}

Future<void> _readVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    ErrorLog.instance.appVersion = '${info.version}+${info.buildNumber}';
  } on Object {
    // Stays "?".
  }
}

/// "release", "profile" or "debug" — which kind of build wrote the log.
String get buildModeName =>
    kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

/// The lines on top of a shared error log: which build, which phone, and
/// whatever [facts] the caller knows (database version, license state).
/// Nothing in it identifies a person; the request code identifies the
/// phone's license, which the shop sends the developer anyway.
String errorLogHeader({
  required String appVersion,
  required DateTime createdAt,
  required int errorCount,
  Map<String, String> facts = const {},
}) {
  final out = StringBuffer()
    ..writeln('Souqi error log')
    ..writeln('Created: ${createdAt.toIso8601String()}')
    ..writeln('App: $appVersion ($buildModeName)')
    ..writeln('System: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}')
    ..writeln('Locale: ${Platform.localeName}');
  for (final fact in facts.entries) {
    out.writeln('${fact.key}: ${fact.value}');
  }
  out.writeln(errorCount == 0
      ? 'Errors recorded: none'
      : 'Errors recorded: $errorCount');
  return out.toString();
}

/// "souqi-error-log-20261126-1412.txt".
String errorLogFileName(DateTime moment) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'souqi-error-log-${moment.year}${two(moment.month)}${two(moment.day)}'
      '-${two(moment.hour)}${two(moment.minute)}.txt';
}

/// What licensing needs from Android: who this device is, and who signed
/// the APK that is running.
///
/// Its own channel ("souqi/license", android/.../LicenseChannel.kt), which
/// is registered on BOTH engines — the app's and the one WorkManager starts
/// for the daily job — because the job checks the license too.
library;

import 'package:flutter/services.dart';

/// The two facts the device hash is made of.
class DeviceIdentity {
  const DeviceIdentity({required this.androidId, required this.packageName});

  /// `Settings.Secure.ANDROID_ID`: on Android 8+ it belongs to this app's
  /// signing key on this phone, and a factory reset changes it. Empty when
  /// the phone has none.
  final String androidId;

  /// The package name the app is installed under.
  final String packageName;
}

abstract class LicensePlatform {
  Future<DeviceIdentity> deviceIdentity();

  /// SHA-256 of each certificate that signed the installed APK, as lower
  /// case hex.
  Future<List<String>> signingCertificates();
}

class MethodChannelLicensePlatform implements LicensePlatform {
  const MethodChannelLicensePlatform();

  static const _channel = MethodChannel('souqi/license');

  @override
  Future<DeviceIdentity> deviceIdentity() async {
    final map =
        await _channel.invokeMethod<Map<Object?, Object?>>('deviceIdentity') ??
            const {};
    return DeviceIdentity(
      androidId: (map['androidId'] as String?) ?? '',
      packageName: (map['packageName'] as String?) ?? '',
    );
  }

  @override
  Future<List<String>> signingCertificates() async {
    final list =
        await _channel.invokeMethod<List<Object?>>('signingCertificates') ??
            const [];
    return [for (final value in list.whereType<String>()) value.toLowerCase()];
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'code_cipher.dart';

/// The card-code keys in the Android Keystore, through flutter_secure_storage.
class SecureStorageKeyStore implements SecretKeyStore {
  const SecureStorageKeyStore();

  static const _storage = FlutterSecureStorage(
    // The plugin's default is to WIPE everything it holds when a read fails.
    // For a cache that is a fair recovery; here it would silently destroy
    // the only key to every card in stock. A failed read must stay a failed
    // read — nothing is sold or shown until the Keystore answers again.
    aOptions: AndroidOptions(resetOnError: false),
  );

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}

/// The `.souqi` backup file: a zip with a manifest.
///
///     manifest.json   what is inside (app + schema version, date, counts,
///                     each file's size and SHA-256, the overall checksum,
///                     how the password key is derived)
///     manifest.sig    HMAC-SHA256 of manifest.json with the password's
///                     signing key — checked once the password is entered
///     souqi.db        a consistent snapshot of the whole database
///     logo.png        the shop logo (also inside the database)
///     secrets.bin     the card-code keys, sealed with the password
///
/// Only these names are ever read out of the zip, and each is written to a
/// fixed file name: nothing in a crafted file can choose where it lands.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

const String backupExtension = 'souqi';
const String backupMimeType = 'application/octet-stream';

const String backupFormatName = 'souqi-backup';
const int backupFormatVersion = 1;

abstract final class BackupEntry {
  static const manifest = 'manifest.json';
  static const signature = 'manifest.sig';
  static const database = 'souqi.db';
  static const logo = 'logo.png';
  static const secrets = 'secrets.bin';

  /// The files the manifest lists (and checks).
  static const payload = [database, logo, secrets];
}

/// Not a backup at all (another zip, a photo, a truncated download…), or a
/// backup whose files do not match its manifest.
class CorruptBackupException implements Exception {
  const CorruptBackupException([this.detail]);

  final String? detail;

  @override
  String toString() => 'CorruptBackupException($detail)';
}

/// Made by a newer version of the app: its database has a schema this
/// version does not know.
class NewerBackupException implements Exception {
  const NewerBackupException({
    required this.backupSchema,
    required this.appSchema,
    this.appVersion,
  });

  final int backupSchema;
  final int appSchema;

  /// The app version that made it, as the manifest says.
  final String? appVersion;

  @override
  String toString() =>
      'NewerBackupException(backup: $backupSchema, app: $appSchema)';
}

/// What the backup holds, for the confirmation before a restore.
class BackupCounts {
  const BackupCounts({
    this.invoices = 0,
    this.customers = 0,
    this.products = 0,
    this.codes = 0,
    this.debtEntries = 0,
  });

  final int invoices;
  final int customers;
  final int products;
  final int codes;
  final int debtEntries;

  Map<String, Object?> toJson() => {
        'invoices': invoices,
        'customers': customers,
        'products': products,
        'codes': codes,
        'debtEntries': debtEntries,
      };

  static BackupCounts fromJson(Object? json) {
    if (json is! Map) throw const CorruptBackupException('counts');
    int n(String key) {
      final value = json[key];
      if (value is int && value >= 0) return value;
      throw CorruptBackupException('counts.$key');
    }

    return BackupCounts(
      invoices: n('invoices'),
      customers: n('customers'),
      products: n('products'),
      codes: n('codes'),
      debtEntries: n('debtEntries'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupCounts &&
      other.invoices == invoices &&
      other.customers == customers &&
      other.products == products &&
      other.codes == codes &&
      other.debtEntries == debtEntries;

  @override
  int get hashCode =>
      Object.hash(invoices, customers, products, codes, debtEntries);

  @override
  String toString() => 'BackupCounts(${toJson()})';
}

class BackupFileInfo {
  const BackupFileInfo({
    required this.name,
    required this.size,
    required this.sha256,
  });

  final String name;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => {'name': name, 'size': size, 'sha256': sha256};
}

/// How the password key of this backup is derived.
class BackupKdf {
  const BackupKdf({required this.iterations, required this.salt});

  static const name = 'PBKDF2-HMAC-SHA256';

  final int iterations;
  final List<int> salt;

  Map<String, Object?> toJson() => {
        'name': name,
        'iterations': iterations,
        'salt': base64Encode(salt),
      };
}

class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.counts,
    required this.files,
    required this.kdf,
    this.formatVersion = backupFormatVersion,
  });

  final int formatVersion;
  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final BackupCounts counts;
  final List<BackupFileInfo> files;
  final BackupKdf kdf;

  BackupFileInfo? file(String name) {
    for (final f in files) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// One SHA-256 over every file's name, size and hash, in name order — the
  /// "checksum" of the whole backup.
  static String checksumOf(Iterable<BackupFileInfo> files) {
    final sorted = files.toList()..sort((a, b) => a.name.compareTo(b.name));
    final text = sorted.map((f) => '${f.name} ${f.size} ${f.sha256}\n').join();
    return crypto.sha256.convert(utf8.encode(text)).toString();
  }

  String get checksum => checksumOf(files);

  List<int> toBytes() => utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'format': backupFormatName,
          'formatVersion': formatVersion,
          'appVersion': appVersion,
          'schemaVersion': schemaVersion,
          'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
          'createdAtIso': createdAt.toUtc().toIso8601String(),
          'counts': counts.toJson(),
          'files': [for (final f in files) f.toJson()],
          'checksum': checksum,
          'kdf': kdf.toJson(),
        }),
      );

  /// Throws [CorruptBackupException] for anything that is not a manifest
  /// this format version can read.
  static BackupManifest fromBytes(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const CorruptBackupException('manifest is not JSON');
    }
    if (json is! Map || json['format'] != backupFormatName) {
      throw const CorruptBackupException('not a Souqi backup');
    }
    final formatVersion = json['formatVersion'];
    if (formatVersion is! int || formatVersion < 1) {
      throw const CorruptBackupException('formatVersion');
    }
    final schema = json['schemaVersion'];
    final created = json['createdAt'];
    final appVersion = json['appVersion'];
    final kdf = json['kdf'];
    final files = json['files'];
    if (schema is! int ||
        schema < 1 ||
        created is! int ||
        appVersion is! String ||
        kdf is! Map ||
        files is! List) {
      throw const CorruptBackupException('manifest fields');
    }
    if (kdf['name'] != BackupKdf.name ||
        kdf['iterations'] is! int ||
        kdf['salt'] is! String) {
      throw const CorruptBackupException('kdf');
    }
    final List<int> salt;
    try {
      salt = base64Decode(kdf['salt'] as String);
    } on FormatException {
      throw const CorruptBackupException('kdf.salt');
    }
    final infos = <BackupFileInfo>[];
    for (final entry in files) {
      if (entry is! Map ||
          entry['name'] is! String ||
          entry['size'] is! int ||
          entry['sha256'] is! String) {
        throw const CorruptBackupException('files');
      }
      infos.add(BackupFileInfo(
        name: entry['name'] as String,
        size: entry['size'] as int,
        sha256: entry['sha256'] as String,
      ));
    }
    final manifest = BackupManifest(
      formatVersion: formatVersion,
      appVersion: appVersion,
      schemaVersion: schema,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
      counts: BackupCounts.fromJson(json['counts']),
      files: infos,
      kdf: BackupKdf(iterations: kdf['iterations'] as int, salt: salt),
    );
    if (json['checksum'] != manifest.checksum) {
      throw const CorruptBackupException('checksum');
    }
    if (manifest.file(BackupEntry.database) == null ||
        manifest.file(BackupEntry.secrets) == null) {
      throw const CorruptBackupException('missing files');
    }
    return manifest;
  }
}

Future<BackupFileInfo> describeFile(String name, File file) async => BackupFileInfo(
      name: name,
      size: await file.length(),
      sha256: (await crypto.sha256.bind(file.openRead()).first).toString(),
    );

/// Writes the zip. [files] maps entry names to the files on disk.
Future<void> writeBackupZip(
  String path, {
  required List<int> manifest,
  required String signature,
  required Map<String, File> files,
}) async {
  final target = File(path);
  if (await target.exists()) await target.delete();
  final encoder = ZipFileEncoder();
  encoder.create(path);
  try {
    encoder.addArchiveFile(ArchiveFile.bytes(BackupEntry.manifest, manifest));
    encoder.addArchiveFile(
      ArchiveFile.bytes(BackupEntry.signature, utf8.encode(signature)),
    );
    for (final entry in files.entries) {
      await encoder.addFile(entry.value, entry.key);
    }
  } finally {
    await encoder.close();
  }
}

/// A backup taken apart in a folder of the app's own, with its manifest
/// checked against every file — but not yet opened with the password.
class ExtractedBackup {
  const ExtractedBackup({
    required this.dir,
    required this.manifest,
    required this.manifestBytes,
    required this.signature,
  });

  final Directory dir;
  final BackupManifest manifest;
  final List<int> manifestBytes;
  final String signature;

  File get database => File(p.join(dir.path, BackupEntry.database));
  File get secrets => File(p.join(dir.path, BackupEntry.secrets));
  File? get logo {
    if (manifest.file(BackupEntry.logo) == null) return null;
    return File(p.join(dir.path, BackupEntry.logo));
  }

  Future<void> discard() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // The app's own temporary folder: cleared again next time.
    }
  }
}

/// Unpacks [path] into [into] (which must be empty or not exist yet) and
/// checks every file against the manifest: size, SHA-256, the overall
/// checksum. Throws [CorruptBackupException]; the folder is removed again on
/// any failure.
Future<ExtractedBackup> extractBackup(String path, Directory into) async {
  await into.create(recursive: true);
  InputFileStream? input;
  try {
    input = InputFileStream(path);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
    } on Object {
      throw const CorruptBackupException('not a zip file');
    }
    final manifestEntry = archive.find(BackupEntry.manifest);
    final signatureEntry = archive.find(BackupEntry.signature);
    if (manifestEntry == null || signatureEntry == null) {
      throw const CorruptBackupException('no manifest');
    }
    final List<int> manifestBytes;
    final String signature;
    try {
      manifestBytes = manifestEntry.readBytes() ?? const [];
      signature = utf8.decode(signatureEntry.readBytes() ?? const []).trim();
    } on Object {
      throw const CorruptBackupException('manifest unreadable');
    }
    final manifest = BackupManifest.fromBytes(manifestBytes);
    for (final info in manifest.files) {
      if (!BackupEntry.payload.contains(info.name)) {
        throw CorruptBackupException('unexpected file ${info.name}');
      }
      final entry = archive.find(info.name);
      if (entry == null || !entry.isFile) {
        throw CorruptBackupException('missing ${info.name}');
      }
      final target = File(p.join(into.path, info.name));
      final out = OutputFileStream(target.path);
      try {
        entry.writeContent(out);
      } on Object {
        throw CorruptBackupException('damaged ${info.name}');
      } finally {
        await out.close();
      }
      final actual = await describeFile(info.name, target);
      if (actual.size != info.size || actual.sha256 != info.sha256) {
        throw CorruptBackupException('checksum of ${info.name}');
      }
    }
    return ExtractedBackup(
      dir: into,
      manifest: manifest,
      manifestBytes: manifestBytes,
      signature: signature,
    );
  } on Object {
    try {
      await input?.close();
      input = null;
      if (await into.exists()) await into.delete(recursive: true);
    } on FileSystemException {
      // Left for the next sweep of the temporary folder.
    }
    rethrow;
  } finally {
    await input?.close();
  }
}

import 'dart:io';

/// How long a staged share image or PDF is kept. The file only has to
/// outlive the share sheet it was handed to, so a day covers even a sheet
/// left open overnight — after that it is dead weight in the cache.
const Duration shareFileMaxAge = Duration(days: 1);

/// Deletes the files in [dir] last modified more than [maxAge] ago and
/// returns how many went.
///
/// Housekeeping never fails its caller: a missing directory, a file that
/// vanished underneath us or one the system will not let go of is skipped
/// and tried again on the next launch. Subdirectories are left alone.
Future<int> pruneOldFiles(
  Directory dir, {
  required Duration maxAge,
  DateTime? now,
}) async {
  if (!await dir.exists()) return 0;
  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  var deleted = 0;
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        if ((await entity.lastModified()).isAfter(cutoff)) continue;
        await entity.delete();
        deleted++;
      } on FileSystemException {
        continue;
      }
    }
  } on FileSystemException {
    return deleted;
  }
  return deleted;
}

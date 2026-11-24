import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/temp_files.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('souqi-cache');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<File> write(String name, {required Duration age}) async {
    final file = await File('${directory.path}/$name').writeAsString('x');
    await file.setLastModified(DateTime.now().subtract(age));
    return file;
  }

  test('sweeps out share files older than a day, keeps the fresh ones',
      () async {
    final stale = await write('invoice-1.png', age: const Duration(days: 2));
    final fresh = await write('invoice-2.pdf', age: const Duration(hours: 3));

    final deleted = await pruneOldFiles(directory, maxAge: shareFileMaxAge);

    expect(deleted, 1);
    expect(stale.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });

  test('leaves subdirectories alone', () async {
    final nested = await Directory('${directory.path}/sub').create();
    await pruneOldFiles(
      directory,
      maxAge: Duration.zero,
      now: DateTime.now().add(const Duration(days: 1)),
    );
    expect(nested.existsSync(), isTrue);
  });

  test('a missing directory is not an error', () async {
    await directory.delete(recursive: true);
    expect(await pruneOldFiles(directory, maxAge: shareFileMaxAge), 0);
  });
}

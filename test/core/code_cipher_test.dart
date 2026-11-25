import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/security/code_cipher.dart';

void main() {
  late InMemoryKeyStore store;
  late CodeCipher cipher;

  setUp(() {
    store = InMemoryKeyStore();
    cipher = CodeCipher(store);
  });

  group('encryption round trip', () {
    test('a code comes back exactly as it was entered', () async {
      for (final code in [
        '1234567890123456',
        '1234-5678-9012-3456',
        'AbCd-EfGh-1234',
        '١٢٣٤٥٦٧٨',
        'x',
      ]) {
        expect(await cipher.decrypt(await cipher.encrypt(code)), code);
      }
    });

    test('surrounding spaces are not part of the code', () async {
      expect(await cipher.decrypt(await cipher.encrypt('  1234 5678  ')),
          '1234 5678');
    });

    test('the stored bytes do not contain the code', () async {
      const code = '4455667788990011';
      final blob = await cipher.encrypt(code);
      expect(latin1.decode(blob).contains(code), isFalse);
      expect(utf8.decode(blob, allowMalformed: true).contains('4455'), isFalse);
      expect(blob.first, CodeCipher.formatVersion);
    });

    test('the same code encrypts differently every time', () async {
      final a = await cipher.encrypt('1234567890123456');
      final b = await cipher.encrypt('1234567890123456');
      expect(a, isNot(equals(b)));
      expect(await cipher.decrypt(a), await cipher.decrypt(b));
    });

    test('a second cipher over the same key store reads it', () async {
      final blob = await cipher.encrypt('1234567890123456');
      expect(await CodeCipher(store).decrypt(blob), '1234567890123456');
    });
  });

  group('what cannot be read', () {
    test('one flipped bit is refused, not decrypted to garbage', () async {
      final blob = await cipher.encrypt('1234567890123456');
      for (final index in [1, 14, blob.length - 1]) {
        final damaged = Uint8List.fromList(blob)..[index] ^= 0x01;
        expect(
          () => cipher.decrypt(damaged),
          throwsA(isA<CodeUnreadableException>()),
        );
      }
    });

    test('another device (another key) cannot read it', () async {
      final blob = await cipher.encrypt('1234567890123456');
      final other = CodeCipher(InMemoryKeyStore());
      expect(
        () => other.decrypt(blob),
        throwsA(isA<CodeUnreadableException>()),
      );
    });

    test('too short, or an unknown format version', () async {
      expect(() => cipher.decrypt(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<CodeUnreadableException>()));
      final blob = await cipher.encrypt('1234567890123456');
      final future = Uint8List.fromList(blob)..[0] = 9;
      expect(() => cipher.decrypt(future),
          throwsA(isA<CodeUnreadableException>()));
    });

    test('the exception says nothing about the code', () {
      expect('${const CodeUnreadableException()}', 'CodeUnreadableException');
    });
  });

  group('the key', () {
    test('is created once and kept', () async {
      expect(store.values, isEmpty);
      await cipher.encrypt('1111');
      final first = store.values[CodeCipher.keyName];
      expect(base64Decode(first!), hasLength(64));
      await cipher.encrypt('2222');
      await CodeCipher(store).encrypt('3333');
      expect(store.values[CodeCipher.keyName], first);
    });

    test('two callers arriving together share one key', () async {
      final blobs = await Future.wait([
        cipher.encrypt('1111'),
        cipher.encrypt('2222'),
        cipher.hash('3333'),
      ]);
      expect(await cipher.decrypt(blobs[0] as Uint8List), '1111');
      expect(await cipher.decrypt(blobs[1] as Uint8List), '2222');
    });

    test('a damaged stored key is an error, never silently replaced',
        () async {
      store.values[CodeCipher.keyName] = base64Encode([1, 2, 3]);
      expect(() => cipher.encrypt('1111'), throwsStateError);
      expect(store.values[CodeCipher.keyName], base64Encode([1, 2, 3]));
    });
  });

  group('the lookup hash', () {
    test('is the same for every spelling of one code', () async {
      final hash = await cipher.hash('1234567890123456');
      expect(await cipher.hash('1234-5678-9012-3456'), hash);
      expect(await cipher.hash(' 1234 5678 9012 3456 '), hash);
      expect(await cipher.hash('١٢٣٤٥٦٧٨٩٠١٢٣٤٥٦'), hash);
      expect(await cipher.hash('1234567890123457'), isNot(hash));
    });

    test('ignores letter case', () async {
      expect(await cipher.hash('abcd-1234'), await cipher.hash('ABCD1234'));
    });

    test('is keyed: another device hashes the same code differently',
        () async {
      final other = CodeCipher(InMemoryKeyStore());
      expect(await other.hash('1234567890123456'),
          isNot(await cipher.hash('1234567890123456')));
    });

    test('is 64 hex characters and does not contain the code', () async {
      final hash = await cipher.hash('1234567890123456');
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hash.contains('1234567890123456'), isFalse);
    });
  });
}

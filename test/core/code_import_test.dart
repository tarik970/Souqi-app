import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/vouchers/code_import.dart';

void main() {
  List<String> codes(CodeParseResult result) =>
      [for (final entry in result.codes) entry.code];

  group('one code per line', () {
    test('lines become codes, in order', () {
      final result = parseCodeList(
        '1111222233334444\n5555666677778888\n',
        columns: CodeColumns.codeOnly,
      );
      expect(codes(result), ['1111222233334444', '5555666677778888']);
      expect(result.emptyLines, 0);
      expect(result.duplicateLines, 0);
      expect(result.invalidLines, 0);
    });

    test('empty lines are skipped and counted', () {
      final result = parseCodeList(
        '1111\n\n   \n2222\n\n',
        columns: CodeColumns.codeOnly,
      );
      expect(codes(result), ['1111', '2222']);
      expect(result.emptyLines, 3);
    });

    test('Windows and old-Mac line endings, and a byte-order mark', () {
      final bom = String.fromCharCode(0xFEFF);
      final result = parseCodeList(
        '${bom}1111\r\n2222\r3333',
        columns: CodeColumns.codeOnly,
      );
      expect(codes(result), ['1111', '2222', '3333']);
      expect(result.emptyLines, 0);
    });

    test('a code keeps the spaces it was written with', () {
      final result = parseCodeList(
        '  1234 5678 9012 3456  ',
        columns: CodeColumns.codeOnly,
      );
      expect(codes(result), ['1234 5678 9012 3456']);
    });
  });

  group('duplicates inside the batch, with normalization', () {
    test('the same digits typed three ways are one card', () {
      final result = parseCodeList(
        '1234-5678-9012\n1234 5678 9012\n١٢٣٤٥٦٧٨٩٠١٢\n123456789012',
        columns: CodeColumns.codeOnly,
      );
      // The first spelling is the one kept.
      expect(codes(result), ['1234-5678-9012']);
      expect(result.duplicateLines, 3);
    });

    test('letter case does not make a different card', () {
      final result = parseCodeList(
        'abcd-1234\nABCD1234\nabcd1235',
        columns: CodeColumns.codeOnly,
      );
      expect(codes(result), ['abcd-1234', 'abcd1235']);
      expect(result.duplicateLines, 1);
    });

    test('a different serial does not make a different card', () {
      final result = parseCodeList(
        'S1,1111\nS2,1111',
        columns: CodeColumns.serialThenCode,
      );
      expect(result.codes.single.serial, 'S1');
      expect(result.duplicateLines, 1);
    });
  });

  group('two columns', () {
    test('serial,code', () {
      final result = parseCodeList(
        'SN001,1111222233334444\nSN002,5555666677778888',
        columns: CodeColumns.serialThenCode,
      );
      expect(codes(result), ['1111222233334444', '5555666677778888']);
      expect([for (final c in result.codes) c.serial], ['SN001', 'SN002']);
    });

    test('code,serial', () {
      final result = parseCodeList(
        '1111222233334444,SN001',
        columns: CodeColumns.codeThenSerial,
      );
      expect(result.codes.single.code, '1111222233334444');
      expect(result.codes.single.serial, 'SN001');
    });

    test('semicolons, tabs and quotes from a spreadsheet export', () {
      final result = parseCodeList(
        '"SN001";"1111"\nSN002\t2222\n\'SN003\' , \'3333\'',
        columns: CodeColumns.serialThenCode,
      );
      expect(codes(result), ['1111', '2222', '3333']);
      expect([for (final c in result.codes) c.serial],
          ['SN001', 'SN002', 'SN003']);
    });

    test('a line without a separator is a code with no serial', () {
      final result = parseCodeList(
        '1111\nSN2,2222',
        columns: CodeColumns.serialThenCode,
      );
      expect(codes(result), ['1111', '2222']);
      expect(result.codes.first.serial, isNull);
    });

    test('a line with nothing in the code column is invalid', () {
      final result = parseCodeList(
        'SN1,\nSN2,2222\nSN3,---',
        columns: CodeColumns.serialThenCode,
      );
      expect(codes(result), ['2222']);
      expect(result.invalidLines, 2);
    });

    test('the wrong column order shows up as serials in the code column', () {
      // Nothing is guessed: the preview is how the user notices.
      final result = parseCodeList(
        'SN001,1111',
        columns: CodeColumns.codeThenSerial,
      );
      expect(result.codes.single.code, 'SN001');
      expect(result.codes.single.serial, '1111');
    });
  });

  group('a heading line', () {
    test('is left out, in English or Arabic', () {
      final english = parseCodeList(
        'Serial,Code\nSN1,1111',
        columns: CodeColumns.serialThenCode,
      );
      expect(english.headerSkipped, isTrue);
      expect(codes(english), ['1111']);

      final arabic = parseCodeList(
        'الرمز\n1111',
        columns: CodeColumns.codeOnly,
      );
      expect(arabic.headerSkipped, isTrue);
      expect(codes(arabic), ['1111']);
    });

    test('only the first line can be one', () {
      final result = parseCodeList(
        '1111\ncode',
        columns: CodeColumns.codeOnly,
      );
      expect(result.headerSkipped, isFalse);
      expect(codes(result), ['1111', 'code']);
    });
  });

  test('line numbers point at the source', () {
    final result = parseCodeList(
      '\n1111\n\n2222',
      columns: CodeColumns.codeOnly,
    );
    expect([for (final c in result.codes) c.line], [2, 4]);
  });

  test('the report of the brief: 120 added, 3 duplicates, 1 empty line', () {
    final lines = [
      for (var i = 0; i < 120; i++) '5000${i.toString().padLeft(12, '0')}',
      '5000000000000000', // again
      '',
      '5000-0000-0000-0001', // again, with dashes
      '٥٠٠٠٠٠٠٠٠٠٠٠٠٠٠٢', // again, Arabic-Indic
    ];
    final result = parseCodeList(
      lines.join('\n'),
      columns: CodeColumns.codeOnly,
    );
    expect(result.codes, hasLength(120));
    expect(result.duplicateLines, 3);
    expect(result.emptyLines, 1);
  });
}

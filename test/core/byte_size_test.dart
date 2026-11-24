import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/byte_size.dart';

void main() {
  test('small sizes stay in bytes', () {
    final size = formatByteSize(812, locale: 'en');
    expect(size.unit, ByteUnit.bytes);
    expect(size.value, '812');
  });

  test('kilobytes keep one decimal while the number is small', () {
    expect(formatByteSize(1536, locale: 'en').value, '1.5');
    expect(formatByteSize(1536, locale: 'en').unit, ByteUnit.kilobytes);
    // 640 KB exactly: no pointless ".0" on a three-digit number.
    expect(formatByteSize(640 * 1024, locale: 'en').value, '640');
  });

  test('megabytes once past 1024 KB', () {
    final size = formatByteSize(5 * 1024 * 1024 + 512 * 1024, locale: 'en');
    expect(size.unit, ByteUnit.megabytes);
    expect(size.value, '5.5');
  });

  test('zero is zero bytes', () {
    expect(formatByteSize(0, locale: 'en').value, '0');
    expect(formatByteSize(0, locale: 'en').unit, ByteUnit.bytes);
  });

  test('the number is localized like every other figure in the app', () {
    // intl's plain 'ar' data uses Latin digits; ar_EG uses Arabic-Indic.
    expect(formatByteSize(1536, locale: 'ar_EG').value, '١٫٥');
    expect(formatByteSize(812, locale: 'ar_EG').value, '٨١٢');
    expect(formatByteSize(1536, locale: 'ar').value, isNotEmpty);
  });
}

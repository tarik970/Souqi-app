import 'dart:typed_data';

import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';

final syp = Currency(
  code: 'SYP',
  nameAr: 'ليرة سورية',
  nameEn: 'Syrian Pound',
  symbol: 'ل.س',
  decimalPlaces: 0,
  rate: RateFraction.one,
  rateUpdatedAt: DateTime.utc(2026),
);

/// 1 USD = 13,000 SYP.
final usd = Currency(
  code: 'USD',
  nameAr: 'دولار أمريكي',
  nameEn: 'US Dollar',
  symbol: r'$',
  decimalPlaces: 2,
  rate: const RateFraction(13000, 1),
  rateUpdatedAt: DateTime.utc(2026),
  sortOrder: 1,
);

final testCurrencies = {'SYP': syp, 'USD': usd};

/// A USD invoice with one SYP-priced line and one USD-priced line — the
/// brief's own example: 10 × 5,000 SYP at 13,000 SYP/USD = 3.85 USD.
Invoice crossCurrencyInvoice({
  String? customerName,
  String? customerPhone,
  String? accountNumber,
  List<String> extraCodes = const [],
  int invoiceNo = 12,
}) {
  final ctx = CurrencyContext.of(
    [syp, usd],
    baseCode: 'SYP',
    extraCodes: extraCodes,
  );
  final cart = const Cart()
      .add(const CartLine(
        name: 'Sugar',
        code: '101',
        unitName: 'kg',
        unitPriceMinor: 5000,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 10000,
      ))
      .add(const CartLine(
        name: 'Oil',
        code: '102',
        unitPriceMinor: 250,
        priceCurrencyCode: 'USD',
        qtyThousandths: 2000,
      ))
      .withInvoiceCurrency('USD');
  return Invoice.fromCart(
    cart: cart,
    ctx: ctx,
    createdAt: DateTime(2026, 11, 24, 14, 35),
    customerName: customerName,
    customerPhone: customerPhone,
    accountNumber: accountNumber,
  ).copyWith(invoiceNo: invoiceNo);
}

/// A plain SYP invoice with [lines] identical lines (for long receipts).
Invoice sypInvoice({int lines = 2, String? customerPhone, int invoiceNo = 7}) {
  final ctx = CurrencyContext.of([syp, usd], baseCode: 'SYP');
  var cart = const Cart();
  for (var i = 0; i < lines; i++) {
    cart = cart.add(CartLine(
      name: 'Item ${i + 1}',
      unitPriceMinor: 1500 + i,
      priceCurrencyCode: 'SYP',
      qtyThousandths: 2000,
    ));
  }
  return Invoice.fromCart(
    cart: cart,
    ctx: ctx,
    createdAt: DateTime(2026, 11, 24, 9, 5),
    customerPhone: customerPhone,
  ).copyWith(invoiceNo: invoiceNo);
}

/// Records what the app asked Android to do, and answers as configured.
class FakeNativeBridge implements NativeBridge {
  BluetoothStatus status = const BluetoothStatus(
    supported: true,
    enabled: true,
    permissionGranted: true,
  );
  bool grantPermissionOnRequest = true;
  List<PairedDevice> devices = const [];
  OutputException? printError;
  List<String> installedWhatsApp = const [whatsAppPackage];
  bool whatsAppOpens = true;

  int permissionRequests = 0;
  final printed = <({String address, Uint8List bytes})>[];
  final shared = <({String path, String mimeType, String? text})>[];
  final whatsAppSends =
      <({String package, String phone, String path, String mimeType})>[];
  final saved = <({String path, String fileName, String mimeType})>[];

  @override
  Future<BluetoothStatus> bluetoothStatus() async => status;

  @override
  Future<bool> requestBluetoothPermission() async {
    permissionRequests++;
    if (grantPermissionOnRequest) {
      status = BluetoothStatus(
        supported: status.supported,
        enabled: status.enabled,
        permissionGranted: true,
      );
    }
    return grantPermissionOnRequest;
  }

  @override
  Future<List<PairedDevice>> pairedDevices() async => devices;

  @override
  Future<void> printBytes(
    String address,
    Uint8List bytes, {
    int chunkSize = 1024,
    int chunkDelayMs = 0,
  }) async {
    final error = printError;
    if (error != null) throw error;
    printed.add((address: address, bytes: bytes));
  }

  @override
  Future<void> disconnectPrinter() async {}

  @override
  Future<void> openBluetoothSettings() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<List<String>> whatsAppPackages() async => installedWhatsApp;

  @override
  Future<bool> sendToWhatsApp({
    required String package,
    required String internationalPhone,
    required String filePath,
    required String mimeType,
    String? text,
  }) async {
    whatsAppSends.add((
      package: package,
      phone: internationalPhone,
      path: filePath,
      mimeType: mimeType,
    ));
    return whatsAppOpens;
  }

  bool chatOpens = true;
  bool dialerOpens = true;
  final chats = <({String package, String phone, String? text})>[];
  final dialed = <String>[];

  @override
  Future<bool> openWhatsAppChat({
    required String package,
    required String internationalPhone,
    String? text,
  }) async {
    chats.add((package: package, phone: internationalPhone, text: text));
    return chatOpens;
  }

  @override
  Future<bool> dial(String phone) async {
    dialed.add(phone);
    return dialerOpens;
  }

  @override
  Future<String> saveToDownloads({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    saved.add((path: filePath, fileName: fileName, mimeType: mimeType));
    return 'Download/Souqi/$fileName';
  }

  @override
  Future<void> shareFile({
    required String filePath,
    required String mimeType,
    String? text,
  }) async {
    shared.add((path: filePath, mimeType: mimeType, text: text));
  }

  /// What the file picker returns; null = the user backed out.
  PickedTextFile? fileToPick;
  int beeps = 0;

  @override
  Future<PickedTextFile?> pickTextFile() async => fileToPick;

  @override
  Future<void> beep() async => beeps++;
}

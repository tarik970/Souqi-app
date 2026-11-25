import 'dart:typed_data';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/platform/external_action_bridge.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/features/security/pin_session.dart';

import 'invoice_test_utils.dart';

/// A clock the test moves by hand — on its own (an app frozen in the
/// background: time passes, no timer fires) or together with the timers.
class FakePinClock extends PinClock {
  DateTime wall = DateTime(2026, 11, 25, 10);
  Duration running = Duration.zero;

  @override
  DateTime wallNow() => wall;

  @override
  Duration runningNow() => running;

  void advance(Duration by) {
    wall = wall.add(by);
    running += by;
  }
}

/// A session like the debts' one.
final sessionProvider =
    NotifierProvider<PinSessionNotifier, bool>(PinSessionNotifier.new);

class Harness {
  Harness(this.tester, {int idleMinutes = 5}) {
    container = ProviderContainer(
      overrides: [
        pinClockProvider.overrideWithValue(clock),
        pinAutoLockMinutesProvider.overrideWith((ref) => idleMinutes),
      ],
    );
  }

  final WidgetTester tester;
  final clock = FakePinClock();
  late final ProviderContainer container;

  PinBackgroundGuard get guard => container.read(pinBackgroundGuardProvider);
  bool get unlocked => container.read(sessionProvider);

  /// A screen of the session is open and unlocked.
  Future<void> unlock() async {
    await container.read(pinAutoLockMinutesProvider.future);
    container.listen(sessionProvider, (_, _) {});
    container.read(sessionProvider.notifier).unlock();
    expect(unlocked, isTrue);
  }

  void touch() => container.read(sessionProvider.notifier).touch();

  /// Time passes and the timers run: the app is alive.
  Future<void> pass(Duration time) async {
    clock.advance(time);
    await tester.pump(time);
  }

  /// Time passes and NO timer runs: Android froze the app in the
  /// background.
  void frozenFor(Duration time) => clock.advance(time);

  void loseFocus() => guard.lifecycle(AppLifecycleState.inactive);

  /// To the background: another app, the home screen, the screen off.
  void leave() {
    guard
      ..lifecycle(AppLifecycleState.inactive)
      ..lifecycle(AppLifecycleState.hidden)
      ..lifecycle(AppLifecycleState.paused);
  }

  void comeBack() {
    guard
      ..lifecycle(AppLifecycleState.hidden)
      ..lifecycle(AppLifecycleState.inactive)
      ..lifecycle(AppLifecycleState.resumed);
  }

  /// The app opens WhatsApp, the share sheet…
  void announce() => guard.externalActionStarting();
}

/// Runs [body] with a [Harness] and closes it before the test ends: the
/// test binding refuses a test that leaves a timer running.
void guardTest(
  String description,
  Future<void> Function(Harness h) body, {
  int idleMinutes = 5,
}) {
  testWidgets(description, (tester) async {
    final h = Harness(tester, idleMinutes: idleMinutes);
    try {
      await body(h);
    } finally {
      h.container.dispose();
    }
  });
}

const seconds = Duration(seconds: 1);
const minutes = Duration(minutes: 1);

void main() {
  group('the user leaves the app', () {
    guardTest('the home button locks at once', (h) async {
      await h.unlock();
      h.leave();
      expect(h.unlocked, isFalse);
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('losing the focus alone (a permission dialog) does not lock',
        (h) async {
      await h.unlock();
      h.loseFocus();
      h.guard.lifecycle(AppLifecycleState.resumed);
      expect(h.unlocked, isTrue);
    });

    guardTest('a session nobody is watching is locked too', (h) async {
      await h.container.read(pinAutoLockMinutesProvider.future);
      h.container.read(sessionProvider.notifier).unlock();
      h.leave();
      h.comeBack();
      expect(h.container.read(sessionProvider), isFalse);
    });
  });

  group('the app opens something itself', () {
    guardTest('back within two minutes: still open', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      expect(h.unlocked, isTrue);
      await h.pass(minutes + seconds * 55);
      expect(h.unlocked, isTrue);
      h.comeBack();
      expect(h.unlocked, isTrue);
    });

    guardTest('away for more than two minutes: locked, while still away',
        (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      await h.pass(minutes * 2 - seconds);
      expect(h.unlocked, isTrue);
      await h.pass(seconds * 2);
      expect(h.unlocked, isFalse);
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('away for more than two minutes with the app frozen (no timer '
        'ran): locked on the way back', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave()
        ..frozenFor(minutes * 2 + seconds);
      expect(h.unlocked, isTrue, reason: 'nothing ran yet');
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('frozen for less than two minutes: still open', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave()
        ..frozenFor(minutes + seconds * 50)
        ..comeBack();
      expect(h.unlocked, isTrue);
    });

    guardTest('one announcement covers ONE trip: the home button right '
        'after coming back locks at once', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      await h.pass(seconds * 30);
      h.comeBack();
      expect(h.unlocked, isTrue);

      h.leave();
      expect(h.unlocked, isFalse);
    });

    guardTest('the two minutes count from leaving, each trip on its own',
        (h) async {
      await h.unlock();
      for (var trip = 0; trip < 3; trip++) {
        h
          ..announce()
          ..leave();
        await h.pass(minutes + seconds * 30);
        h
          ..comeBack()
          // The seller does something on the screen in between.
          ..touch();
        await h.pass(seconds * 5);
        expect(h.unlocked, isTrue, reason: 'trip $trip');
      }
    });

    guardTest('the share sheet: a panel over the app for as long as the '
        'seller takes to choose, the background only after', (h) async {
      await h.unlock();
      h
        ..announce()
        ..loseFocus();
      // Far longer than the time an announcement waits for.
      await h.pass(seconds * 40);
      h.guard
        ..lifecycle(AppLifecycleState.hidden)
        ..lifecycle(AppLifecycleState.paused);
      expect(h.unlocked, isTrue);
      await h.pass(minutes);
      h.comeBack();
      expect(h.unlocked, isTrue);
    });

    guardTest('the share sheet closed without choosing: the announcement is '
        'spent, the home button locks at once', (h) async {
      await h.unlock();
      h
        ..announce()
        ..loseFocus();
      await h.pass(seconds * 3);
      h.guard.lifecycle(AppLifecycleState.resumed);
      expect(h.unlocked, isTrue);

      h.leave();
      expect(h.unlocked, isFalse);
    });

    guardTest('nothing came up within ten seconds: the announcement is '
        'dropped, the home button locks at once', (h) async {
      await h.unlock();
      h.announce();
      await h.pass(seconds * 9);
      // Still good: a slow phone taking its time to show WhatsApp.
      h.leave();
      expect(h.unlocked, isTrue);
      h.comeBack();

      h.announce();
      await h.pass(seconds * 11);
      h.leave();
      expect(h.unlocked, isFalse);
    });

    guardTest('the platform said it opened nothing: the home button locks '
        'at once', (h) async {
      await h.unlock();
      h
        ..announce()
        ..guard.externalActionFailed()
        ..leave();
      expect(h.unlocked, isFalse);
    });

    guardTest('a late "nothing opened" does not end a trip already under '
        'way', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave()
        ..guard.externalActionFailed();
      await h.pass(seconds * 30);
      h.comeBack();
      expect(h.unlocked, isTrue);
    });

    guardTest('the app being closed locks, announced or not', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave()
        ..guard.lifecycle(AppLifecycleState.detached);
      expect(h.unlocked, isFalse);
    });
  });

  group('the idle time keeps running behind an external action', () {
    guardTest('"lock again after 1 minute": 70 seconds in WhatsApp is the '
        'lock, though under two minutes', idleMinutes: 1, (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      await h.pass(seconds * 50);
      expect(h.unlocked, isTrue);
      await h.pass(seconds * 20);
      expect(h.unlocked, isFalse);
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('the same with the app frozen: checked on the way back',
        idleMinutes: 1, (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave()
        ..frozenFor(seconds * 70);
      expect(h.unlocked, isTrue, reason: 'nothing ran yet');
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('back before the idle time: open, and the idle time was not '
        'restarted by the trip', idleMinutes: 1, (h) async {
      await h.unlock();
      await h.pass(seconds * 20);
      h
        ..announce()
        ..leave();
      await h.pass(seconds * 30);
      h.comeBack();
      expect(h.unlocked, isTrue);
      // 50 seconds since the last touch; 15 more is over the minute.
      await h.pass(seconds * 15);
      expect(h.unlocked, isFalse);
    });

    guardTest('five minutes: the whole two minutes are there', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave()
        ..frozenFor(minutes + seconds * 59)
        ..comeBack();
      expect(h.unlocked, isTrue);
    });
  });

  group('the two clocks', () {
    guardTest('the phone\'s clock set BACK while away: locked', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      h.clock.wall = h.clock.wall.subtract(const Duration(minutes: 10));
      h.clock.running += seconds * 20;
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('ten minutes away and the clock set back to look like one: '
        'the running clock says ten', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      h.clock.wall = h.clock.wall.add(minutes);
      h.clock.running += minutes * 10;
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    guardTest('the phone slept (the running clock stood still): the wall '
        'clock says ten minutes', (h) async {
      await h.unlock();
      h
        ..announce()
        ..leave();
      h.clock.wall = h.clock.wall.add(minutes * 10);
      h.clock.running += seconds * 5;
      h.comeBack();
      expect(h.unlocked, isFalse);
    });

    test('the real clock runs forward', () async {
      final clock = PinClock();
      final start = clock.stamp();
      expect(clock.passed(start, const Duration(hours: 1)), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(clock.passed(start, const Duration(milliseconds: 20)), isTrue);
    });
  });

  group('the doorway to Android announces what opens another app', () {
    late FakeNativeBridge fake;
    late int announced;
    late int notStarted;
    late ExternalActionBridge bridge;

    ExternalActionBridge wrap(NativeBridge inner) => ExternalActionBridge(
          inner,
          onStarting: () => announced++,
          onNotStarted: () => notStarted++,
        );

    setUp(() {
      fake = FakeNativeBridge();
      announced = 0;
      notStarted = 0;
      bridge = wrap(fake);
    });

    Future<bool> whatsAppFile() => bridge.sendToWhatsApp(
          package: whatsAppPackage,
          internationalPhone: '963944123456',
          filePath: 'receipt.png',
          mimeType: 'image/png',
        );

    Future<bool> whatsAppChat() => bridge.openWhatsAppChat(
          package: whatsAppPackage,
          internationalPhone: '963944123456',
          text: 'hello',
        );

    test('the share sheet, WhatsApp (file and chat), the dialer, the file '
        'picker, the two settings pages', () async {
      final actions = <String, Future<Object?> Function()>{
        'share sheet': () =>
            bridge.shareFile(filePath: 'receipt.png', mimeType: 'image/png'),
        'WhatsApp with a file': whatsAppFile,
        'WhatsApp chat': whatsAppChat,
        'dialer': () => bridge.dial('0944 123 456'),
        'file picker': bridge.pickTextFile,
        'Bluetooth settings': bridge.openBluetoothSettings,
        'app settings': bridge.openAppSettings,
      };
      for (final MapEntry(key: name, value: action) in actions.entries) {
        announced = 0;
        await action();
        expect(announced, 1, reason: name);
        expect(notStarted, 0, reason: name);
      }
      // …and they reached the phone.
      expect(fake.shared, hasLength(1));
      expect(fake.whatsAppSends, hasLength(1));
      expect(fake.chats.single.text, 'hello');
      expect(fake.dialed.single, '0944 123 456');
    });

    test('the announcement comes BEFORE the phone is asked', () async {
      final order = <String>[];
      final ordered = ExternalActionBridge(
        _Recording(order),
        onStarting: () => order.add('announced'),
        onNotStarted: () {},
      );
      await ordered.dial('0944 123 456');
      expect(order, ['announced', 'dial']);
    });

    test('what stays inside the app announces nothing: saving to the phone, '
        'printing, the permission prompt, the beep', () async {
      await bridge.saveToDownloads(
        filePath: 'receipt.png',
        fileName: 'receipt.png',
        mimeType: 'image/png',
      );
      await bridge.printBytes('00:11', Uint8List(4));
      await bridge.requestBluetoothPermission();
      await bridge.bluetoothStatus();
      await bridge.pairedDevices();
      await bridge.whatsAppPackages();
      await bridge.disconnectPrinter();
      await bridge.beep();
      expect(announced, 0);
      expect(fake.saved, hasLength(1));
      expect(fake.printed, hasLength(1));
      expect(fake.beeps, 1);
    });

    test('WhatsApp or the dialer could not be opened: taken back', () async {
      fake
        ..whatsAppOpens = false
        ..chatOpens = false
        ..dialerOpens = false;
      expect(await whatsAppFile(), isFalse);
      expect(await whatsAppChat(), isFalse);
      expect(await bridge.dial('0944 123 456'), isFalse);
      expect(announced, 3);
      expect(notStarted, 3);
    });

    test('the phone refused with an error: taken back, and the error still '
        'reaches the screen', () async {
      final failing = wrap(_Failing());
      await expectLater(
        failing.shareFile(filePath: 'receipt.png', mimeType: 'image/png'),
        throwsA(isA<OutputException>()),
      );
      await expectLater(
        failing.pickTextFile(),
        throwsA(isA<OutputException>()),
      );
      expect(announced, 2);
      expect(notStarted, 2);
    });
  });
}

class _Recording extends FakeNativeBridge {
  _Recording(this.order);

  final List<String> order;

  @override
  Future<bool> dial(String phone) async {
    order.add('dial');
    return true;
  }
}

class _Failing extends FakeNativeBridge {
  @override
  Future<void> shareFile({
    required String filePath,
    required String mimeType,
    String? text,
  }) =>
      throw const OutputException(OutputFailure.unknown, 'no share sheet');

  @override
  Future<PickedTextFile?> pickTextFile() async =>
      throw const OutputException(OutputFailure.unknown, 'not a text file');
}

# Souqi (سوقي)

An offline point-of-sale and invoice app for small shops: groceries,
internet-card and subscription shops, anything that sells products, services
or cards. Android only, Arabic and English, no server, no internet, no
accounts. Everything lives in one SQLite database on the phone.

The permanent project brief — what the app does and the rules its code
follows — is `.cursor/rules/souqi.mdc`. This file is about building,
releasing and maintaining it.

- [Build](#build)
- [The three things that must never be lost](#the-three-things-that-must-never-be-lost)
- [The release keystore](#the-release-keystore)
- [Building a release](#building-a-release)
- [Licensing and the key generator](#licensing-and-the-key-generator)
- [Feature flags](#feature-flags)
- [Database versions](#database-versions)
- [Printers](#printers)
- [The error log](#the-error-log)
- [Release checklist](#release-checklist)

## Build

Needs Flutter 3.50 (Dart 3.14), JDK 17 and the Android SDK.

```powershell
flutter pub get
flutter gen-l10n                  # after editing lib/l10n/app_*.arb
flutter analyze                   # must report no issues
flutter test --concurrency=1      # the full suite, about 20 minutes
flutter run                       # debug build on a connected phone
```

Things this project depends on that are easy to break:

- **`--concurrency=1`** for the whole test suite on the development machine:
  several test processes at once run out of memory.
- **Never run `flutter test` and `flutter build`/`flutter run` at the same
  time.** Both regenerate `lib/l10n/generated/`; `flutter gen-l10n` restores
  it.
- **`kotlin.incremental=false`** in `android/gradle.properties` stays (a
  Windows Kotlin cache bug).
- **The Aliyun Maven mirrors** in `android/settings.gradle.kts`,
  `android/build.gradle.kts` (and `~/.gradle/init.gradle`) stay: Google's
  Maven is blocked on the development network.
- UI code imports `package:material_ui/material_ui.dart`
  (`package:flutter/material.dart` is deprecated in this Flutter).
- No printer plugin, no scheduler plugin: Bluetooth printing, the daily job
  and licensing go through the app's own platform channels in
  `android/app/src/main/kotlin/com/souqi/souqi/`.

A Kotlin-only check without a full build:
`cd android; ./gradlew :app:compileDebugKotlin --offline`.

## The three things that must never be lost

Every customer's activation depends on all three. Lose or change any one of
them and **every phone that was activated stops selling** until it gets a new
build and a new activation code.

| What | Where it is | Why it can never change |
| --- | --- | --- |
| **The release keystore** and its password | A file outside this repository (for example `C:\SouqiKeys\souqi-release.jks`) | A phone's request code is derived from the key the app is signed with. An update signed with another key shows another request code, cannot be installed over the old app, and fails the app's own signature check. |
| **The licensing private key** | The key file `souqi_keygen init` wrote (outside this repository, see `..\souqi_keygen\README.md`) | The app trusts this key only. Without it no activation code and no PIN-reset code can be issued for the apps already installed. |
| **Three constants in `lib/core/licensing/license_keys.dart`**: `licensePublicKeyHex`, `licenseDeviceSalt`, `expectedSigningCertSha256` — and the package name `com.souqi.souqi` | In this repository | They are part of how a code is checked and how a phone is identified. They are not secret, but changing one invalidates every license issued. |

**Back up, in at least three places that are not this computer** (two USB
sticks kept in two buildings and a printed copy of the passwords is a good
set):

1. `C:\SouqiKeys\souqi-release.jks` — the keystore file itself.
2. The keystore password (and alias `souqi`), written down or in a password
   manager. `android/key.properties` holds it too, but that file is only a
   convenience and is not in git.
3. The licensing key file, and `keygen.config.json` and `issued.csv` from
   `..\souqi_keygen` (the record of every license issued).
4. This repository (it holds the three constants): keep the git remote up to
   date.
5. `releases\<version>\` of every version handed out (APK, symbols, mapping).

Never put the keystore, `key.properties` or the licensing key into this
repository, a chat or a cloud folder. `android/.gitignore` already ignores
`key.properties`, `*.jks` and `*.keystore`; the root `.gitignore` ignores
`*.key` and `releases/`.

## The release keystore

Done **once**, before the first release. In PowerShell:

```powershell
# 1. A folder OUTSIDE the repository.
New-Item -ItemType Directory -Force C:\SouqiKeys | Out-Null

# 2. The keystore: RSA 4096, valid for 30 years (10958 days). keytool asks for
#    a password twice. Use at least 20 letters and digits — no spaces, no
#    backslash, no '#', '!', '=' or ':' (they have a meaning in key.properties).
keytool -genkeypair -v `
  -keystore C:\SouqiKeys\souqi-release.jks -storetype PKCS12 `
  -alias souqi -keyalg RSA -keysize 4096 -sigalg SHA256withRSA `
  -validity 10958 -dname "CN=Souqi, O=Souqi, C=SY"

# 3. android/key.properties (git-ignored). The password is typed, not pasted
#    into a command, so it does not end up in the shell history.
$secure = Read-Host 'Keystore password' -AsSecureString
$plain  = [System.Net.NetworkCredential]::new('', $secure).Password
Set-Content -Path D:\Souqi\android\key.properties -Encoding ascii -Value @(
  'storeFile=C:/SouqiKeys/souqi-release.jks'
  "storePassword=$plain"
  "keyPassword=$plain"
  'keyAlias=souqi'
)
Remove-Variable plain, secure

# 4. Check that git does not see it (must print the .gitignore rule).
git -C D:\Souqi check-ignore -v android/key.properties

# 5. Print the certificate's SHA-256 and write it into
#    expectedSigningCertSha256, then commit that one file.
pwsh D:\Souqi\tool\seal_release.ps1
git -C D:\Souqi add lib/core/licensing/license_keys.dart
git -C D:\Souqi commit -m "Seal the release build with the release certificate"
```

Then back the keystore up (previous section) **before** building anything for
a customer.

`android/app/build.gradle.kts` signs the release build with this keystore
whenever `android/key.properties` exists. Without it a release build still
compiles but is signed with the debug key; such an APK reports itself as
modified and does not sell.

**Request codes change with the signing key.** A license issued for a debug
build, or for a build signed with any other key, does not work on the release
build: issue real licenses only from request codes shown by an APK built with
`tool/build_release.ps1`.

## Building a release

```powershell
pwsh tool/build_release.ps1
```

It refuses to run unless the keystore of `android/key.properties` matches
`expectedSigningCertSha256`, builds an obfuscated APK for arm and arm64 (one
universal APK — never `--split-per-abi`, whose APKs cannot update each
other), checks the certificate of the result, and fills one folder:

```
releases/<version>/
  souqi-<version>.apk   hand this out
  symbols/              Dart debug symbols (--split-debug-info)
  mapping.txt           R8's name map of the Android side
  build-info.txt        date, git commit, Flutter version, certificate, sizes
```

**Archive that folder with every version you hand out.** A customer's error
log is obfuscated and can only be read with the symbols of the same build:

```powershell
flutter symbolize -i souqi-error-log.txt -d releases/1.0.0+1/symbols/app.android-arm64.symbols
```

`pwsh tool/build_release.ps1 -AllowDebugSigning` builds without the release
key into `releases/<version>-UNSIGNED/` — for looking at the size or trying
the build on your own phone, never for a customer.

A new version: raise `version:` in `pubspec.yaml` (`1.0.1+2` — the number
after `+` is Android's version code and must grow with every release), commit,
build. An update installs over the old app and keeps its data **only** when it
is signed with the same keystore and has a higher version code.

R8 runs on every release build. What is reached by name at run time (the
WorkManager worker, the file provider, the plugins) is kept by
`android/app/proguard-rules.pro`; add a rule there whenever a new class is
referenced from the manifest, created by reflection or called through JNI.

Developer tools (the test-data seeders on Settings → About) exist in debug
builds only: they sit behind `kDebugMode`, so a release build does not
contain their code.

## Licensing and the key generator

Offline. Each phone needs an activation code signed with the developer's
Ed25519 private key; the app holds only the public key. The design is in the
brief (`.cursor/rules/souqi.mdc`, phase 5b). The key generator is a separate
project next to this one and is never part of this repository:

```powershell
cd D:\souqi_keygen
dart pub get
dart run bin/keygen.dart                       # lists the commands

# Once: make the key pair. Prints the public key for license_keys.dart.
dart run bin/keygen.dart init --out E:\souqi\souqi-licensing.key

# An activation code. The customer sends the REQUEST CODE the app shows
# (Settings -> Activation, or the activation screen).
dart run bin/keygen.dart issue --request K7QM-29XD-HF4P-8WZN --shop "بقالة النور" --features all --lifetime
dart run bin/keygen.dart issue --request K7QM-29XD-HF4P-8WZN --shop "Al Noor" --features debt,vouchers,barcode --expires 2027-12-31
```

- `--shop` is the name printed on every invoice of that shop
  (`--shop-file name.txt` when the console cannot type Arabic).
- `--features`: `debt`, `customers`, `accounts`, `vouchers`, `barcode`,
  `discount`, `multiCurrency`, `dailyReport`, `backup`, or `all`.
- It prints the code (send it as text; spaces and line breaks do not matter)
  and writes a QR code to `out/` that the app can scan.
- A PIN-reset code for a shop that lost its PIN **and** its recovery code is
  issued the same way from the request code in the "Forgot PIN?" dialog; see
  `..\souqi_keygen\README.md`.

A license belongs to one phone and one signing key: a factory reset, another
phone, or a build signed with another keystore all show a different request
code and need a new activation. The code format is shared between the two
projects (`license_codec.dart`, `base32.dart`, `license_vectors.json`); never
change a field or a feature bit in one without the other
(`dart run tool/check_shared.dart` in the key generator compares them).

`developerWhatsApp` in `lib/config/support.dart` is still the placeholder
`+963XXXXXXXXX`: replace the X's with your number (a `+`, spaces and dashes
are fine) and "Send on WhatsApp" on the activation screen opens your chat
with the request code typed in. While it holds X's the app treats it as "no
number" and lets the shop choose the chat (`developerWhatsAppNumber`).

## Feature flags

One question everywhere: `featureOn(Feature.x)` (`lib/config/features.dart`).
A feature is on when all three are true:

1. its **compile-time flag** in `features.dart` (`debtEnabled`,
   `customersEnabled`, `accountsEnabled`, `voucherStockEnabled`,
   `barcodeEnabled`, `discountEnabled`, `multiCurrencyEnabled`,
   `dailyReportEnabled`, `backupEnabled`) — the upper limit of a build;
2. the **license** has its bit (everything during the trial);
3. what it **requires** is on (accounts and debt need customers; the daily
   report needs debt).

Nothing outside `features.dart` reads a flag constant or the license mask.
With a feature off nothing of it appears anywhere — menus, buttons, invoice
lines, statistics — but its tables exist from version 1, so turning it on
later needs no migration.

A new module: add a `Feature`, a flag, and a bit in `licenseFeatureBits`
(`license_codec.dart`, in both projects). Tests turn a feature off with
`FeatureGate.applyWithout([...])` and `addTearDown(FeatureGate.reset)`.

"Shop type" (Grocery / Cards & subscriptions / Both) is a runtime setting,
not a flag: it only changes defaults and what is shown first.

## Database versions

The schema is at **version 8**. Each version is one class in
`lib/data/db/migrations/`, listed in `AppDatabase.migrations`.

1. **A schema change is always a new version step**, added at the end.
   Never edit or remove an existing migration: phones in the field have
   already run it.
2. **A migration never drops user data.** When it must change rows (version 7
   clears duplicate barcodes), it changes the least it can and writes what it
   did to the audit log.
3. **Every step has a test** in `test/data/migration_test.dart` that opens a
   populated database of the previous version, upgrades it, and checks that
   no row was lost and that the result equals a fresh install.
4. **SQL must run on SQLite 3.9** (Android 7): no window functions, no
   UPSERT, no `RETURNING`, no `VACUUM INTO`, no `RENAME COLUMN`, at most 999
   parameters in one statement.
5. A database from a **newer** version is refused
   (`NewerDatabaseException`), never relabelled. A backup records its schema
   version; an older backup is migrated on restore, a newer one is refused.
6. Multi-step writes go in one transaction, and inside it everything uses the
   transaction, never the outer database.
7. Money is INTEGER minor units of its currency, quantities are INTEGER
   thousandths, rates are two INTEGERs. A currency's decimal places are
   frozen once anything is stored in it.
8. The debt ledger is append-only: its rows are never updated or deleted
   (triggers refuse), a correction is a REVERSAL entry. The one change an
   entry may see is a link being cleared (`invoice_id`, `return_id`) when
   its invoice is deleted.
9. An invoice is never deleted to fix a mistake: it is VOIDED
   (`invoices.voided_at`, counted nowhere, still in the archive) or items
   are RETURNED (`invoice_returns`, own counter `return_no`). Every query
   that counts sales has `voided_at IS NULL`; a new one must too.
10. The background engine (the daily job) opens the database with
   `AppDatabase.open(ownConnection: true)`. The ordinary open would hand it
   the app's own connection — sqflite keeps one per process — and closing it
   there would close it for the app.

What each version did:

| Version | What |
| --- | --- |
| 1 | Everything: products, units, currencies, invoices, customers, accounts, card codes, audit log |
| 2 | No table change: the name search columns recomputed with the stronger Arabic normalization |
| 3 | Normalized, indexed search columns on the invoice snapshots (archive search at 50,000 invoices) |
| 4 | What selling card codes needs: batch expiry, status notes, sale snapshots, audit product columns |
| 5 | The debt ledger rebuilt (types, direction, receipts, never-edited triggers); credit limits |
| 6 | The undo record of a bulk price change |
| 7 | `products.barcode` unique (duplicates cleared, logged as `BARCODE_DEDUP`); short codes stored the way they are looked up |
| 8 | Void and returns: `invoices.voided_at` / `void_reason` and the renewal dates before the sale; `invoice_returns` + `invoice_return_items`; the ledger rebuilt once more for the RETURN type (`return_id`, `return_no`), every row and id kept |

## Printers

Receipts are rendered as a picture and sent as ESC/POS raster or TSPL bitmap
(`lib/core/printing/`). A printer works without setup:

- A printer the app knows by its Bluetooth name gets a built-in profile
  (`lib/core/printing/printer_detect.dart`). **XP-365B** → TSPL, 512 dots,
  centred. Add a model there when one is tested on paper.
- Any other printer is asked once, on the first connection: a status
  question in each language, 0.4 s each. The one it answers is the one it
  speaks; a printer that answers nothing is taken for ESC/POS, 512 dots on
  80 mm paper (384 on 58 mm).
- The answer is remembered per printer. Settings → Invoice & printing →
  Printer diagnostics has "Detect the printer's language", the two language
  tests, the image modes and pacing; calibration (moving or narrowing the
  print) is under Advanced there.

## The error log

No crash service, no internet. An error nobody caught is written to
`<app files>/logs/errors-*.log` (rotating, under 1 MB in all;
`lib/core/logging/`), a crash on the Android side to `errors-native.log`
(`CrashLog.kt`). **Settings → About → Share error log** hands them to the
share sheet as one text file with the version, the database version and the
license state on top. The values a database error quotes (names, amounts) are
cut off before they are written. Read the stack traces with the symbols of
the same build (above).

## Release checklist

Before the build:

- [ ] `version:` raised in `pubspec.yaml`; the version code is higher than
      the last release.
- [ ] `flutter analyze` — no issues. `flutter test --concurrency=1` — all
      green.
- [ ] `git status` clean; the commit is pushed.
- [ ] `licensePublicKeyHex` and `expectedSigningCertSha256` are filled in;
      `developerWhatsApp` is your number.

The build:

- [ ] `pwsh tool/build_release.ps1` ends with "certificate matches" and no
      warning.
- [ ] `releases/<version>/` copied to the backup places.

On a real phone, with the APK from `releases/<version>/` (not a debug build):

- [ ] Installs over the previous version and the data is still there.
- [ ] Settings → About shows the version and build number; no "Developer
      tools" section.
- [ ] A new phone starts its trial; the request code is shown; a code issued
      for it activates it; the shop name is on the invoice.
- [ ] A sale: one tap on Save, the invoice prints and shares.
- [ ] The printer was found without choosing a language (try the shop's
      XP-365B and one ordinary receipt printer).
- [ ] A barcode scan with the camera.
- [ ] A backup is made, and restored on the same phone.
- [ ] The daily report or backup runs at its time **while the app is open**,
      and a sale still saves afterwards.
- [ ] Settings → About → Share error log opens the share sheet.

After handing it out: write the customer, the request code and the license
number down (the key generator's `issued.csv` does it), and keep the APK you
gave them.

/// The three constants licensing stands on. Nothing in this file is secret.
///
/// THE PRIVATE KEY IS NOT HERE AND MUST NEVER BE: it exists only in the key
/// file `souqi_keygen init` wrote on the developer's laptop (and its offline
/// backups). This repository — source, assets, tests — holds public values
/// only.
library;

/// The developer's Ed25519 PUBLIC key, 64 hex characters, as printed by
///
///     dart run bin/keygen.dart init --out <key file>
///
/// in ../souqi_keygen. Every activation code and PIN reset code is checked
/// against it. Empty = not set yet: the trial runs, but no code can be
/// accepted (and the activation screen says so).
///
/// Replacing it invalidates every license already issued with the old key.
const String licensePublicKeyHex = 'b79c540aae4ee2d32aed55ffb8cb25f3bd4e9c5136bf05846689c5fd3527652c';

/// Mixed into the device hash (with ANDROID_ID and the package name), so the
/// request code of a phone means nothing to another app. Fixed for the life
/// of the product: changing it changes every phone's request code and so
/// invalidates every license already issued.
const String licenseDeviceSalt = 'souqi-device-16400f75d8a914f24b22e1355c5d8b3d';

/// SHA-256 of the certificate the RELEASE APK is signed with, 64 hex
/// characters (colons and case do not matter). A copy of the app that was
/// modified and signed again by someone else has another certificate and
/// refuses to sell.
///
/// PHASE 6 fills this in from the release keystore:
///
///     keytool -list -v -keystore <release.jks> -alias <alias>
///
/// (the line "SHA256:"). Until it is filled in, only DEBUG builds skip the
/// check; a release or profile build reports itself as not sealed.
const String expectedSigningCertSha256 = '13996c9e997a6e33418ff680c44b5624dcd275579b923954e378221ef7aa18c2';

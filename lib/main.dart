import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/security/vault_session.dart';
import 'core/storage/secure_store.dart';
import 'core/storage/vault_paths.dart';
import 'injection.dart';
import 'platform/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final paths = await VaultPaths.resolve();
  final store = SecureStore();
  final platform = PlatformServices();

  // iOS keeps Keychain items across uninstall. If our files are gone but the Keychain says a
  // vault exists, it belongs to a deleted install: start fresh.
  if (!await paths.installMarker.exists()) {
    await store.deleteAll();
    await platform.disableBiometric().catchError((_) {});
  }
  await paths.ensure();
  await paths.installMarker.create();
  await platform.excludeFromBackup(paths.root.path);
  await paths.clearTemp();
  await VaultPaths.sweepPickerLeftovers();

  final session = VaultSession(isConfigured: await store.readKeyMaterial() != null);
  final autoLock = await store.readAutoLock();
  if (autoLock != null) session.autoLockAfter = autoLock;

  runApp(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(session),
        secureStoreProvider.overrideWithValue(store),
        vaultPathsProvider.overrideWithValue(paths),
        platformServicesProvider.overrideWithValue(platform),
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ],
      child: const ColorMatchApp(),
    ),
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/encryption/aead.dart';
import 'core/encryption/chunked_cipher.dart';
import 'core/security/key_hierarchy.dart';
import 'core/security/vault_session.dart';
import 'core/storage/secure_store.dart';
import 'core/storage/vault_paths.dart';
import 'data/datasources/media_stream_server.dart';
import 'data/datasources/vault_database.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/game_repository_impl.dart';
import 'data/repositories/media_repository_impl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/game_repository.dart';
import 'domain/repositories/media_repository.dart';
import 'platform/platform_services.dart';

// Bootstrapped in main() and supplied through ProviderScope overrides.
final sessionProvider = Provider<VaultSession>((ref) => throw UnimplementedError());
final secureStoreProvider = Provider<SecureStore>((ref) => throw UnimplementedError());
final vaultPathsProvider = Provider<VaultPaths>((ref) => throw UnimplementedError());
final platformServicesProvider = Provider<PlatformServices>((ref) => throw UnimplementedError());
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final aeadProvider = Provider((ref) => Aead());
final keyHierarchyProvider = Provider((ref) => KeyHierarchy(ref.watch(aeadProvider)));
final chunkedCipherProvider = Provider((ref) => ChunkedCipher(ref.watch(aeadProvider)));

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    store: ref.watch(secureStoreProvider),
    keys: ref.watch(keyHierarchyProvider),
    session: ref.watch(sessionProvider),
    platform: ref.watch(platformServicesProvider),
  ),
);

final vaultDatabaseProvider = Provider((ref) {
  final db = VaultDatabase(ref.watch(vaultPathsProvider).databasePath);
  ref.onDispose(db.close);
  return db;
});

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepositoryImpl(
    database: ref.watch(vaultDatabaseProvider),
    paths: ref.watch(vaultPathsProvider),
    keys: ref.watch(keyHierarchyProvider),
    cipher: ref.watch(chunkedCipherProvider),
    session: ref.watch(sessionProvider),
    platform: ref.watch(platformServicesProvider),
    server: MediaStreamServer(ref.watch(chunkedCipherProvider)),
  ),
);

final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => GameRepositoryImpl(ref.watch(sharedPreferencesProvider)),
);

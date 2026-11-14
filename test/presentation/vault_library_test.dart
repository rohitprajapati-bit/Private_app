import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/core/security/vault_session.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/domain/entities/media_item.dart';
import 'package:private_app/domain/entities/vault_library.dart';
import 'package:private_app/domain/repositories/media_repository.dart';
import 'package:private_app/injection.dart';
import 'package:private_app/presentation/vault/vault_providers.dart';

class _FakeMediaRepository implements MediaRepository {
  final library = VaultLibrary(
    items: [
      MediaItem(
        id: 'a',
        type: MediaType.photo,
        name: 'beach',
        extension: 'jpg',
        sizeBytes: 10,
        importedAt: DateTime(2026),
      ),
    ],
  );

  @override
  Future<VaultLibrary> load() async => library;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('items reappear after the vault locks and unlocks while the screen stays open', () async {
    final session = VaultSession(isConfigured: true)..unlock(randomBytes(32));
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(session),
        mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository()),
      ],
    );
    addTearDown(container.dispose);
    // Simulates the open vault screen listening to the provider.
    final subscription = container.listen(vaultLibraryProvider, (_, _) {});
    addTearDown(subscription.close);

    expect((await container.read(vaultLibraryProvider.future)).items, hasLength(1));

    session.lock(); // app sent to background
    expect((await container.read(vaultLibraryProvider.future)).items, isEmpty);

    session.unlock(randomBytes(32)); // owner unlocks again
    expect((await container.read(vaultLibraryProvider.future)).items, hasLength(1));
  });

  test('changes started after an auto-lock are dropped, not thrown', () async {
    final session = VaultSession(isConfigured: true)..unlock(randomBytes(32));
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(session),
        mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vaultLibraryProvider.future);

    session.lock(); // e.g. idle timeout while the "New album" dialog is open
    final notifier = container.read(vaultLibraryProvider.notifier);
    expect(await notifier.createAlbum('Trips'), isNull);
    await notifier.renameAlbum('x', 'y');
    await notifier.deleteAlbum('x');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/media_item.dart';
import '../../injection.dart';
import '../../routes/app_router.dart';
import '../albums/albums_tab.dart';
import '../gallery/media_grid.dart';
import '../sharing/shared_tab.dart';
import 'media_actions.dart';

class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Admin role: keep serving paired viewers while the vault is open.
    ref.read(sharingHostProvider).startIfPaired().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Leaving the vault always locks it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(sessionProvider).lock();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Private'),
          leading: IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_rounded),
            onPressed: () => ref.read(sessionProvider).lock(),
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => context.go(Routes.vaultSettings),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: const [
              MediaGrid(type: MediaType.photo, basePath: Routes.vault),
              MediaGrid(type: MediaType.video, basePath: Routes.vault),
              AlbumsTab(),
              SharedTab(),
            ],
          ),
        ),
        floatingActionButton: _tab == 3
            ? null
            : _tab == 2
            ? FloatingActionButton.extended(
                onPressed: () => AlbumsTab.create(context, ref),
                icon: const Icon(Icons.create_new_folder_rounded),
                label: const Text('New album'),
              )
            : FloatingActionButton(
                tooltip: _tab == 0 ? 'Add photos' : 'Add videos',
                onPressed: () => MediaActions.import(context, ref, _tab == 0 ? MediaType.photo : MediaType.video),
                child: const Icon(Icons.add_rounded),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.photo_library_rounded), label: 'Photos'),
            NavigationDestination(icon: Icon(Icons.video_library_rounded), label: 'Videos'),
            NavigationDestination(icon: Icon(Icons.folder_rounded), label: 'Albums'),
            NavigationDestination(icon: Icon(Icons.people_alt_rounded), label: 'Shared'),
          ],
        ),
      ),
    );
  }
}

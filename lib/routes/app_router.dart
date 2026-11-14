import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../injection.dart';
import '../presentation/albums/album_screen.dart';
import '../presentation/authentication/unlock_screen.dart';
import '../presentation/game/game_screen.dart';
import '../presentation/game/home_screen.dart';
import '../presentation/game/levels_screen.dart';
import '../presentation/gallery/photo_viewer_screen.dart';
import '../presentation/onboarding/setup_screen.dart';
import '../presentation/online/online_library_screen.dart';
import '../presentation/online/online_viewers.dart';
import '../presentation/settings/game_settings_screen.dart';
import '../presentation/settings/vault_settings_screen.dart';
import '../presentation/sharing/sharing_screen.dart';
import '../presentation/vault/vault_home_screen.dart';
import '../presentation/video_player/video_player_screen.dart';

abstract final class Routes {
  static const setup = '/setup';
  static const home = '/';
  static const levels = '/levels';
  static const gameSettings = '/settings';
  static const unlock = '/unlock';
  static const vault = '/vault';
  static const vaultSettings = '/vault/settings';
  static const sharing = '/vault/sharing';
  static const online = '/vault/online';

  static String onlinePhoto(String id) => '/vault/online/photo/$id';
  static String onlineVideo(String id) => '/vault/online/video/$id';

  static String play(int level) => '/play?level=$level';
  static String album(String id) => '/vault/album/$id';

  /// [base] is `/vault` or an album path, so back navigation returns to where the user was.
  static String photo(String base, String id) => '$base/photo/$id';
  static String video(String base, String id) => '$base/video/$id';
}

List<GoRoute> _mediaRoutes() => [
  GoRoute(
    path: 'photo/:id',
    builder: (context, state) => PhotoViewerScreen(
      initialId: state.pathParameters['id']!,
      albumId: state.pathParameters['albumId'],
      orderedIds: state.extra is List<String> ? state.extra! as List<String> : null,
    ),
  ),
  GoRoute(
    path: 'video/:id',
    builder: (context, state) => VideoPlayerScreen(id: state.pathParameters['id']!),
  ),
];

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);
  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!session.isConfigured) return location == Routes.setup ? null : Routes.setup;
      if (location == Routes.setup) return Routes.home;
      // Every vault route requires an unlocked session; locking bounces back to the game.
      if (location.startsWith(Routes.vault) && !session.isUnlocked) return Routes.home;
      if (location == Routes.unlock) {
        if (session.isUnlocked) return Routes.vault;
        // Reachable only right after the secret in-game sequence.
        if (!session.entryGranted) return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.setup, builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'play',
            builder: (context, state) =>
                GameScreen(startLevel: int.tryParse(state.uri.queryParameters['level'] ?? '') ?? 1),
          ),
          GoRoute(path: 'levels', builder: (context, state) => const LevelsScreen()),
          GoRoute(path: 'settings', builder: (context, state) => const GameSettingsScreen()),
          GoRoute(path: 'unlock', builder: (context, state) => const UnlockScreen()),
        ],
      ),
      GoRoute(
        path: Routes.vault,
        builder: (context, state) => const VaultHomeScreen(),
        routes: [
          ..._mediaRoutes(),
          GoRoute(path: 'settings', builder: (context, state) => const VaultSettingsScreen()),
          GoRoute(path: 'sharing', builder: (context, state) => const SharingScreen()),
          GoRoute(
            path: 'online',
            builder: (context, state) => const OnlineLibraryScreen(),
            routes: [
              GoRoute(path: 'photo/:id', builder: (context, state) => OnlinePhotoScreen(id: state.pathParameters['id']!)),
              GoRoute(path: 'video/:id', builder: (context, state) => OnlineVideoScreen(id: state.pathParameters['id']!)),
            ],
          ),
          GoRoute(
            path: 'album/:albumId',
            builder: (context, state) => AlbumScreen(albumId: state.pathParameters['albumId']!),
            routes: _mediaRoutes(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

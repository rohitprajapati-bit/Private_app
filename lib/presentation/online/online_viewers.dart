import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../injection.dart';
import 'online_library_screen.dart';

/// View-only photo streamed from the broker. No save/share actions by design.
class OnlinePhotoScreen extends ConsumerWidget {
  const OnlinePhotoScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(remoteSessionProvider);
    final item = session.library?.itemById(id);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(item?.name ?? 'Photo'),
      ),
      body: item == null
          ? const Center(
              child: Text(
                'Not available',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : PhotoView(
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              loadingBuilder: (context, _) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (context, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
              imageProvider: NetworkImage(
                ref.read(brokerClientProvider).mediaUri(id).toString(),
                headers: session.headers,
              ),
            ),
    );
  }
}

/// View-only video streamed from the broker (range requests enable seeking). The player never
/// writes the file anywhere the user can reach; there is no download or export action.
class OnlineVideoScreen extends ConsumerStatefulWidget {
  const OnlineVideoScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<OnlineVideoScreen> createState() => _OnlineVideoScreenState();
}

class _OnlineVideoScreenState extends ConsumerState<OnlineVideoScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final client = ref.read(brokerClientProvider);
    final headers = ref.read(remoteSessionProvider).headers;
    final controller = VideoPlayerController.networkUrl(
      client.mediaUri(widget.id),
      httpHeaders: headers,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _error = 'This video could not be played.');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(remoteSessionProvider).library?.itemById(widget.id);
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(item?.name ?? 'Video'),
      ),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white70))
            : controller == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                  VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton(
                      iconSize: 48,
                      color: Colors.white,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_circle_rounded
                            : Icons.play_circle_rounded,
                      ),
                      onPressed: () => value.isPlaying
                          ? controller.pause()
                          : controller.play(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

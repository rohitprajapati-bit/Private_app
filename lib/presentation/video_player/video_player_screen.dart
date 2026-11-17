import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/security/vault_session.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';
import '../../injection.dart';
import '../gallery/media_grid.dart';
import '../vault/media_actions.dart';
import '../vault/vault_providers.dart';

/// Plays a vault video streamed from the loopback decrypting server.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  late final MediaRepository _repository;
  late final VaultSession _session;
  MediaItem? _item;
  bool _failed = false;
  bool _controls = true;
  bool _fullscreen = false;
  Timer? _hideTimer;
  Timer? _activityTimer;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(mediaRepositoryProvider);
    _session = ref.read(sessionProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final item = ref.read(mediaItemProvider(widget.id));
    if (item == null) return setState(() => _failed = true);
    _item = item;
    try {
      final uri = await _repository.videoUri(item);
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play();
      _scheduleHide();
      // Watching without touching the screen must not trigger the inactivity lock.
      _activityTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (controller.value.isPlaying) _session.recordActivity();
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false))
        setState(() => _controls = false);
    });
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _restoreSystemUi();
    }
    setState(() {});
  }

  static Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _activityTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    final item = _item;
    if (item != null) _repository.releaseVideo(item);
    if (_fullscreen) unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final item = _item;
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: Text(item?.name ?? '', overflow: TextOverflow.ellipsis),
                actions: [
                  if (item != null && !item.isShared) ...[
                    IconButton(
                      tooltip: 'Save to gallery',
                      icon: const Icon(Icons.download_rounded),
                      onPressed: () =>
                          MediaActions.export(context, ref, [item]),
                    ),
                    IconButton(
                      tooltip: 'Move to album',
                      icon: const Icon(Icons.drive_file_move_rounded),
                      onPressed: () =>
                          MediaActions.moveToAlbum(context, ref, [item]),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_rounded),
                      onPressed: () async {
                        await _controller?.pause();
                        if (!context.mounted) return;
                        if (await MediaActions.delete(context, ref, [item]) &&
                            context.mounted)
                          context.pop();
                      },
                    ),
                  ],
                ],
              ),
        body: SafeArea(
          top: !_fullscreen,
          bottom: !_fullscreen,
          child: _failed
              ? const Center(
                  child: Text(
                    'This video could not be played.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : controller == null
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _controls = !_controls);
                    if (_controls) _scheduleHide();
                  },
                  child: Stack(
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio == 0
                              ? 16 / 9
                              : controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      if (_controls)
                        _Controls(
                          controller: controller,
                          fullscreen: _fullscreen,
                          onFullscreen: _toggleFullscreen,
                          onInteract: _scheduleHide,
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onInteract,
  });

  final VideoPlayerController controller;
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black38,
        child: Column(
          children: [
            const Spacer(),
            IconButton(
              iconSize: 64,
              color: Colors.white,
              icon: Icon(
                value.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
              ),
              onPressed: () {
                if (value.isPlaying) {
                  controller.pause();
                } else {
                  if (position >= duration) controller.seekTo(Duration.zero);
                  controller.play();
                }
                onInteract();
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    formatDuration(position),
                    style: const TextStyle(color: Colors.white),
                  ),
                  Expanded(
                    child: Slider(
                      value: position.inMilliseconds.toDouble(),
                      max: duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: (v) {
                        controller.seekTo(Duration(milliseconds: v.round()));
                        onInteract();
                      },
                    ),
                  ),
                  Text(
                    formatDuration(duration),
                    style: const TextStyle(color: Colors.white),
                  ),
                  IconButton(
                    tooltip: fullscreen ? 'Exit full screen' : 'Full screen',
                    color: Colors.white,
                    icon: Icon(
                      fullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                    ),
                    onPressed: onFullscreen,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

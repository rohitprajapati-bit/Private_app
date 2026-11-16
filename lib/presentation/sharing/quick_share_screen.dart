import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/security/vault_session.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sharing/quick_share.dart';
import '../../data/sharing/sharing_protocol.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/vault_library.dart';
import '../../injection.dart';
import '../gallery/encrypted_image.dart';
import '../gallery/media_grid.dart';
import '../vault/vault_providers.dart';

/// Sends items to a nearby phone that has the Receive screen open: pick it from the list
/// (Bonjour) or scan the QR code it shows. Opened with no [ids], it first lets the owner
/// choose items.
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key, required this.ids});

  final List<String> ids;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _found = <DiscoveredDevice>[];
  StreamSubscription<DiscoveredDevice>? _search;
  bool _searching = false;
  ({int count, int bytes})? _summary;
  late List<String> _ids = widget.ids;

  // Read once: `ref` must not be used in dispose().
  late final QuickShareSender _sender;
  late final VaultSession _session;

  @override
  void initState() {
    super.initState();
    _sender = ref.read(quickShareSenderProvider);
    _session = ref.read(sessionProvider);
    _sender.reset();
    if (_ids.isNotEmpty) _ready();
  }

  @override
  void dispose() {
    unawaited(_search?.cancel());
    if (_sender.busy) _sender.cancel();
    super.dispose();
  }

  void _ready() {
    unawaited(_loadSummary());
    _scan();
  }

  void _picked(List<String> ids) {
    setState(() => _ids = ids);
    _ready();
  }

  Future<void> _loadSummary() async {
    final items = await _sender.sendable(_ids);
    if (mounted) setState(() => _summary = (count: items.length, bytes: items.fold(0, (sum, i) => sum + i.wire)));
  }

  void _scan() {
    unawaited(_search?.cancel());
    setState(() {
      _found.clear();
      _searching = true;
    });
    _search = _sender.discover().listen(
      (device) => setState(() => _found.add(device)),
      onError: (_) => _stopScan(),
      onDone: _stopScan,
    );
  }

  void _stopScan() {
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _sendTo(DiscoveredDevice receiver) async {
    await _search?.cancel();
    _stopScan();
    await _sender.send(receiver, _ids);
  }

  Future<void> _scanQr() async {
    // The camera permission prompt briefly backgrounds the app; don't lock the vault for it.
    final text = await _session.withoutAutoLock(
      () => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage())),
    );
    if (text == null || !mounted) return;
    final ticket = ReceiverTicket.decode(text);
    if (ticket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That is not a Receive code. Open Receive on the other phone.')),
      );
      return;
    }
    await _search?.cancel();
    _stopScan();
    await _sender.sendToTicket(ticket, _ids);
  }

  void _retry() {
    _sender.reset();
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    if (_ids.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose items to send')),
        body: SafeArea(child: _ItemPicker(onDone: _picked)),
      );
    }
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _sender,
          builder: (context, _) {
            final sender = _sender;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(
                  icon: Icons.send_rounded,
                  title: summary == null
                      ? 'Preparing…'
                      : summary.count == 0
                      ? 'Nothing to send'
                      : 'Sending ${_items(summary.count)} · ${formatBytes(summary.bytes)}',
                  subtitle: summary?.count == 0
                      ? 'Only your own photos and videos can be sent — not items shared with you view-only.'
                      : 'The other phone keeps its own copy in its hidden vault.',
                ),
                const SizedBox(height: 16),
                if (summary != null && summary.count > 0)
                  switch (sender.stage) {
                    SendStage.idle => _receiverList(),
                    SendStage.connecting => const _Busy(text: 'Connecting…'),
                    SendStage.awaitingAccept => _CodeCard(
                      title: 'Waiting for the other phone to accept',
                      code: sender.code!,
                      hint: 'It should show this same code.',
                      actions: [TextButton(onPressed: sender.cancel, child: const Text('Cancel'))],
                    ),
                    SendStage.sending => _ProgressCard(
                      verb: 'Sending',
                      progress: sender.progress,
                      onCancel: sender.cancel,
                    ),
                    SendStage.done => _ResultCard(
                      success: true,
                      text: _resultText('Sent', sender.progress),
                      primary: ('Done', () => Navigator.of(context).maybePop()),
                    ),
                    SendStage.declined => _ResultCard(
                      success: false,
                      text: 'The other phone declined.',
                      primary: ('Try again', _retry),
                    ),
                    SendStage.failed => _ResultCard(
                      success: false,
                      text: sender.error ?? 'Sending failed.',
                      primary: ('Try again', _retry),
                    ),
                  },
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _receiverList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR code'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Fastest: scan the code shown on the other phone\'s Receive screen. Works on the same '
              'Wi-Fi or when one phone is the other\'s hotspot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const Divider(height: 32),
            const Text('Or pick a nearby phone', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'The other phone must have Receive open and be on the same Wi-Fi.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (_searching) const LinearProgressIndicator(),
            for (final device in _found)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.phone_iphone_rounded)),
                title: Text(device.name),
                subtitle: const Text('Ready to receive'),
                trailing: const Icon(Icons.send_rounded),
                onTap: () => _sendTo(device),
              ),
            if (!_searching) ...[
              if (_found.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No phones found.', textAlign: TextAlign.center),
                ),
              OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.refresh_rounded), label: const Text('Search again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Multi-select grid of the owner's own items (never ones shared view-only).
class _ItemPicker extends ConsumerStatefulWidget {
  const _ItemPicker({required this.onDone});

  final ValueChanged<List<String>> onDone;

  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  final _selected = <String>{};
  MediaType? _type;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(vaultLibraryProvider);
    final repository = ref.watch(mediaRepositoryProvider);
    final accent = Theme.of(context).colorScheme.primary;
    return library.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not open the vault.')),
      data: (library) {
        final items = library.items
            .where((i) => !i.isShared && (_type == null || i.type == _type))
            .toList()
            .sortedBy(MediaSort.newest);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<MediaType?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('All')),
                        ButtonSegment(value: MediaType.photo, label: Text('Photos')),
                        ButtonSegment(value: MediaType.video, label: Text('Videos')),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) => setState(() => _type = s.first),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () => setState(() => _selected.addAll(items.map((i) => i.id))),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('Nothing to send yet.', style: TextStyle(color: AppColors.textMuted)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = _selected.contains(item.id);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (!_selected.remove(item.id)) _selected.add(item.id);
                          }),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                AnimatedScale(
                                  scale: selected ? 0.88 : 1,
                                  duration: const Duration(milliseconds: 150),
                                  child: EncryptedThumbnail(item: item, repository: repository),
                                ),
                                if (item.isVideo)
                                  const Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Icon(Icons.play_circle_fill_rounded, size: 18, color: Colors.white),
                                  ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Icon(
                                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: selected ? accent : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : () => widget.onDone(_selected.toList()),
                  icon: const Icon(Icons.send_rounded),
                  label: Text(_selected.isEmpty ? 'Select items' : 'Next · ${_items(_selected.length)}'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-screen camera that returns the first QR code it reads.
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.map((b) => b.rawValue).nonNulls.firstOrNull;
    if (value == null || _done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan code')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in Settings to scan, or pick the phone from the list instead.'
                      : 'The camera could not start.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Text(
              'Point at the code on the other phone\'s Receive screen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Makes this phone discoverable and accepts items from a nearby sender.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  String? _error;
  int _reloadedAt = 0;

  // Read once: `ref` must not be used in dispose().
  late final QuickShareReceiver _receiver;
  late final VaultLibraryNotifier _library;

  @override
  void initState() {
    super.initState();
    _receiver = ref.read(quickShareReceiverProvider);
    _library = ref.read(vaultLibraryProvider.notifier);
    _receiver.addListener(_onChange);
    unawaited(_start());
  }

  @override
  void dispose() {
    _receiver.removeListener(_onChange);
    unawaited(_receiver.stop());
    // Items committed before an abandoned transfer must still appear.
    unawaited(_library.reload());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _receiver.start();
    } on Object {
      if (mounted) setState(() => _error = 'Could not start receiving on this network.');
    }
  }

  /// Refreshes the gallery every 10 received items and when the transfer finishes.
  void _onChange() {
    final done = _receiver.progress.doneItems;
    final finished = _receiver.stage == ReceiveStage.done;
    if (done > _reloadedAt && (finished || done >= _reloadedAt + 10)) {
      _reloadedAt = done;
      unawaited(_library.reload());
    }
    if (_receiver.stage == ReceiveStage.ready) _reloadedAt = 0;
  }

  @override
  Widget build(BuildContext context) {
    final receiver = ref.watch(quickShareReceiverProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: receiver,
          builder: (context, _) {
            final offer = receiver.offer;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(
                  icon: Icons.move_to_inbox_rounded,
                  title: 'Ready to receive as "${receiver.deviceName}"',
                  subtitle: 'On the other phone: Send → choose items → Scan QR code (or pick this phone). '
                      'Keep this screen open. Items are saved only in this hidden vault.',
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  _ResultCard(success: false, text: _error!, primary: ('Retry', () {
                    setState(() => _error = null);
                    unawaited(_start());
                  }))
                else
                  switch (receiver.stage) {
                    ReceiveStage.off || ReceiveStage.ready => _QrCard(
                      ticket: receiver.ticket,
                      discoverable: receiver.discoverable,
                    ),
                    ReceiveStage.offered => _CodeCard(
                      title: '${offer!.sender.name} wants to send ${_items(offer.count)} (${formatBytes(offer.bytes)})',
                      code: offer.code,
                      hint: 'Accept only if the sending phone shows the same code.',
                      actions: [
                        TextButton(onPressed: receiver.decline, child: const Text('Decline')),
                        FilledButton(onPressed: receiver.accept, child: const Text('Accept')),
                      ],
                    ),
                    ReceiveStage.receiving => _ProgressCard(
                      verb: 'Receiving from ${receiver.sender?.name ?? 'sender'}',
                      progress: receiver.progress,
                      onCancel: receiver.receiveMore,
                    ),
                    ReceiveStage.done => _ResultCard(
                      success: receiver.progress.failed == 0,
                      text: _resultText('Received', receiver.progress),
                      primary: ('Done', () => Navigator.of(context).maybePop()),
                      secondary: ('Receive more', receiver.receiveMore),
                    ),
                  },
              ],
            );
          },
        ),
      ),
    );
  }
}

String _items(int n) => '$n item${n == 1 ? '' : 's'}';

String _resultText(String verb, TransferProgress p) {
  final parts = ['$verb ${_items(p.doneItems)}.'];
  if (p.skipped > 0) parts.add('${p.skipped} already on that phone.');
  if (p.failed > 0) parts.add('${p.failed} failed.');
  return parts.join(' ');
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      ],
    );
  }
}

/// The Receive screen's QR code. A new one is made for every transfer.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.ticket, required this.discoverable});

  final ReceiverTicket? ticket;
  final bool discoverable;

  @override
  Widget build(BuildContext context) {
    final ticket = this.ticket;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (ticket == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Connect to Wi-Fi, or join the other phone\'s hotspot, to show a code.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: ticket.encode(), size: 220, backgroundColor: Colors.white),
              ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              discoverable
                  ? 'Waiting for a sender… Scan this code, or pick this phone from the list.'
                  : 'Waiting for a sender… Scan this code to send (this phone isn\'t listed nearby).',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [const LinearProgressIndicator(), const SizedBox(height: 12), Text(text)],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.title, required this.code, required this.hint, required this.actions});

  final String title;
  final String code;
  final String hint;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
              '${code.substring(0, 3)} ${code.substring(3)}',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.verb, required this.progress, required this.onCancel});

  final String verb;
  final TransferProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final fraction = p.fraction;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(verb, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('${p.doneItems + p.failed} of ${p.totalItems}')),
                Text('${formatBytes(p.doneBytes)} / ${formatBytes(p.totalBytes)}'),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Keep the app open until this finishes.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.success, required this.text, required this.primary, this.secondary});

  final bool success;
  final String text;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 48,
              color: success ? Theme.of(context).colorScheme.primary : AppColors.danger,
            ),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                if (secondary case (final label, final onTap)) TextButton(onPressed: onTap, child: Text(label)),
                FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

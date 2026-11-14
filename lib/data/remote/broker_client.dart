import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/errors/failures.dart';
import '../../core/storage/secure_store.dart';
import 'remote_library.dart';

/// Talks to the Cloudflare Worker broker for the online (code-based) view-only library.
///
/// The user device holds only: a random device id, and the device token the broker issued
/// when a code was redeemed. It never holds any Google/Drive/Firebase credential. Media is
/// streamed from the broker with the two device headers; there is no "download" path — callers
/// get a URL + headers to stream, never a file.
class BrokerClient {
  BrokerClient(this._store, {required this.baseUrl});

  final SecureStore _store;
  final String baseUrl;

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<String> deviceId() async {
    final existing = await _store.readRemote(SecureStore.remoteDeviceId);
    if (existing != null) return existing;
    final id = _randomId();
    await _store.writeRemote(SecureStore.remoteDeviceId, id);
    return id;
  }

  Future<String?> _token() => _store.readRemote(SecureStore.remoteDeviceToken);

  /// True once a code has been redeemed on this device and not forgotten/revoked.
  Future<bool> hasAccess() async => (await _token()) != null;

  Future<String?> savedCode() => _store.readRemote(SecureStore.remoteCode);
  Future<String?> savedLibraryName() => _store.readRemote(SecureStore.remoteLibraryName);

  /// Headers every library/media/heartbeat request must carry. Pass these to `Image.network`
  /// and `VideoPlayerController.networkUrl` so streaming is authenticated.
  Future<Map<String, String>> authHeaders() async {
    return {'X-Device-Id': await deviceId(), 'X-Device-Token': await _token() ?? ''};
  }

  /// URL to stream one item (or its thumbnail). Only usable together with [authHeaders];
  /// without the headers the broker returns 401, so the URL alone is not a download link.
  Uri mediaUri(String itemId, {bool thumb = false}) =>
      Uri.parse('$baseUrl/v1/${thumb ? 'thumb' : 'media'}/${Uri.encodeComponent(itemId)}');

  /// Redeem an access code: registers this device and returns the library it unlocks.
  Future<RemoteLibrary> redeem(String code) async {
    final trimmed = code.trim().toUpperCase();
    final json = await _send('POST', '/v1/redeem', body: {
      'code': trimmed,
      'deviceId': await deviceId(),
      'name': Platform.isIOS ? 'iPhone' : 'Android phone',
      'platform': Platform.isIOS ? 'ios' : 'android',
    });
    final token = json['deviceToken'] as String?;
    final libJson = json['library'] as Map<String, dynamic>?;
    if (token == null || libJson == null) {
      throw const SharingFailure('The server sent an unexpected response.');
    }
    final library = RemoteLibrary.fromJson(libJson);
    await _store.writeRemote(SecureStore.remoteDeviceToken, token);
    await _store.writeRemote(SecureStore.remoteCode, trimmed);
    await _store.writeRemote(SecureStore.remoteLibraryName, library.name);
    return library;
  }

  /// Re-fetch the library this device already has access to. Null if no code was redeemed.
  Future<RemoteLibrary?> currentLibrary() async {
    if (!await hasAccess()) return null;
    final json = await _send('GET', '/v1/library');
    final library = RemoteLibrary.fromJson(json['library'] as Map<String, dynamic>);
    await _store.writeRemote(SecureStore.remoteLibraryName, library.name);
    return library;
  }

  /// Tell the broker this device is alive (updates the admin dashboard's last-seen).
  Future<void> heartbeat() async {
    if (!await hasAccess()) return;
    try {
      await _send('POST', '/v1/heartbeat');
    } on VaultFailure {
      // A missed heartbeat is harmless; the next one updates last-seen.
    }
  }

  /// Drop this device's access locally (does not touch the admin's grant).
  Future<void> forget() async {
    await _store.writeRemote(SecureStore.remoteDeviceToken, null);
    await _store.writeRemote(SecureStore.remoteCode, null);
    await _store.writeRemote(SecureStore.remoteLibraryName, null);
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, Object?>? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      (await authHeaders()).forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) return json;
      return _fail(response.statusCode, json);
    } on SocketException {
      throw const SharingFailure('Could not reach the server. Check your internet connection.');
    } on HttpException {
      throw const SharingFailure('Could not reach the server. Check your internet connection.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Never> _fail(int status, Map<String, dynamic> json) async {
    switch (json['error']) {
      case 'invalid_code':
        throw const SharingFailure('That code is not valid.');
      case 'code_disabled':
        throw const SharingFailure('This code has been turned off by the owner.');
      case 'code_expired':
        throw const SharingFailure('This code has expired.');
      case 'device_limit':
        throw const SharingFailure('This code is already in use on another device.');
      case 'revoked':
      case 'unauthorized':
        await forget();
        throw const SharingFailure('Your access to this library was removed.');
      default:
        throw SharingFailure('Something went wrong (error $status). Please try again.');
    }
  }

  static String _randomId() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

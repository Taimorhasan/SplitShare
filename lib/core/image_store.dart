import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class ImageTooLargeException implements Exception {
  @override
  String toString() =>
      'That photo is too large. Please choose a smaller one or crop it.';
}

/// Free image storage on Firestore (no Firebase Storage / Blaze plan needed).
///
/// Each image is one small document holding the JPEG bytes:
/// * `avatarImages/{uid}` — profile photos (readable by signed-in users)
/// * `receipts/{expenseId}` — receipt photos (readable by the expense's
///   participants only)
///
/// Images are referenced with `fsimg://<collection>/<id>?v=<version>`; the
/// version changes on every upload so caches refresh. Photos are shrunk by
/// the image picker before upload (Firestore documents max out at 1 MiB).
class ImageStore {
  ImageStore._();

  static const scheme = 'fsimg://';
  static const int maxBytes = 950 * 1024;

  static final _fs = FirebaseFirestore.instance;
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};

  static bool isStored(String? url) => url != null && url.startsWith(scheme);

  /// `collection/id` part of an fsimg url.
  static String _path(String url) => url.substring(scheme.length).split('?').first;

  static Future<String> _save(String collection, String id, Uint8List bytes) async {
    if (bytes.lengthInBytes > maxBytes) throw ImageTooLargeException();
    await _fs.collection(collection).doc(id).set({
      'data': Blob(bytes),
      'contentType': 'image/jpeg',
      'size': bytes.lengthInBytes,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 30));
    final url = '$scheme$collection/$id?v=${DateTime.now().millisecondsSinceEpoch}';
    _cache[url] = bytes;
    return url;
  }

  static Future<String> saveAvatar(String uid, Uint8List bytes) =>
      _save('avatarImages', uid, bytes);

  /// The expense document must exist first (rules check its participants).
  static Future<String> saveReceipt(String expenseId, Uint8List bytes) =>
      _save('receipts', expenseId, bytes);

  static Future<void> delete(String url) async {
    if (!isStored(url)) return;
    _cache.removeWhere((k, _) => k.startsWith(url.split('?').first));
    await _fs.doc(_path(url)).delete();
  }

  /// Deletes a receipt by expense id (before the expense itself is deleted).
  static Future<void> deleteReceipt(String expenseId) =>
      _fs.collection('receipts').doc(expenseId).delete();

  /// Loads image bytes (memory-cached; concurrent requests share one read).
  static Future<Uint8List?> load(String url) {
    final cached = _cache[url];
    if (cached != null) return Future.value(cached);
    return _inflight[url] ??= () async {
      try {
        final snap = await _fs.doc(_path(url)).get();
        final data = snap.data()?['data'];
        if (data is Blob) {
          final bytes = data.bytes;
          if (_cache.length > 80) _cache.remove(_cache.keys.first);
          _cache[url] = bytes;
          return bytes;
        }
        return null;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(url);
      }
    }();
  }

  /// Synchronous cache hit, for flicker-free rebuilds.
  static Uint8List? cached(String url) => _cache[url];
}

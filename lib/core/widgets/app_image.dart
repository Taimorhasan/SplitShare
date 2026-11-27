import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../image_store.dart';

/// Shows an image from either a web URL (e.g. a Google profile photo) or
/// SplitShare's free Firestore image store (`fsimg://…`).
class AppImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? error;
  final int? memCacheWidth;

  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.error,
    this.memCacheWidth,
  });

  static bool canShow(String? url) =>
      url != null && (url.startsWith('http') || ImageStore.isStored(url));

  @override
  Widget build(BuildContext context) {
    final fallback = error ?? const SizedBox.shrink();
    final waiting = placeholder ??
        const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );

    if (ImageStore.isStored(url)) {
      final hit = ImageStore.cached(url);
      Widget image(Uint8List bytes) => Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            cacheWidth: memCacheWidth,
            errorBuilder: (_, _, _) => fallback,
          );
      if (hit != null) return image(hit);
      return FutureBuilder(
        future: ImageStore.load(url),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return SizedBox(width: width, height: height, child: waiting);
          }
          final bytes = snap.data;
          return bytes == null
              ? SizedBox(width: width, height: height, child: fallback)
              : image(bytes);
        },
      );
    }

    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => waiting,
        errorWidget: (_, _, _) => fallback,
      );
    }
    return SizedBox(width: width, height: height, child: fallback);
  }
}

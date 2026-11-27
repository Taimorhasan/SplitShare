// Renders the SplitShare logo (the `AppLogo` widget) to the PNGs used for
// launcher / web / desktop icons, so every platform shows the exact same mark
// as the app itself.
//
// Regenerate icons after changing AppLogo:
//   flutter test tool/render_app_icon_test.dart
//   dart run flutter_launcher_icons
//
// Lives in tool/ (not test/) so it never runs as part of `flutter test`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitshare/core/widgets/illustration.dart';

const double _size = 1024;

String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_tester lives in <root>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (Directory('${dir.path}/bin/cache').existsSync()) return dir.path;
    dir = dir.parent;
  }
  throw StateError('Could not locate the Flutter SDK');
}

Future<void> _loadMaterialIcons() async {
  final file = File(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  await loader.load();
}

Future<void> _render(WidgetTester tester, Widget child, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: _size, height: _size, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File(path)..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render app icons', (tester) async {
    await _loadMaterialIcons();
    tester.view.physicalSize = const Size(_size, _size);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // iOS / macOS App Store style: full-bleed square (the OS applies the mask).
    await _render(
      tester,
      const AppLogo(size: _size, withShadow: false, cornerRadius: 0),
      'assets/icon/app_icon.png',
    );

    // Rounded tile on transparent background: Android legacy, web, Windows,
    // and the in-repo brand image.
    await _render(
      tester,
      const Padding(
        padding: EdgeInsets.all(_size * 0.06),
        child: AppLogo(size: _size * 0.88, withShadow: false, cornerRadius: 0.24),
      ),
      'assets/icon/app_icon_rounded.png',
    );

    // Android adaptive icon foreground. The launcher config adds a 16% inset,
    // which keeps the mark inside the adaptive-icon safe zone.
    await _render(
      tester,
      const Center(
        child: AppLogo(size: _size, foregroundOnly: true, withShadow: false),
      ),
      'assets/icon/app_icon_foreground.png',
    );
    await _render(
      tester,
      Container(color: AppLogo.brand),
      'assets/icon/app_icon_background.png',
    );

    expect(File('assets/icon/app_icon.png').existsSync(), isTrue);
  });
}

import 'dart:io';

import 'generated/frb_generated.dart';

/// Инициализация Rust Core (FRB).
///
/// На Windows ожидается, что нативная библиотека лежит в `rust/target/release/`.
/// См. [`RustCore`](generated/frb_generated.dart:16) и его `defaultExternalLibraryLoaderConfig`.
class RustCoreBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    // Web не является целевой платформой для данного этапа.
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError('Unsupported platform for RustCore init');
    }

    await RustCore.init();
    _initialized = true;
  }
}


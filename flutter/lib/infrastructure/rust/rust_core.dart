import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'generated/frb_generated.dart';
import '../logging/app_logger.dart';

/// Инициализация Rust Core (FRB).
///
/// Поддерживает два режима загрузки нативной библиотеки:
/// 1. **Packaged build (MSIX)**: DLL находится рядом с исполняемым файлом
/// 2. **Development/Debug**: DLL в дереве исходников (rust/target/release/)
///
/// Это критично для MSIX, где относительные пути из FRB codegen
/// (`../rust/target/release/`) не работают.
class RustCoreBootstrap {
  static bool _initialized = false;
  static Future<void>? _initFuture;
  static final Logger _log = AppLogger.create();

  /// Возвращает true, если Rust Core успешно инициализирован.
  static bool get isInitialized => _initialized;

  /// Инициализирует Rust Core, гарантируя единственный вызов.
  ///
  /// Использует кешированный Future для защиты от гонок при параллельных
  /// вызовах из разных мест приложения.
  static Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInit();
  }

  static Future<void> _doInit() async {
    try {
      // Web не является целевой платформой для данного этапа.
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        throw UnsupportedError('Unsupported platform for RustCore init');
      }

      // Определяем путь к нативной библиотеке
      final externalLibrary = _resolveExternalLibrary();

      await RustCore.init(externalLibrary: externalLibrary);
      _initialized = true;
    } catch (e) {
      // Сбрасываем Future чтобы позволить повторную попытку инициализации
      _initFuture = null;
      rethrow;
    }
  }

  /// Резолвит путь к нативной библиотеке Rust.
  ///
  /// Приоритет поиска:
  /// 1. Рядом с exe (packaged build, MSIX, installed app)
  /// 2. В дереве исходников release (development)
  /// 3. В дереве исходников debug (development debug)
  static ExternalLibrary _resolveExternalLibrary() {
    final config = _getPlatformConfig();
    return _resolveLibrary(config);
  }

  /// Конфигурация путей для конкретной платформы.
  static _PlatformConfig _getPlatformConfig() {
    final exeDir = _getExecutableDirectory();

    if (Platform.isWindows) {
      return _PlatformConfig(
        libraryType: 'DLL',
        packagedPath: p.normalize('$exeDir\\latera_rust.dll'),
        devReleasePath: p.normalize(
          '$exeDir\\..\\..\\..\\..\\..\\..\\rust\\target\\release\\latera_rust.dll',
        ),
        devDebugPath: p.normalize(
          '$exeDir\\..\\..\\..\\..\\..\\..\\rust\\target\\debug\\latera_rust.dll',
        ),
      );
    } else if (Platform.isMacOS) {
      return _PlatformConfig(
        libraryType: 'dylib',
        packagedPath: p.normalize('$exeDir/liblatera_rust.dylib'),
        // flutter/build/macos/Build/Products/Release/latera.app/Contents/MacOS/
        devReleasePath: p.normalize(
          '$exeDir/../../../../../../../rust/target/release/liblatera_rust.dylib',
        ),
        devDebugPath: p.normalize(
          '$exeDir/../../../../../../../rust/target/debug/liblatera_rust.dylib',
        ),
      );
    } else {
      return _PlatformConfig(
        libraryType: 'SO',
        packagedPath: p.normalize('$exeDir/liblatera_rust.so'),
        // flutter/build/linux/x64/release/bundle/
        devReleasePath: p.normalize(
          '$exeDir/../../../../../../rust/target/release/liblatera_rust.so',
        ),
        devDebugPath: p.normalize(
          '$exeDir/../../../../../../rust/target/debug/liblatera_rust.so',
        ),
      );
    }
  }

  /// Универсальный метод резолвинга библиотеки.
  ///
  /// Ищет библиотеку в порядке приоритета и возвращает первый найденный путь.
  static ExternalLibrary _resolveLibrary(_PlatformConfig config) {
    final searchPaths = [
      (config.packagedPath, 'packaged build'),
      (config.devReleasePath, 'development release'),
      (config.devDebugPath, 'development debug'),
    ];

    for (final (path, description) in searchPaths) {
      if (File(path).existsSync()) {
        _log.d('Loading Rust library from: $path ($description)');
        try {
          return ExternalLibrary.open(path);
        } catch (e) {
          throw StateError(
            'Failed to load Rust library at $path: $e\n'
            'The ${config.libraryType} exists but could not be loaded '
            '(corrupted or wrong architecture).',
          );
        }
      }
    }

    // Not found: throw descriptive error
    final searchedLocations = searchPaths
        .map((e) => '  ${searchPaths.indexOf(e) + 1}. ${e.$1} (${e.$2})')
        .join('\n');
    throw StateError(
      'Rust library not found. Searched locations:\n$searchedLocations\n'
      'Build Rust: cargo build (--release for production)',
    );
  }

  /// Возвращает директорию исполняемого файла.
  static String _getExecutableDirectory() {
    return File(Platform.resolvedExecutable).parent.path;
  }
}

/// Конфигурация путей для платформо-специфичного резолвинга.
class _PlatformConfig {
  final String libraryType;
  final String packagedPath;
  final String devReleasePath;
  final String devDebugPath;

  const _PlatformConfig({
    required this.libraryType,
    required this.packagedPath,
    required this.devReleasePath,
    required this.devDebugPath,
  });
}

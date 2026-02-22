/// Тип лицензии приложения.
enum LicenseType {
  /// Бесплатная версия с ограничениями.
  free,

  /// Платная версия с полным функционалом.
  pro,
}

/// Состояние лицензии.
enum LicenseStatus {
  /// Лицензия активна.
  active,

  /// Лицензия истекла.
  expired,

  /// Лицензия отозвана.
  revoked,

  /// Лицензия не найдена.
  notFound,

  /// Ошибка проверки.
  error,
}

/// Информация о лицензии.
///
/// Immutable-сущность, представляющая текущее состояние лицензии.
class License {
  /// Тип лицензии.
  final LicenseType type;

  /// Текущий статус лицензии.
  final LicenseStatus status;

  /// Идентификатор лицензии (опционально).
  final String? licenseId;

  /// Email пользователя (опционально).
  final String? userEmail;

  /// Дата истечения лицензии (опционально, null = бессрочная).
  final DateTime? expiresAt;

  /// Дата активации лицензии.
  final DateTime? activatedAt;

  /// Сообщение об ошибке (если status == error).
  final String? errorMessage;

  const License({
    required this.type,
    required this.status,
    this.licenseId,
    this.userEmail,
    this.expiresAt,
    this.activatedAt,
    this.errorMessage,
  });

  /// Лицензия по умолчанию (Free, активная).
  static const License defaultFree = License(
    type: LicenseType.free,
    status: LicenseStatus.active,
  );

  /// Проверяет, активна ли лицензия.
  bool get isActive => status == LicenseStatus.active;

  /// Проверяет, является ли лицензия Pro.
  bool get isPro => type == LicenseType.pro && isActive;

  /// Проверяет, является ли лицензия Free.
  bool get isFree => type == LicenseType.free || !isActive;

  /// Проверяет, истекла ли лицензия (по дате).
  bool get isExpiredByDate {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Создаёт копию с обновлёнными полями.
  License copyWith({
    LicenseType? type,
    LicenseStatus? status,
    String? licenseId,
    String? userEmail,
    DateTime? expiresAt,
    DateTime? activatedAt,
    String? errorMessage,
  }) {
    return License(
      type: type ?? this.type,
      status: status ?? this.status,
      licenseId: licenseId ?? this.licenseId,
      userEmail: userEmail ?? this.userEmail,
      expiresAt: expiresAt ?? this.expiresAt,
      activatedAt: activatedAt ?? this.activatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'License(type: $type, status: $status, licenseId: $licenseId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is License &&
        other.type == type &&
        other.status == status &&
        other.licenseId == licenseId &&
        other.userEmail == userEmail &&
        other.expiresAt == expiresAt &&
        other.activatedAt == activatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      status,
      licenseId,
      userEmail,
      expiresAt,
      activatedAt,
    );
  }
}

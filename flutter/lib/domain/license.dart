/// Тип лицензии приложения.
enum LicenseType {
  /// Бесплатная версия с ограничениями.
  free,

  /// Платная версия с полным функционалом.
  pro,
}

/// Режим лицензии (Basic / ProTrial / Pro).
enum LicenseMode {
  /// Бесплатная версия с ограничениями (триал истёк, Pro не куплен).
  basic,

  /// Бесплатный 3-дневный триал Pro-функций.
  proTrial,

  /// Оплаченная Pro версия.
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

  /// Режим лицензии (basic / proTrial / pro).
  final LicenseMode mode;

  /// Дата окончания триала (null если триал не активен).
  final DateTime? trialExpiresAt;

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
    this.mode = LicenseMode.basic,
    this.trialExpiresAt,
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

  /// Проверяет, является ли лицензия Pro (включая триал).
  bool get isPro =>
      (type == LicenseType.pro || mode == LicenseMode.pro || mode == LicenseMode.proTrial) &&
      isActive;

  /// Проверяет, является ли лицензия Free.
  bool get isFree => mode == LicenseMode.basic || !isActive;

  /// Проверяет, активен ли Pro-триал.
  bool get isProTrial => mode == LicenseMode.proTrial && isActive;

  /// Проверяет, истекла ли лицензия (по дате).
  bool get isExpiredByDate {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Создаёт копию с обновлёнными полями.
  License copyWith({
    LicenseType? type,
    LicenseStatus? status,
    LicenseMode? mode,
    DateTime? trialExpiresAt,
    String? licenseId,
    String? userEmail,
    DateTime? expiresAt,
    DateTime? activatedAt,
    String? errorMessage,
  }) {
    return License(
      type: type ?? this.type,
      status: status ?? this.status,
      mode: mode ?? this.mode,
      trialExpiresAt: trialExpiresAt ?? this.trialExpiresAt,
      licenseId: licenseId ?? this.licenseId,
      userEmail: userEmail ?? this.userEmail,
      expiresAt: expiresAt ?? this.expiresAt,
      activatedAt: activatedAt ?? this.activatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'License(type: $type, status: $status, mode: $mode, licenseId: $licenseId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is License &&
        other.type == type &&
        other.status == status &&
        other.mode == mode &&
        other.trialExpiresAt == trialExpiresAt &&
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
      mode,
      trialExpiresAt,
      licenseId,
      userEmail,
      expiresAt,
      activatedAt,
    );
  }
}

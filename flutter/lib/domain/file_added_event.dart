/// Domain-событие: добавлен новый файл.
///
/// Domain слой не зависит от Flutter/плагинов.
class FileAddedEvent {
  final String fileName;
  final String? fullPath;
  final DateTime occurredAt;

  const FileAddedEvent({
    required this.fileName,
    required this.occurredAt,
    this.fullPath,
  });
}


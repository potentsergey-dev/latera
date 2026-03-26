/// Domain-событие: файл удалён из отслеживаемой директории.
///
/// Domain слой не зависит от Flutter/плагинов.
class FileRemovedEvent {
  final String fileName;
  final String? fullPath;
  final DateTime occurredAt;

  const FileRemovedEvent({
    required this.fileName,
    required this.occurredAt,
    this.fullPath,
  });
}

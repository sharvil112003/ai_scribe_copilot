class ChunkItem {
  final int? id;
  final String sessionId;
  final int chunkNumber;
  final String filePath;
  final String mimeType;
  final String status; // pending|uploading|uploaded|failed
  final int retries;
  final DateTime createdAt;

  ChunkItem({
    this.id,
    required this.sessionId,
    required this.chunkNumber,
    required this.filePath,
    required this.mimeType,
    required this.status,
    required this.retries,
    required this.createdAt,
  });

  ChunkItem copyWith({int? id, String? status, int? retries}) => ChunkItem(
    id: id ?? this.id,
    sessionId: sessionId,
    chunkNumber: chunkNumber,
    filePath: filePath,
    mimeType: mimeType,
    status: status ?? this.status,
    retries: retries ?? this.retries,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'sessionId': sessionId, 'chunkNumber': chunkNumber,
    'filePath': filePath, 'mimeType': mimeType, 'status': status,
    'retries': retries, 'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static ChunkItem fromMap(Map<String, dynamic> m) => ChunkItem(
    id: m['id'] as int?,
    sessionId: m['sessionId'],
    chunkNumber: m['chunkNumber'],
    filePath: m['filePath'],
    mimeType: m['mimeType'],
    status: m['status'],
    retries: m['retries'] ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt']),
  );
}

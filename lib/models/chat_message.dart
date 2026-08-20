class ChatMessage {
  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isAi;
  final bool isCoach;
  final bool read;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isAi = false,
    this.isCoach = false,
    this.read = true,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) => ChatMessage(
        id: id,
        senderUid: map['senderUid'] ?? '',
        senderName: map['senderName'] ?? '',
        text: map['text'] ?? '',
        timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
        isAi: map['isAi'] ?? false,
        isCoach: map['isCoach'] ?? false,
        read: map['read'] ?? map['isCoach'] == true,
      );

  Map<String, dynamic> toMap() => {
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'isAi': isAi,
        'isCoach': isCoach,
        'read': read,
      };
}

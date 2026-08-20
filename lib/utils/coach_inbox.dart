import '../models/chat_message.dart';

/// Coach-inbox unread: last message is from the athlete and newer than
/// the coach's last-read timestamp for that thread.
bool coachThreadIsUnread(ChatMessage? last, DateTime? lastReadAt) {
  if (last == null || last.isCoach || last.isAi) return false;
  if (lastReadAt == null) return true;
  return last.timestamp.isAfter(lastReadAt);
}

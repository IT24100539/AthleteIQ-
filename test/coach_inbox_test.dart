import 'package:flutter_test/flutter_test.dart';
import 'package:athleteiq/models/chat_message.dart';
import 'package:athleteiq/utils/coach_inbox.dart';

ChatMessage msg({
  required bool isCoach,
  required DateTime ts,
}) {
  return ChatMessage(
    id: '1',
    senderUid: isCoach ? 'coach' : 'athlete',
    senderName: isCoach ? 'Coach' : 'Athlete',
    text: 'hi',
    timestamp: ts,
    isCoach: isCoach,
  );
}

void main() {
  final t = DateTime(2026, 8, 15, 12);

  test('empty thread is not unread', () {
    expect(coachThreadIsUnread(null, null), isFalse);
  });

  test('last message from coach is not unread', () {
    expect(coachThreadIsUnread(msg(isCoach: true, ts: t), null), isFalse);
  });

  test('athlete message with no lastRead is unread', () {
    expect(coachThreadIsUnread(msg(isCoach: false, ts: t), null), isTrue);
  });

  test('athlete message after lastRead is unread', () {
    expect(
      coachThreadIsUnread(msg(isCoach: false, ts: t), t.subtract(const Duration(minutes: 1))),
      isTrue,
    );
  });

  test('athlete message at or before lastRead is read', () {
    expect(coachThreadIsUnread(msg(isCoach: false, ts: t), t), isFalse);
    expect(
      coachThreadIsUnread(msg(isCoach: false, ts: t), t.add(const Duration(seconds: 1))),
      isFalse,
    );
  });
}

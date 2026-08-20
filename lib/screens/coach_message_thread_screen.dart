import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/athlete.dart';
import '../models/chat_message.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';

/// Coach reply thread — same `athletes/{uid}/messages/` collection as the athlete chat.
class CoachMessageThreadScreen extends StatefulWidget {
  final AthleteProfile athlete;
  final String coachUid;

  const CoachMessageThreadScreen({
    super.key,
    required this.athlete,
    required this.coachUid,
  });

  @override
  State<CoachMessageThreadScreen> createState() => _CoachMessageThreadScreenState();
}

class _CoachMessageThreadScreenState extends State<CoachMessageThreadScreen> {
  final _fs = FirestoreService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _markedRead = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markReadOnce() {
    if (_markedRead) return;
    _markedRead = true;
    _fs.markInboxThreadRead(widget.coachUid, widget.athlete.uid);
  }

  Future<void> _sendReply() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() => _sending = true);

    try {
      await _fs.sendCoachReply(widget.athlete.uid, text);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.mint),
              ),
              child: Text(
                _initials(widget.athlete.name),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mint,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.athlete.name.isNotEmpty ? widget.athlete.name : 'Athlete',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Athlete',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _fs.streamCoachMessages(widget.athlete.uid),
                builder: (context, snapshot) {
                  final blocked = asyncBody(
                    snapshot,
                    heading: 'Could not load messages',
                  );
                  if (blocked != null) return blocked;

                  final messages = snapshot.data ?? [];
                  if (messages.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadOnce());
                  }

                  if (messages.isEmpty) {
                    return const Center(
                      child: EmptyState(
                        icon: Icons.chat_bubble_outline,
                        heading: 'No messages yet',
                        subtext:
                            'This thread is empty. Reply below — it writes to the same messages collection the athlete uses.',
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      return _CoachChatBubble(message: messages[i]);
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendReply(),
                      decoration: const InputDecoration(
                        hintText: 'Reply to athlete…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.mint,
                            ),
                          )
                        : const Icon(Icons.send, color: AppColors.mint),
                    onPressed: _sending ? null : _sendReply,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _CoachChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isCoach;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppColors.mint : AppColors.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe ? AppColors.mint : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: isMe ? AppColors.mintDark : AppColors.textPrimary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('h:mm a').format(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? AppColors.mintDark.withValues(alpha: 0.6) : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

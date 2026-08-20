import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/athlete.dart';
import '../models/chat_message.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/stream_fallback.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import 'connect_coach_screen.dart';

class MessageCoachScreen extends StatefulWidget {
  final String athleteUid;

  const MessageCoachScreen({super.key, required this.athleteUid});

  @override
  State<MessageCoachScreen> createState() => _MessageCoachScreenState();
}

class _MessageCoachScreenState extends State<MessageCoachScreen> {
  final _fs = FirestoreService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final Stream<List<ChatMessage>> _messagesStream;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messagesStream = emitOnError(
      _fs.streamCoachMessages(widget.athleteUid),
      const <ChatMessage>[],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() => _sending = true);

    try {
      await _fs.sendCoachMessage(widget.athleteUid, text);
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
    return StreamBuilder<AthleteProfile>(
      stream: _fs.athleteProfile(widget.athleteUid),
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Message coach')),
            body: asyncError(
              heading: 'Could not load this chat',
              error: profileSnap.error,
            ),
          );
        }

        final coachUid = profileSnap.data?.coachUid;
        final waitingProfile =
            profileSnap.connectionState == ConnectionState.waiting && !profileSnap.hasData;

        return StreamBuilder<Map<String, String?>>(
          stream: (coachUid == null || coachUid.isEmpty)
              ? Stream.value(const {'name': null, 'email': null})
              : _fs.streamCoachDisplay(coachUid),
          builder: (context, coachSnap) {
            final coachName = (coachSnap.data?['name'] ?? '').trim();
            final hasCoach = coachUid != null && coachUid.isNotEmpty;
            final displayName = !hasCoach
                ? 'Connect your coach'
                : (coachName.isEmpty ? 'Your coach' : coachName);
            final initials = !hasCoach || coachName.isEmpty ? '?' : _initials(coachName);

            if (!waitingProfile && !hasCoach) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Connect coach'),
                  centerTitle: true,
                ),
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Text(
                      'Join your coach\'s roster',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask your coach for their invite code, then enter it below. You\'ll be able to message them and they\'ll see your training once you\'re linked.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ConnectCoachForm(athleteUid: widget.athleteUid),
                  ],
                ),
              );
            }

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
                      child: waitingProfile
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.mint,
                              ),
                            )
                          : Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.mint,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          waitingProfile ? 'Loading…' : displayName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          hasCoach ? 'Your coach' : 'Link a coach in Profile',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<ChatMessage>>(
                        stream: _messagesStream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return kAsyncLoading;
                          }

                          final messages = snapshot.data ?? [];
                          if (messages.isEmpty) {
                            return const Center(
                              child: EmptyState(
                                icon: Icons.chat_bubble_outline,
                                heading: 'Send your coach a message',
                                subtext:
                                    'This thread is empty. Nothing here is a sample conversation.',
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            itemCount: messages.length,
                            itemBuilder: (ctx, i) {
                              final m = messages[i];
                              return _ChatBubble(message: m);
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
                              enabled: hasCoach,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                              decoration: InputDecoration(
                                hintText: hasCoach
                                    ? 'Message your coach…'
                                    : 'Link a coach to send messages',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
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
                            onPressed: !hasCoach || _sending ? null : _sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = !message.isCoach;

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

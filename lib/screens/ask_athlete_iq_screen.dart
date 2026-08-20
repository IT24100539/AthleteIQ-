import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../utils/stream_fallback.dart';
import '../widgets/async_body.dart';

class AskAthleteIQScreen extends StatefulWidget {
  final String athleteUid;
  final bool showAppBar;

  const AskAthleteIQScreen({
    super.key,
    required this.athleteUid,
    this.showAppBar = true,
  });

  @override
  State<AskAthleteIQScreen> createState() => _AskAthleteIQScreenState();
}

class _AskAthleteIQScreenState extends State<AskAthleteIQScreen> {
  final _fs = FirestoreService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final Stream<List<ChatMessage>> _chatStream;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _chatStream = emitOnError(
      _fs.streamAiChat(widget.athleteUid),
      const <ChatMessage>[],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _askQuestion() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() => _thinking = true);

    try {
      await _fs.askAthleteIQ(widget.athleteUid, text);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = SafeArea(
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
                stream: _chatStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return kAsyncLoading;
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty && !_thinking) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.psychology_outlined,
                              size: 40,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ask about training load, fatigue, sleep, or recovery. '
                              'When askAthleteIQ is deployed, answers are grounded in logged check-ins. '
                              'If the callable is unavailable, replies are labeled rule-based fallbacks — not the full AI model.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: messages.length + (_thinking ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_thinking && i == messages.length) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.mint,
                              ),
                            ),
                          ),
                        );
                      }
                      final m = messages[i];
                      return _AiBubble(message: m);
                    },
                  );
                },
              ),
            ),

            // Input Bar
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
                      onSubmitted: (_) => _askQuestion(),
                      decoration: const InputDecoration(
                        hintText: 'Ask a question…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _thinking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.mint,
                            ),
                          )
                        : const Icon(Icons.send, color: AppColors.mint),
                    onPressed: _thinking ? null : _askQuestion,
                  ),
                ],
              ),
            ),
          ],
        ),
    );

    if (!widget.showAppBar) return chat;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, color: AppColors.mint, size: 20),
            SizedBox(width: 6),
            Text('Ask AthleteIQ'),
          ],
        ),
        centerTitle: true,
      ),
      body: chat,
    );
  }
}

class _AiBubble extends StatelessWidget {
  final ChatMessage message;

  const _AiBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = !message.isAi;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
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
            if (message.isAi) ...[
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology, color: AppColors.mint, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'AthleteIQ AI',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: isMe ? AppColors.mintDark : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

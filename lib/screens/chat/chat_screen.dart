import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../models/audit_log_model.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.jobId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _showNegotiation = false;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String get _currentUserId =>
      ref.read(authStateChangesProvider).value?.uid ?? '';

  ChatNotifierParams get _params {
    final uid = _currentUserId;
    final job = ref.read(jobStreamProvider(widget.jobId)).asData?.value;
    final role = job?.customerId == uid ? ActorRole.customer : ActorRole.artisan;
    return ChatNotifierParams(
      jobId: widget.jobId,
      senderId: uid,
      receiverId: widget.otherUserId,
      senderRole: role,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.otherUserId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chat is not available until an artisan has been selected for this job.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        ),
      );
    }

    final messages = ref.watch(messagesStreamProvider(widget.jobId));
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));
    final sending = ref.watch(chatNotifierProvider(_params));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherUserName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            jobAsync.when(
              data: (job) => Text(
                job?.status.label ?? '',
                style: TextStyle(
                    fontSize: 12, color: context.colors.textSecondary),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, stack) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          jobAsync.when(
            data: (job) {
              if (job == null) return const SizedBox.shrink();
              if (job.status.name == 'inChat') {
                return TextButton(
                  onPressed: () => context.push('/payment/${widget.jobId}'),
                  child: Text('Pay Now',
                      style: TextStyle(color: context.colors.primary)),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (msgs) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });
                if (msgs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nSay hello!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.textTertiary,
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, i) => _MessageBubble(
                    message: msgs[i],
                    isMine: msgs[i].senderId == _currentUserId,
                  ),
                );
              },
            ),
          ),
          if (_showNegotiation) _negotiationBar(),
          _inputBar(sending),
        ],
      ),
    );
  }

  Widget _negotiationBar() => Container(
        color: context.colors.warningSurface,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const Text('₦', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Propose a price',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final amount = double.tryParse(_amountController.text);
                if (amount == null || amount <= 0) return;
                ref
                    .read(chatNotifierProvider(_params).notifier)
                    .sendNegotiation(amount);
                _amountController.clear();
                setState(() => _showNegotiation = false);
              },
              child: const Text('Send'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _showNegotiation = false),
            ),
          ],
        ),
      );

  Widget _inputBar(AsyncValue<void> sending) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.borderLight)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.attach_money_rounded,
                    color: context.colors.textSecondary),
                onPressed: () =>
                    setState(() => _showNegotiation = !_showNegotiation),
                tooltip: 'Propose price',
              ),
              IconButton(
                icon: Icon(Icons.image_outlined,
                    color: context.colors.textSecondary),
                onPressed: sending.isLoading ? null : _pickAndSendImage,
                tooltip: 'Send image',
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    filled: true,
                    fillColor: context.colors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              sending.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: Icon(Icons.send_rounded,
                          color: context.colors.primary),
                      onPressed: _sendText,
                    ),
            ],
          ),
        ),
      );

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(chatNotifierProvider(_params).notifier).sendText(text);
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        quality: 70,
      );
      bytes = Uint8List.fromList(compressed);
    }
    await ref
        .read(chatNotifierProvider(_params).notifier)
        .sendImageBytes(bytes);
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (message.type == MessageType.system) {
      return _systemBubble(context);
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? context.colors.bubbleSent : context.colors.bubbleReceived,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.type == MessageType.image && message.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, stack) => Icon(
                      Icons.broken_image_outlined,
                      color: context.colors.textTertiary),
                ),
              )
            else if (message.type == MessageType.negotiation)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_money_rounded,
                      size: 16,
                      color: isMine ? Colors.white70 : context.colors.warning),
                  const SizedBox(width: 4),
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isMine ? Colors.white : context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              )
            else
              Text(
                message.text,
                style: TextStyle(
                  color: isMine ? Colors.white : context.colors.textPrimary,
                  fontSize: 14,
                  fontFamily: 'Inter',
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: isMine ? Colors.white60 : context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _systemBubble(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

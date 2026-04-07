import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import 'call_repository.dart';
import 'call_controller.dart';

class CallChatScreen extends ConsumerStatefulWidget {
  final String callId;
  const CallChatScreen({super.key, required this.callId});

  @override
  ConsumerState<CallChatScreen> createState() => _CallChatScreenState();
}

class _CallChatScreenState extends ConsumerState<CallChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Poll for new messages every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final repo = ref.read(callRepositoryProvider);
      final data = await repo.getMessages(widget.callId);
      
      // Handle different possible backend response structures
      List<dynamic> messageList = [];
      if (data.containsKey('messages')) {
        messageList = data['messages'] as List;
      } else if (data.containsKey('results')) {
        messageList = data['results'] as List;
      } else if (data is Map && data.values.any((v) => v is List)) {
         messageList = data.values.firstWhere((v) => v is List);
      }

      if (mounted) {
        setState(() {
          _messages = messageList.map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });
        // Auto scroll on first load
        if (_messages.isNotEmpty && _scrollController.hasClients && _scrollController.offset == 0) {
           _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Failed to load messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    _messageController.clear();
    try {
      final repo = ref.read(callRepositoryProvider);
      await repo.sendMessage(widget.callId, text);
      await _loadMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Чат с пользователем',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender_type'] == 'guard' || msg['is_from_me'] == true;
                          return _buildMessageBubble(msg, isMe);
                        },
                      ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, color: AppColors.textHint, size: 48),
          const SizedBox(height: 12),
          Text(
            'Начните переписку с пользователем',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final text = msg['message'] ?? msg['text'] ?? '';
    final timeStr = msg['created_at'] != null 
        ? msg['created_at'].toString().substring(11, 16)
        : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppColors.accent : AppColors.cardDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ваше сообщение...',
                hintStyle: TextStyle(color: AppColors.textHint),
                border: InputBorder.none,
              ),
              maxLines: null,
            ),
          ),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send_rounded, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

import 'chat_message.dart';

class MessageSearchResult {
  final String target;
  final ChatMessage message;

  const MessageSearchResult({
    required this.target,
    required this.message,
  });
}

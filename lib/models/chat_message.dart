enum ChatMessageType {
  normal,
  action,
  system,
}

class ChatMessage {
  final String sender;
  final String target;
  final String text;
  final DateTime time;
  final bool isMe;
  final bool isSystem;
  final ChatMessageType type;

  const ChatMessage({
    required this.sender,
    required this.target,
    required this.text,
    required this.time,
    this.isMe = false,
    this.isSystem = false,
    this.type = ChatMessageType.normal,
  });

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'target': target,
      'text': text,
      'time': time.toIso8601String(),
      'isMe': isMe,
      'isSystem': isSystem,
      'type': type.name,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      sender: json['sender'] as String,
      target: json['target'] as String,
      text: json['text'] as String,
      time: DateTime.parse(json['time'] as String),
      isMe: json['isMe'] as bool? ?? false,
      isSystem: json['isSystem'] as bool? ?? false,
      type: ChatMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ChatMessageType.normal,
      ),
    );
  }
}
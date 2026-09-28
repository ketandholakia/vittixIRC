class Channel {
  final String name;
  final int unreadCount;
  final bool isPrivate;
  final bool pinned;
  final String modes;

  const Channel({
    required this.name,
    this.unreadCount = 0,
    this.isPrivate = false,
    this.pinned = false,
    this.modes = '',
  });

  Channel copyWith({
    String? name,
    int? unreadCount,
    bool? isPrivate,
    bool? pinned,
    String? modes,
  }) {
    return Channel(
      name: name ?? this.name,
      unreadCount: unreadCount ?? this.unreadCount,
      isPrivate: isPrivate ?? this.isPrivate,
      pinned: pinned ?? this.pinned,
      modes: modes ?? this.modes,
    );
  }
}

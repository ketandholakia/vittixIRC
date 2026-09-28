class NotificationRoutePayload {
  final String serverId;
  final String target;

  const NotificationRoutePayload({
    required this.serverId,
    required this.target,
  });

  static NotificationRoutePayload? parse(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;

    final parts = payload.split('|');
    if (parts.length != 2) return null;

    return NotificationRoutePayload(
      serverId: parts[0],
      target: parts[1],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum NetworkConnectionState { connected, connecting, disconnected }

class NetworkStateIndicator extends StatelessWidget {
  final NetworkConnectionState state;

  const NetworkStateIndicator({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    // We hide the indicator completely when connected
    if (state == NetworkConnectionState.connected) {
      return const SizedBox.shrink();
    }

    final isConnecting = state == NetworkConnectionState.connecting;
    final bgColor = isConnecting ? Colors.orange.shade700 : Colors.red.shade700;
    final text = isConnecting ? 'Connecting...' : 'Disconnected';

    final banner = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return banner.animate().fadeIn(duration: 180.ms).slideY(
          begin: -0.12,
          end: 0,
          duration: 180.ms,
          curve: Curves.easeOut,
        );
  }
}

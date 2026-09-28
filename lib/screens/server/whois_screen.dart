import 'package:flutter/material.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';

class WhoisScreen extends StatefulWidget {
  final IrcSessionController controller;
  final String nick;

  const WhoisScreen({
    super.key,
    required this.controller,
    required this.nick,
  });

  @override
  State<WhoisScreen> createState() => _WhoisScreenState();
}

class _WhoisScreenState extends State<WhoisScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.requestWhois(widget.nick);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return ListTile(
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.controller.whoisFor(widget.nick);

    return Scaffold(
      appBar: AppBar(
        title: Text('WHOIS ${widget.nick}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.controller.requestWhois(widget.nick),
          ),
        ],
      ),
      body: info == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _row('Nick', info.nick),
                _row('User / Host', info.userHost),
                _row('Real Name', info.realName),
                _row('Account', info.account),
                _row('Server', info.server),
                _row('Server Info', info.serverInfo),
                _row('Idle', info.idle),
                if (info.channels.isNotEmpty) ...[
                  const Divider(),
                  const ListTile(
                    title: Text('Channels'),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: info.channels.map((c) => Chip(label: Text(c))).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                const Divider(),
                const ListTile(
                  title: Text('Raw WHOIS Lines'),
                ),
                ...info.rawLines.map(
                  (line) => ListTile(
                    dense: true,
                    title: SelectableText(line),
                  ),
                ),
              ],
            ),
    );
  }
}

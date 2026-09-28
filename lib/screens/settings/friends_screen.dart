import 'package:flutter/material.dart';

import 'package:vittix_irc/models/app_settings.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/state/session_manager.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = AppSettingsService();
  final _controller = TextEditingController();
  bool _loading = true;
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _save(AppSettings settings) async {
    setState(() => _settings = settings);
    await _service.saveSettings(settings);
    SessionManager.instance.reloadSettingsForAll();
  }

  Future<void> _addFriend() async {
    final nick = _controller.text.trim();
    if (nick.isEmpty) return;
    if (_settings.friendNicks
        .any((item) => item.toLowerCase() == nick.toLowerCase())) {
      return;
    }

    await _save(
      _settings.copyWith(friendNicks: [..._settings.friendNicks, nick]),
    );
    _controller.clear();
  }

  Future<void> _removeFriend(String nick) async {
    await _save(
      _settings.copyWith(
        friendNicks: _settings.friendNicks
            .where((item) => item.toLowerCase() != nick.toLowerCase())
            .toList(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            labelText: 'Add friend nick',
                            hintText: 'alice',
                          ),
                          onSubmitted: (_) => _addFriend(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _addFriend,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _settings.friendNicks.isEmpty
                      ? const Center(child: Text('No friends tracked yet'))
                      : ListView.separated(
                          itemCount: _settings.friendNicks.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final nick = _settings.friendNicks[index];
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(nick),
                              subtitle: const Text('Tracked friend'),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close),
                                onPressed: () => _removeFriend(nick),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vittix_irc/models/server_config.dart';

class _ServerPreset {
  final String name;
  final String section;
  final String host;
  final int port;
  final String notes;
  final String suggestedChannel;
  final IconData icon;
  final Color accent;

  const _ServerPreset({
    required this.name,
    required this.section,
    required this.host,
    required this.port,
    required this.notes,
    required this.suggestedChannel,
    required this.icon,
    required this.accent,
  });
}

class _PresetHistoryEntry {
  final _ServerPreset preset;
  final DateTime usedAt;

  const _PresetHistoryEntry({
    required this.preset,
    required this.usedAt,
  });
}

class AddServerScreen extends StatefulWidget {
  final ServerConfig? existingServer;

  const AddServerScreen({
    super.key,
    this.existingServer,
  });

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  static const String _recentPrefsKey = 'irc_recent_presets';
  static const String _favoritesPrefsKey = 'irc_favorite_presets';
  static const int _maxRecentPresets = 3;
  static const List<_ServerPreset> _presets = [
    _ServerPreset(
      name: 'Libera.Chat',
      section: 'Modern',
      host: 'irc.libera.chat',
      port: 6697,
      notes: 'Largest modern FOSS IRC network',
      suggestedChannel: '#libera',
      icon: Icons.public,
      accent: Colors.blue,
    ),
    _ServerPreset(
      name: 'OFTC',
      section: 'Modern',
      host: 'irc.oftc.net',
      port: 6697,
      notes: 'Open-source communities',
      suggestedChannel: '#oftc',
      icon: Icons.handshake,
      accent: Colors.teal,
    ),
    _ServerPreset(
      name: 'EFnet',
      section: 'Legacy',
      host: 'irc.efnet.org',
      port: 6697,
      notes: 'One of the oldest IRC networks',
      suggestedChannel: '#efnet',
      icon: Icons.history,
      accent: Colors.indigo,
    ),
    _ServerPreset(
      name: 'Undernet',
      section: 'Legacy',
      host: 'irc.undernet.org',
      port: 6697,
      notes: 'Classic IRC network',
      suggestedChannel: '#undernet',
      icon: Icons.cloud,
      accent: Colors.deepPurple,
    ),
    _ServerPreset(
      name: 'IRCnet',
      section: 'Legacy',
      host: 'open.ircnet.net',
      port: 6697,
      notes: 'Traditional IRC',
      suggestedChannel: '#ircnet',
      icon: Icons.forum,
      accent: Colors.brown,
    ),
    _ServerPreset(
      name: 'Rizon',
      section: 'Gaming',
      host: 'irc.rizon.net',
      port: 6697,
      notes: 'Anime, gaming, and general chat',
      suggestedChannel: '#rizon',
      icon: Icons.gamepad,
      accent: Colors.orange,
    ),
    _ServerPreset(
      name: 'QuakeNet',
      section: 'Gaming',
      host: 'irc.quakenet.org',
      port: 6697,
      notes: 'Gaming and esports legacy',
      suggestedChannel: '#quakenet',
      icon: Icons.sports_esports,
      accent: Colors.red,
    ),
    _ServerPreset(
      name: 'GameSurge',
      section: 'Gaming',
      host: 'irc.gamesurge.net',
      port: 6697,
      notes: 'Gaming and community',
      suggestedChannel: '#gamesurge',
      icon: Icons.sports_score,
      accent: Colors.green,
    ),
    _ServerPreset(
      name: 'DALnet',
      section: 'Legacy',
      host: 'irc.dal.net',
      port: 6697,
      notes: 'Large historic network',
      suggestedChannel: '#dalnet',
      icon: Icons.dns,
      accent: Colors.amber,
    ),
    _ServerPreset(
      name: 'SwiftIRC',
      section: 'Modern',
      host: 'irc.swiftirc.net',
      port: 6697,
      notes: 'General purpose',
      suggestedChannel: '#swiftirc',
      icon: Icons.bolt,
      accent: Colors.lightBlue,
    ),
    _ServerPreset(
      name: 'WebChat',
      section: 'Modern',
      host: 'irc.webchat.org',
      port: 6697,
      notes: 'Community-focused',
      suggestedChannel: '#webchat',
      icon: Icons.chat,
      accent: Colors.cyan,
    ),
    _ServerPreset(
      name: 'SorceryNet',
      section: 'Community',
      host: 'irc.sorcery.net',
      port: 6697,
      notes: 'Small community network',
      suggestedChannel: '#sorcerynet',
      icon: Icons.auto_fix_high,
      accent: Colors.pink,
    ),
  ];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _nickCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _realNameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _channelCtrl;

  bool _useTls = true;
  bool _useSasl = false;
  String? _selectedPresetName;
  List<_PresetHistoryEntry> _recentPresets = [];
  Set<String> _favoritePresetNames = <String>{};
  final TextEditingController _presetSearchCtrl = TextEditingController();

  IrcConnectionProfileType _profileType = IrcConnectionProfileType.normal;
  IrcBouncerType _bouncerType = IrcBouncerType.znc;
  final _bouncerNetworkCtrl = TextEditingController();
  final _random = Random();

  @override
  void initState() {
    super.initState();

    final server = widget.existingServer;

    _nameCtrl = TextEditingController(text: server?.name ?? 'Libera Chat');
    _hostCtrl = TextEditingController(text: server?.host ?? 'irc.libera.chat');
    _portCtrl = TextEditingController(text: (server?.port ?? 6697).toString());
    _nickCtrl = TextEditingController(text: server?.nickname ?? _randomNick());
    _usernameCtrl =
        TextEditingController(text: server?.username ?? _randomUsername());
    _realNameCtrl =
        TextEditingController(text: server?.realName ?? _randomRealName());
    _passwordCtrl = TextEditingController(text: server?.password ?? '');
    _channelCtrl =
        TextEditingController(text: server?.defaultChannel ?? '#test');

    _useTls = server?.useTls ?? true;
    _useSasl = server?.useSasl ?? false;

    _profileType = server?.profileType ?? IrcConnectionProfileType.normal;
    _bouncerType = server?.bouncerType ?? IrcBouncerType.znc;
    _bouncerNetworkCtrl.text = server?.bouncerNetwork ?? '';

    if (server == null) {
      _selectedPresetName = 'Libera.Chat';
      _channelCtrl.text = _presetByName(_selectedPresetName!)!.suggestedChannel;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPresetPreferences();
    });
  }

  Future<void> _loadPresetPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final recentJson = prefs.getString(_recentPrefsKey);
    final favorites = prefs.getStringList(_favoritesPrefsKey) ?? const [];
    final parsedRecent = <_PresetHistoryEntry>[];
    if (recentJson != null && recentJson.isNotEmpty) {
      final decoded = jsonDecode(recentJson) as List<dynamic>;
      for (final item in decoded) {
        final map = item as Map<String, dynamic>;
        final name = map['name'] as String?;
        final usedAt = map['usedAt'] as String?;
        if (name == null || usedAt == null) continue;
        final preset = _presetByName(name);
        if (preset == null) continue;
        parsedRecent.add(_PresetHistoryEntry(
            preset: preset,
            usedAt: DateTime.tryParse(usedAt) ?? DateTime.now()));
      }
    }
    if (!mounted) return;
    setState(() {
      _recentPresets = parsedRecent.take(_maxRecentPresets).toList();
      _favoritePresetNames = favorites.toSet();
    });
  }

  void _applyPreset(_ServerPreset preset) {
    setState(() {
      _selectedPresetName = preset.name;
      _nameCtrl.text = preset.name;
      _hostCtrl.text = preset.host;
      _portCtrl.text = preset.port.toString();
      _useTls = true;
      _channelCtrl.text = preset.suggestedChannel;
    });
    SharedPreferences.getInstance().then((prefs) {
      final updated = <_PresetHistoryEntry>[
        _PresetHistoryEntry(preset: preset, usedAt: DateTime.now()),
        ..._recentPresets.where((entry) => entry.preset.name != preset.name),
      ].take(_maxRecentPresets).toList();
      _recentPresets = updated;
      prefs.setString(
        _recentPrefsKey,
        jsonEncode(
          updated
              .map(
                (entry) => {
                  'name': entry.preset.name,
                  'usedAt': entry.usedAt.toIso8601String(),
                },
              )
              .toList(),
        ),
      );
    });
  }

  _ServerPreset? _presetByName(String name) {
    for (final preset in _presets) {
      if (preset.name == name) return preset;
    }
    return null;
  }

  Future<void> _toggleFavorite(_ServerPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = Set<String>.from(_favoritePresetNames);
    if (!updated.add(preset.name)) {
      updated.remove(preset.name);
    }
    if (!mounted) return;
    setState(() {
      _favoritePresetNames = updated;
    });
    await prefs.setStringList(_favoritesPrefsKey, updated.toList());
  }

  String _randomNick() => 'nick${_random.nextInt(900000) + 100000}';

  String _randomUsername() => 'user${_random.nextInt(900000) + 100000}';

  String _randomRealName() => 'Real User ${_random.nextInt(900000) + 100000}';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _nickCtrl.dispose();
    _usernameCtrl.dispose();
    _realNameCtrl.dispose();
    _passwordCtrl.dispose();
    _channelCtrl.dispose();
    _presetSearchCtrl.dispose();
    _bouncerNetworkCtrl.dispose();
    super.dispose();
  }

  List<_ServerPreset> get _filteredPresets {
    final query = _presetSearchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _presets;
    return _presets.where((preset) {
      return preset.name.toLowerCase().contains(query) ||
          preset.host.toLowerCase().contains(query) ||
          preset.notes.toLowerCase().contains(query) ||
          preset.suggestedChannel.toLowerCase().contains(query);
    }).toList();
  }

  List<_ServerPreset> get _favoritePresets => _presets
      .where((preset) => _favoritePresetNames.contains(preset.name))
      .toList();

  _ServerPreset? get _selectedPreset =>
      _selectedPresetName == null ? null : _presetByName(_selectedPresetName!);

  List<DropdownMenuItem<String>> _buildPresetDropdownItems() {
    return _filteredPresets.map((preset) {
      return DropdownMenuItem<String>(
        value: preset.name,
        child: Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: preset.accent.withValues(alpha: 0.15),
              foregroundColor: preset.accent,
              child: Icon(preset.icon, size: 12),
            ),
            const SizedBox(width: 10),
            Text(
              '${preset.name} • ${preset.section}',
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildPresetCard(_PresetHistoryEntry entry) {
    final preset = entry.preset;
    final isFavorite = _favoritePresetNames.contains(preset.name);
    final isRecent = _recentPresets.isNotEmpty &&
        _recentPresets.first.preset.name == preset.name;
    return Card(
      elevation: isRecent ? 3 : 0,
      color: isRecent ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              preset.accent.withValues(alpha: isRecent ? 0.28 : 0.15),
          foregroundColor: preset.accent,
          child: Icon(preset.icon),
        ),
        title: Row(
          children: [
            Expanded(child: Text(preset.name)),
            if (isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.star, size: 18),
              ),
            if (preset.name == 'Libera.Chat')
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text('Default'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${preset.host} - ${preset.suggestedChannel}\nLast used ${_formatTimestamp(entry.usedAt)}',
        ),
        trailing: Wrap(
          spacing: 6,
          children: [
            IconButton(
              onPressed: () => _toggleFavorite(preset),
              icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
            ),
            FilledButton(
              onPressed: () => _applyPreset(preset),
              child: const Text('Use'),
            ),
          ],
        ),
        onTap: () => _applyPreset(preset),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final existing = widget.existingServer;

    final server = ServerConfig(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
      useTls: _useTls,
      useSasl: _useSasl,
      nickname: _nickCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      realName: _realNameCtrl.text.trim(),
      password:
          _passwordCtrl.text.trim().isEmpty ? null : _passwordCtrl.text.trim(),
      defaultChannel: _channelCtrl.text.trim(),
    );

    Navigator.pop(context, server);
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool requiredField = true,
    String? Function(String?)? validator,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator ??
            (value) {
              if (!requiredField) return null;
              if (value == null || value.trim().isEmpty) {
                return '$label is required';
              }
              return null;
            },
        decoration: _decoration(label, icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingServer == null
            ? 'Add IRC Server'
            : 'Edit IRC Server'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Server Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              if (widget.existingServer == null) ...[
                if (_favoritePresets.isNotEmpty) ...[
                  Text(
                    'Favorites',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _favoritePresets
                        .map(
                          (preset) => ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor:
                                  preset.accent.withValues(alpha: 0.15),
                              foregroundColor: preset.accent,
                              child: Icon(preset.icon, size: 14),
                            ),
                            label: Text(preset.name),
                            onPressed: () => _applyPreset(preset),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_recentPresets.isNotEmpty) ...[
                  Text(
                    'Recent',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ..._recentPresets.map(_buildPresetCard),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _presetSearchCtrl,
                  decoration:
                      _decoration('Search presets', Icons.search).copyWith(
                    hintText: 'Filter by network, host, or channel',
                    suffixIcon: _presetSearchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _presetSearchCtrl.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear search',
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPresetName,
                  decoration: _decoration('Preset Server', Icons.public),
                  hint: const Text('Choose a recommended network'),
                  items: _buildPresetDropdownItems(),
                  onChanged: (name) {
                    if (name == null) return;
                    final preset = _presetByName(name);
                    if (preset == null) return;
                    _applyPreset(preset);
                  },
                ),
                if (_selectedPreset != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _applyPreset(_selectedPreset!),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset to preset'),
                    ),
                  ),
                ],
                if (_filteredPresets.isEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'No presets match your search.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
              ],
              _field(
                controller: _nameCtrl,
                label: 'Server Name',
                icon: Icons.dns,
              ),
              _field(
                controller: _hostCtrl,
                label: 'Host',
                icon: Icons.language,
              ),
              _field(
                controller: _portCtrl,
                label: 'Port',
                icon: Icons.settings_ethernet,
                keyboardType: TextInputType.number,
                validator: (value) {
                  final port = int.tryParse(value ?? '');
                  if (port == null || port <= 0 || port > 65535) {
                    return 'Enter valid port';
                  }
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use TLS / SSL'),
                subtitle: Text(_useTls ? 'Secure connection' : 'Plain TCP'),
                value: _useTls,
                onChanged: (value) {
                  setState(() => _useTls = value);
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Connection Profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<IrcConnectionProfileType>(
                initialValue: _profileType,
                decoration: _decoration('Profile Type', Icons.account_tree),
                items: const [
                  DropdownMenuItem(
                    value: IrcConnectionProfileType.normal,
                    child: Text('Normal IRC Server'),
                  ),
                  DropdownMenuItem(
                    value: IrcConnectionProfileType.bouncer,
                    child: Text('IRC Bouncer'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _profileType = value);
                },
              ),
              if (_profileType == IrcConnectionProfileType.bouncer) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<IrcBouncerType>(
                  initialValue: _bouncerType,
                  decoration: _decoration('Bouncer Type', Icons.hub),
                  items: const [
                    DropdownMenuItem(
                        value: IrcBouncerType.znc, child: Text('ZNC')),
                    DropdownMenuItem(
                        value: IrcBouncerType.soju, child: Text('soju')),
                    DropdownMenuItem(
                        value: IrcBouncerType.other, child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _bouncerType = value);
                  },
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _bouncerNetworkCtrl,
                  label: 'Bouncer Network Name',
                  icon: Icons.router,
                  requiredField: false,
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'User Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _nickCtrl,
                label: 'Nickname',
                icon: Icons.person,
              ),
              _field(
                controller: _usernameCtrl,
                label: 'Username',
                icon: Icons.account_circle,
              ),
              _field(
                controller: _realNameCtrl,
                label: 'Real Name',
                icon: Icons.badge,
              ),
              _field(
                controller: _passwordCtrl,
                label: 'Password / SASL Password',
                icon: Icons.lock,
                requiredField: false,
                obscureText: true,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use SASL Login'),
                subtitle: const Text('Authenticate before joining channels'),
                value: _useSasl,
                onChanged: (value) {
                  setState(() => _useSasl = value);
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Default Channel',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _channelCtrl,
                label: 'Channel',
                icon: Icons.tag,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Channel is required';
                  if (!text.startsWith('#')) {
                    return 'Channel must start with #';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: Text(widget.existingServer == null
                    ? 'Save Server'
                    : 'Update Server'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

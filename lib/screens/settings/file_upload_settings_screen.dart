import 'package:flutter/material.dart';

import 'package:vittix_irc/models/file_upload_settings.dart';
import 'package:vittix_irc/services/file_upload_settings_service.dart';

class FileUploadSettingsScreen extends StatefulWidget {
  const FileUploadSettingsScreen({super.key});

  @override
  State<FileUploadSettingsScreen> createState() =>
      _FileUploadSettingsScreenState();
}

class _FileUploadSettingsScreenState extends State<FileUploadSettingsScreen> {
  final _service = FileUploadSettingsService();

  final _uploadUrlCtrl = TextEditingController();
  final _fileFieldCtrl = TextEditingController();
  final _regexCtrl = TextEditingController();
  final _headersCtrl = TextEditingController();
  final _fieldsCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _rememberCtrl = TextEditingController();
  final _maxFileSizeCtrl = TextEditingController();

  UploadAuthType _authType = UploadAuthType.none;
  bool _loading = true;
  String? _loadError;
  String? _selectedPreset;
  String? _presetCheckMessage;
  bool _presetCheckIsError = false;

  static const _presets = <String, Map<String, String>>{
    'x0.at': {
      'icon': 'bolt',
      'badge': 'General',
      'description': 'Single-file host, simple URL response.',
      'uploadUrl': 'https://x0.at',
      'fileField': 'file',
      'responseRegex': r'https://\S+',
      'additionalHeaders': '',
      'additionalFields': '',
    },
    '0x0.st': {
      'icon': 'link',
      'badge': 'General',
      'description': 'Minimal generic file upload service.',
      'uploadUrl': 'https://0x0.st',
      'fileField': 'file',
      'responseRegex': r'https://\S+',
      'additionalHeaders': '',
      'additionalFields': '',
    },
    'ttm.sh': {
      'icon': 'upload',
      'badge': 'General',
      'description': 'Simple paste/file host with URL output.',
      'uploadUrl': 'https://ttm.sh',
      'fileField': 'file',
      'responseRegex': r'https://\S+',
      'additionalHeaders': '',
      'additionalFields': '',
    },
    'Imgur Anonymous': {
      'icon': 'image',
      'badge': 'Images',
      'description': 'Images only, anonymous Client-ID upload.',
      'uploadUrl': 'https://api.imgur.com/3/upload',
      'fileField': 'image',
      'responseRegex': r'https://i\.imgur\.com/\w+\.\w+',
      'additionalHeaders': 'Authorization: Client-ID <your client id>',
      'additionalFields': '',
    },
    'Imgur OAuth': {
      'icon': 'shield',
      'badge': 'Images',
      'description': 'Images only, OAuth Bearer-token upload.',
      'uploadUrl': 'https://api.imgur.com/3/upload',
      'fileField': 'image',
      'responseRegex': r'https://i\.imgur\.com/\w+\.\w+',
      'additionalHeaders': 'Authorization: Bearer <access token>',
      'additionalFields': '',
    },
    'Catbox': {
      'icon': 'folder',
      'badge': 'General',
      'description': 'General file host with long-lived links.',
      'uploadUrl': 'https://catbox.moe/user/api.php',
      'fileField': 'fileToUpload',
      'responseRegex': r'https://\S+',
      'additionalHeaders': '',
      'additionalFields': 'reqtype=fileupload',
    },
    'Litterbox': {
      'icon': 'timer',
      'badge': 'Temp',
      'description': 'Temporary uploads with expiry controls.',
      'uploadUrl': 'https://litterbox.catbox.moe/resources/internals/api.php',
      'fileField': 'fileToUpload',
      'responseRegex': r'https://\S+',
      'additionalHeaders': '',
      'additionalFields': 'reqtype=fileupload\ntime=72h',
    },
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.getSettings();

      if (!mounted) return;

      _uploadUrlCtrl.text = settings.uploadUrl;
      _fileFieldCtrl.text = settings.fileField;
      _regexCtrl.text = settings.responseRegex;
      _headersCtrl.text = settings.additionalHeaders;
      _fieldsCtrl.text = settings.additionalFields;
      _usernameCtrl.text = settings.username ?? '';
      _passwordCtrl.text = settings.password ?? '';
      _rememberCtrl.text = settings.rememberUploadsHours.toString();
      _maxFileSizeCtrl.text = settings.maxFileSizeMb.toString();
      _authType = settings.authType;

      setState(() {
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _save() async {
    try {
      final settings = FileUploadSettings(
        uploadUrl: _uploadUrlCtrl.text.trim(),
        fileField: _fileFieldCtrl.text.trim().isEmpty
            ? 'file'
            : _fileFieldCtrl.text.trim(),
        responseRegex: _regexCtrl.text.trim(),
        additionalHeaders: _headersCtrl.text.trim(),
        additionalFields: _fieldsCtrl.text.trim(),
        authType: _authType,
        username: _usernameCtrl.text.trim().isEmpty
            ? null
            : _usernameCtrl.text.trim(),
        password: _passwordCtrl.text.trim().isEmpty
            ? null
            : _passwordCtrl.text.trim(),
        rememberUploadsHours: int.tryParse(_rememberCtrl.text.trim()) ?? 24,
        maxFileSizeMb: int.tryParse(_maxFileSizeCtrl.text.trim()) ?? 25,
      );

      await _service.saveSettings(settings);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload settings saved')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save upload settings: $e')),
      );
    }
  }

  void _applyPreset(String name) {
    final preset = _presets[name];
    if (preset == null) return;

    setState(() {
      _selectedPreset = name;
      _presetCheckMessage = null;
      _uploadUrlCtrl.text = preset['uploadUrl'] ?? '';
      _fileFieldCtrl.text = preset['fileField'] ?? '';
      _regexCtrl.text = preset['responseRegex'] ?? '';
      _headersCtrl.text = preset['additionalHeaders'] ?? '';
      _fieldsCtrl.text = preset['additionalFields'] ?? '';
      _authType = UploadAuthType.none;
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    });
  }

  void _checkPreset() {
    final name = _selectedPreset;
    if (name == null) {
      setState(() {
        _presetCheckIsError = true;
        _presetCheckMessage = 'Choose a preset first.';
      });
      return;
    }

    final problems = <String>[];
    final uploadUrl = _uploadUrlCtrl.text.trim();
    final fileField = _fileFieldCtrl.text.trim();
    final responseRegex = _regexCtrl.text.trim();
    final headers = _headersCtrl.text.trim();
    final fields = _fieldsCtrl.text.trim();

    if (uploadUrl.isEmpty) problems.add('Upload URL is empty.');
    if (fileField.isEmpty) problems.add('File field is empty.');
    if (responseRegex.isEmpty) problems.add('Response regex is empty.');

    if (name == 'Imgur Anonymous' && !headers.contains('Client-ID')) {
      problems.add('Imgur Anonymous needs a Client-ID header.');
    }
    if (name == 'Imgur OAuth' && !headers.contains('Bearer')) {
      problems.add('Imgur OAuth needs a Bearer token header.');
    }
    if (name == 'Catbox' && !fields.contains('reqtype=fileupload')) {
      problems.add('Catbox needs reqtype=fileupload.');
    }
    if (name == 'Litterbox' && !fields.contains('time=')) {
      problems.add('Litterbox should include an expiry time.');
    }

    setState(() {
      _presetCheckIsError = problems.isNotEmpty;
      _presetCheckMessage =
          problems.isEmpty ? '$name looks ready.' : problems.join(' ');
    });
  }

  @override
  void dispose() {
    _uploadUrlCtrl.dispose();
    _fileFieldCtrl.dispose();
    _regexCtrl.dispose();
    _headersCtrl.dispose();
    _fieldsCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _rememberCtrl.dispose();
    _maxFileSizeCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  bool get _isImageOnlyPreset =>
      _selectedPreset == 'Imgur Anonymous' || _selectedPreset == 'Imgur OAuth';

  String? get _presetDescription {
    final preset = _selectedPreset;
    if (preset == null) return null;
    return _presets[preset]?['description'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Upload Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load file upload settings.',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: null,
                      decoration:
                          _decoration('Preset', 'Choose a common uploader'),
                      items: _presets.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: SizedBox(
                                width: 260,
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      child: Icon(
                                        _presetIcon(entry.value['icon']),
                                        size: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      entry.value['badge'] ?? '',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _applyPreset(value);
                      },
                    ),
                    if (_presetDescription != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            label:
                                Text(_presets[_selectedPreset]?['badge'] ?? ''),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _presetDescription!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_isImageOnlyPreset) ...[
                      const SizedBox(height: 8),
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.image, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Imgur only accepts image files.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _uploadUrlCtrl,
                      decoration: _decoration(
                        'Upload URL',
                        'https://0x0.st',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fileFieldCtrl,
                      decoration: _decoration(
                        'File Field',
                        'file',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regexCtrl,
                      decoration: _decoration(
                        'Response Regex',
                        r'https://\S+',
                      ),
                    ),
                    if (_selectedPreset != 'Imgur Anonymous' &&
                        _selectedPreset != 'Imgur OAuth') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _headersCtrl,
                        minLines: 2,
                        maxLines: 5,
                        decoration: _decoration(
                          'Additional Headers',
                          'Authorization: Client-ID xxx',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _checkPreset,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Check preset'),
                    ),
                    if (_presetCheckMessage != null) ...[
                      const SizedBox(height: 8),
                      Card(
                        color: _presetCheckIsError
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_presetCheckMessage!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fieldsCtrl,
                      minLines: 2,
                      maxLines: 5,
                      decoration: _decoration(
                        'Additional Fields',
                        'reqtype=fileupload',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UploadAuthType>(
                      initialValue: _authType,
                      decoration: _decoration('Authentication', ''),
                      items: const [
                        DropdownMenuItem(
                          value: UploadAuthType.none,
                          child: Text('None'),
                        ),
                        DropdownMenuItem(
                          value: UploadAuthType.basic,
                          child: Text('Basic'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _authType = value);
                      },
                    ),
                    if (_selectedPreset == 'Imgur Anonymous' ||
                        _selectedPreset == 'Imgur OAuth') ...[
                      const SizedBox(height: 8),
                      Text(
                        _selectedPreset == 'Imgur Anonymous'
                            ? 'Anonymous mode uses a Client-ID header.'
                            : 'OAuth mode uses a Bearer token header.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (_authType == UploadAuthType.basic) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _usernameCtrl,
                        decoration: _decoration('Username', 'user'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration: _decoration('Password', 'pass'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _rememberCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _decoration(
                        'Remember uploads for hours',
                        '24',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _maxFileSizeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _decoration(
                        'Max File Size MB',
                        '25',
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Settings'),
                    ),
                  ],
                ),
    );
  }

  IconData _presetIcon(String? name) {
    switch (name) {
      case 'bolt':
        return Icons.bolt;
      case 'link':
        return Icons.link;
      case 'upload':
        return Icons.cloud_upload;
      case 'image':
        return Icons.image;
      case 'shield':
        return Icons.shield;
      case 'folder':
        return Icons.folder;
      case 'timer':
        return Icons.timer;
      default:
        return Icons.upload;
    }
  }
}

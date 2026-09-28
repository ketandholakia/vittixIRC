import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:vittix_irc/models/message_search_result.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';

class GlobalMessageSearchScreen extends StatefulWidget {
  final IrcSessionController controller;
  final String? target;

  const GlobalMessageSearchScreen({
    super.key,
    required this.controller,
    this.target,
  });

  @override
  State<GlobalMessageSearchScreen> createState() =>
      _GlobalMessageSearchScreenState();
}

class _GlobalMessageSearchScreenState extends State<GlobalMessageSearchScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<MessageSearchResult> _results = [];
  bool _useRegex = false;
  bool _caseSensitive = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(value);
    });
  }

  Future<void> _search(String value) async {
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    final results = widget.target == null
        ? await widget.controller.searchAllMessages(query)
        : await widget.controller.searchMessagesInTarget(
            target: widget.target!,
            query: query,
            useRegex: _useRegex,
            caseSensitive: _caseSensitive,
          );

    if (!mounted) return;

    setState(() {
      _results = results;
      _loading = false;
    });
  }

  String _time(DateTime time) {
    final d = time.day.toString().padLeft(2, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');

    return '$d/$mo $h:$m';
  }

  Future<void> _openResult(MessageSearchResult result) async {
    await widget.controller.openSearchResult(result);

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Messages'),
        actions: [
          if (widget.target != null)
            PopupMenuButton<String>(
              tooltip: 'Search options',
              onSelected: (value) {
                setState(() {
                  if (value == 'regex') {
                    _useRegex = !_useRegex;
                  } else if (value == 'case') {
                    _caseSensitive = !_caseSensitive;
                  }
                });
                _search(_searchCtrl.text);
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'regex',
                  checked: _useRegex,
                  child: const Text('Regex'),
                ),
                CheckedPopupMenuItem(
                  value: 'case',
                  checked: _caseSensitive,
                  child: const Text('Case sensitive'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.target == null
                    ? 'Search all channels...'
                    : 'Search ${widget.target}...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _searchCtrl.text.trim().isEmpty
                          ? 'Type to search messages'
                          : 'No results found',
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final result = _results[index];
                      final msg = result.message;

                      return ListTile(
                        leading: Icon(
                          result.target.startsWith('#')
                              ? Icons.tag
                              : Icons.person,
                        ),
                        title: Text(
                          widget.target == null
                              ? '${msg.sender} in ${result.target}'
                              : msg.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          msg.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(_time(msg.time)),
                        onTap: () => _openResult(result),
                      ).animate().fadeIn(duration: 160.ms).slideX(
                            begin: 0.04,
                            end: 0,
                            duration: 160.ms,
                            curve: Curves.easeOut,
                          );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

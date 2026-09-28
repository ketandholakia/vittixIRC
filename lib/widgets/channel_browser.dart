import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vittix_irc/models/irc_channel_info.dart';

class ChannelBrowser extends StatefulWidget {
  final String title;
  final List<IrcChannelInfo> channels;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<IrcChannelInfo> onJoin;
  final String emptyMessage;
  final String searchingEmptyMessage;
  final String loadingMessage;

  const ChannelBrowser({
    super.key,
    required this.title,
    required this.channels,
    required this.loading,
    required this.onRefresh,
    required this.onJoin,
    required this.emptyMessage,
    required this.searchingEmptyMessage,
    required this.loadingMessage,
  });

  @override
  State<ChannelBrowser> createState() => _ChannelBrowserState();
}

class _ChannelBrowserState extends State<ChannelBrowser> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _minUsers = 0;
  String _sortMode = 'users';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<IrcChannelInfo> _filteredChannels() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = widget.channels.where((c) {
      if (c.name.isEmpty) return false;
      if (c.users < _minUsers) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.topic.toLowerCase().contains(q);
    }).toList();

    switch (_sortMode) {
      case 'name':
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'topic':
        filtered.sort(
          (a, b) => a.topic.toLowerCase().compareTo(b.topic.toLowerCase()),
        );
        break;
      default:
        filtered.sort((a, b) => b.users.compareTo(a.users));
    }

    return filtered;
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChannels();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(
              widget.loading
                  ? 'Loading channels...'
                  : 'Total: ${widget.channels.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: widget.loading ? null : () => widget.onRefresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search channels or topics',
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSearch,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('100+ users'),
                      selected: _minUsers >= 100,
                      onSelected: (selected) {
                        setState(() {
                          _minUsers = selected ? 100 : 0;
                        });
                      },
                    ),
                    FilterChip(
                      label: const Text('25+ users'),
                      selected: _minUsers >= 25 && _minUsers < 100,
                      onSelected: (selected) {
                        setState(() {
                          _minUsers = selected ? 25 : 0;
                        });
                      },
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'users', label: Text('Users')),
                        ButtonSegment(value: 'name', label: Text('Name')),
                        ButtonSegment(value: 'topic', label: Text('Topic')),
                      ],
                      selected: {_sortMode},
                      onSelectionChanged: (selection) {
                        setState(() => _sortMode = selection.first);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.45,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                widget.loading
                                    ? widget.loadingMessage
                                    : _searchCtrl.text.trim().isEmpty &&
                                            _minUsers == 0
                                        ? widget.emptyMessage
                                        : widget.searchingEmptyMessage,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final channel = filtered[index];

                        return Card(
                          child: InkWell(
                            onTap: () => widget.onJoin(channel),
                            child: ListTile(
                              leading: const Icon(Icons.tag),
                              title: Text(channel.name),
                              subtitle: Text(
                                '${channel.users} users\n${channel.topic.isEmpty ? 'No topic set' : channel.topic}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: FilledButton(
                                onPressed: () => widget.onJoin(channel),
                                child: const Text('Join'),
                              ),
                            ),
                          ),
                        ).animate(
                          delay: Duration(milliseconds: (index * 25).clamp(0, 300)),
                        ).slideX(
                          begin: 0.05,
                          end: 0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutQuad,
                        ).fadeIn(
                          duration: const Duration(milliseconds: 250),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

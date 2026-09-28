import 'package:vittix_irc/models/irc_command_help.dart';

const ircCommandHelpList = <IrcCommandHelp>[
  IrcCommandHelp(
    command: '/join',
    usage: '/join #channel [key]',
    description: 'Join a channel, optionally with a key/password',
  ),
  IrcCommandHelp(
    command: '/part',
    usage: '/part or /part #channel',
    description: 'Leave current or selected channel',
  ),
  IrcCommandHelp(
    command: '/msg',
    usage: '/msg nickname message',
    description: 'Send private message',
  ),
  IrcCommandHelp(
    command: '/query',
    usage: '/query nickname',
    description: 'Open a private chat tab',
  ),
  IrcCommandHelp(
    command: '/invite',
    usage: '/invite nickname [#channel]',
    description: 'Invite a user to current or selected channel',
  ),
  IrcCommandHelp(
    command: '/nick',
    usage: '/nick newNickname',
    description: 'Change your nickname',
  ),
  IrcCommandHelp(
    command: '/me',
    usage: '/me action',
    description: 'Send an action message',
  ),
  IrcCommandHelp(
    command: '/topic',
    usage: '/topic or /topic new topic',
    description: 'View or change channel topic',
  ),
  IrcCommandHelp(
    command: '/identify',
    usage: '/identify password',
    description: 'Identify with NickServ',
  ),
  IrcCommandHelp(
    command: '/key',
    usage: '/key secret',
    description: 'Set/change key for current channel',
  ),
  IrcCommandHelp(
    command: '/removekey',
    usage: '/removekey',
    description: 'Remove key/password from current channel',
  ),
  IrcCommandHelp(
    command: '/whois',
    usage: '/whois nickname',
    description: 'Show information about a user',
  ),
  IrcCommandHelp(
    command: '/kick',
    usage: '/kick nickname reason',
    description: 'Kick user from current channel',
  ),
  IrcCommandHelp(
    command: '/ban',
    usage: '/ban nickname-or-mask',
    description: 'Ban user or host mask from current channel',
  ),
  IrcCommandHelp(
    command: '/unban',
    usage: '/unban mask',
    description: 'Remove ban mask from current channel',
  ),
  IrcCommandHelp(
    command: '/op',
    usage: '/op nickname',
    description: 'Give operator status',
  ),
  IrcCommandHelp(
    command: '/deop',
    usage: '/deop nickname',
    description: 'Remove operator status',
  ),
  IrcCommandHelp(
    command: '/voice',
    usage: '/voice nickname',
    description: 'Give voice status',
  ),
  IrcCommandHelp(
    command: '/devoice',
    usage: '/devoice nickname',
    description: 'Remove voice status',
  ),
  IrcCommandHelp(
    command: '/mode',
    usage: '/mode #channel +/-mode',
    description: 'Send channel/user mode command',
  ),
  IrcCommandHelp(
    command: '/clear',
    usage: '/clear',
    description: 'Clear local chat history',
  ),
  IrcCommandHelp(
    command: '/help',
    usage: '/help',
    description: 'Show command help',
  ),
];

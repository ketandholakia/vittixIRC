# VIRC — Vittix IRC Chat Client

A modern, feature-rich, multi-server Internet Relay Chat (IRC) client for mobile (Android/iOS), built with Flutter. 

VIRC is designed to provide a robust mobile chatting experience with a clean "shell and drawer" UI, background lifecycle management, and built-in support for modern IRC features like SASL and Bouncers.

## ✨ Features

* **Multi-Server Sessions:** Connect to and manage multiple IRC networks (e.g., Libera Chat, OFTC) simultaneously.
* **Modern UI Architecture:** Seamlessly switch between channels and private messages using a sliding drawer shell interface.
* **Bouncer & SASL Support:** First-class support for IRC Bouncers (ZNC, soju) and secure authentication via SASL SCRAM-SHA-256 (with PLAIN fallback).
* **IRCv3 Capabilities:** `server-time` timestamps, `chathistory` gap backfill on join/reconnect, and `typing` indicators.
* **Secure Connections & Storage:** TLS with trust-on-first-use (TOFU) certificate pinning for self-signed servers, STS policy enforcement, passwords in the device keychain (`flutter_secure_storage`), and AES-encrypted, password-protected profile backups.
* **Background Keep-Alive:** An Android foreground service keeps your sessions connected while the app is backgrounded.
* **Smart Reconnects:** Exponential backoff, flap detection for unstable links, and auto-reconnect that halts on authentication failures instead of hammering the server.
* **Smart Notifications:** Receive local push notifications for private messages and @mentions, complete with deep-linking that routes you straight to the active channel when tapped.
* **Message Persistence:** Chat history is saved locally (SQLite) so you don't lose context when switching channels or restarting the app.
* **Intelligent Auto-complete:** Start typing `/` to see command suggestions, or `@` to auto-complete nicknames from the current channel.

## 🚀 Supported Commands

VIRC supports a wide array of standard IRC slash commands directly from the chat input:

* `/join #channel [key]` - Join a channel
* `/part [#channel]` - Leave a channel
* `/msg <nick> <message>` - Send a private message
* `/query <nick>` - Open a private message tab
* `/nick <new_nick>` - Change your nickname
* `/me <action>` - Send an action message
* `/topic [<new topic>]` - View or change the channel topic
* `/identify <password>` - Quickly authenticate with NickServ
* `/whois <nick>` - Fetch user information
* **Moderation:** `/kick`, `/ban`, `/unban`, `/op`, `/deop`, `/voice`, `/devoice`, `/mode`, `/key`, `/removekey`

## 📁 Project Structure

The app is built using a decoupled, state-driven architecture ensuring that the UI remains strictly a presentation layer.

```text
lib/
├── core/                         # Low-level IRC logic (protocol layer)
│   ├── irc_socket_service.dart   # Raw TCP/TLS socket management
│   ├── irc_parser.dart           # Raw string -> Model parsing
│   └── app_navigator.dart        # Global navigation key
├── models/                       # Data models (ServerConfig, ChatMessage, etc.)
├── services/                     # App-level services
│   ├── server_storage_service.dart
│   ├── notification_service.dart 
│   ├── backup_service.dart
│   └── app_lifecycle_service.dart
├── screens/                      # UI Screens separated by feature
│   ├── server/                   # Server list and configuration forms
│   ├── chat/                     # Chat shell and message view
│   └── settings/                 # App preferences
├── widgets/                      # Reusable UI components (ChatBubble, ServerTile)
├── state/                        # State management 
│   ├── session_manager.dart      # Global multi-server manager
│   └── irc_session_controller.dart # Per-server state and event routing
└── utils/                        # Helpers (Crypto, formatting)
```

## 🛠️ Getting Started

### Prerequisites

* Flutter SDK (`>=3.0.0`)
* Android Studio / Xcode (for emulation/compilation)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/vittixIRC.git
   cd vittixIRC
   ```

2. Fetch the Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## 📦 Major Dependencies

* `shared_preferences` - Local simple state and message history persistence.
* `flutter_secure_storage` - Keychain-backed secure storage for passwords.
* `flutter_local_notifications` - Native background and foreground notifications.
* `encrypt` & `crypto` - AES-256-CBC encryption for secure configuration backups.
* `file_picker` & `share_plus` - OS-level file handling for importing/exporting backups.

---

*Built with ❤️ using Flutter.*
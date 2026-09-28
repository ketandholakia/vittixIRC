# Vittix IRC - Development Roadmap

## Phase 1: Architecture & Stability (High Priority)
- [x] **Database Migration:** Replace `shared_preferences` for message history with `sqflite` or `Isar` to prevent memory bloat and UI lag.
- [x] **Pagination:** Implement lazy-loading for chat history scrolling to maintain 60 FPS in highly active channels.
- [x] **Network State UI:** Add an unobtrusive "Connecting..." / "Reconnecting..." indicator to the chat view header.

## Phase 2: Media & Sharing Integration
- [x] **Incoming Share Intents:** Finish integration of `receive_sharing_intent` to accept images/files from the host OS.
- [x] **HTTP Upload Service:** Implement an upload manager to push shared images to external hosts (e.g., 0x0.st, custom POST endpoints).
- [x] **URL Injection:** Automatically inject the hosted URL into the user's chat input field upon successful upload.

## Phase 3: Rich UX & Modernization
- [x] **Media Previews (Unfurling):** Background parsing of URLs to display inline image thumbnails and webpage OpenGraph previews.
- [x] **Inline Notifications:** Integrate `RemoteInput` into `flutter_local_notifications` to allow replying directly from the OS notification shade.
- [x] **Mentions Hub:** Create a unified view aggregating all `@mentions` and DMs across multiple servers.
- [x] **Jump to Bottom:** Add a floating action button that appears when scrolling up in a busy channel.

## Phase 4: Power User & Protocol Features
- [ ] **CertFP Support:** Allow generation or import of TLS client certificates for password-less authentication.
- [ ] **Untrusted Cert Pinning:** Add a UI prompt to manually trust/pin self-signed certificates for private networks.
- [ ] **Local Search:** Implement full-text search across the local SQLite database for channel histories.
- [ ] **Granular Theming:** Provide AMOLED pure-black themes and customizable font families (monospace support).

## Future Considerations
- Ignore lists / Spam filtering.
- WebRTC / DCC integration for direct P2P file transfers (if viable on mobile).
- Multi-device sync (potentially via IRCv3 features like `chathistory`).
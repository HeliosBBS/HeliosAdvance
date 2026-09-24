# Backlog

Features mentioned and not yet brainstormed, in dependency order. A line here is a name, a
purpose and what it depends on, plus anything the developer has already said about it, kept in
their words so nothing is lost before its brainstorm. Nothing on this list is designed or
built until it has been through `feature-brainstorm` and has a brief of its own.

## Foundations

- **Service lifecycle**: `hadv-service` runs as a Windows service or a daemon; starts, stops,
  reloads, reports health. Depends on: servers, nodes and one board.
- **Languages**: every string the whole estate uses lives in one TOML file per language, at
  `lang/<code>/<code>.toml` (for example `lang/en-us/en-us.toml`), or in the database; which of
  the two, and how every server gets them, is decided in the brainstorm, not assumed. Each file
  names its language (`en-us = English (United States)`). Translations work in both legacy code
  pages and UTF-8. Strings are structured so the board can be translated into any living
  language: verb tenses, plural, gender and case handled so languages other than English read
  correctly, with plural rules per language (CLDR-style categories) rather than a single plural
  form, and gendered and ordinal forms where the language requires them. Numbers, dates and
  currency are formatted per locale, separately from the user's date-format preference. Sizes
  are shown in human units (kilobytes, megabytes and so on), formatted per locale. Parody
  languages such as pirate are supported too. Research the existing standards for this before
  designing anything of our own. Language files do not embed colour codes; they use
  theme-defined macros to set colours, preserving theme integrity. A string missing from a
  language falls back to the board's default language, then to en-us, which ships complete, and
  is logged once; a raw tag is never shown. An executable picks its language from the operating
  system and falls back to en-us when that language is not available; en-us ships with the
  board and others are added later. Every string passes through one parser that replaces
  placeholders such as `{BBSNAME}` and the theme's colour macros. Depends on: servers. Touches
  every repository in the estate.
- **Classic text-mode interface**: the TUI tools have a classic BBS feel, similar to the
  RemoteAccess configuration menu: a pull-down menu system with a modal dialog box for
  settings; our own menu items and colour scheme; a bottom help line giving the field's valid
  range; mouse support nice to have, not required. Shared by every TUI tool. Depends on:
  languages.
- **Configuration**: every board setting has a key, default and kind; `hadv-config` (TUI and
  CLI; the CLI is for automation) and `hadv-config-gui` expose all of them with parity. Most
  settings are tunable there. Defaults are secure by default; loosening is the sysop's
  explicit choice. Runs on the server or on a separate computer for remote administration
  (the board hosted at a cloud provider, configured from the sysop's home computer as if it
  were local). Configuration changes are held until applied. Sign-in by the Sysop role only;
  no one can grant that permission to another role. Depends on: servers, remote
  administration, classic text-mode interface.
- **Sensitive data encrypted at rest**: user passwords stored as a hash (the previous system
  used Argon2id); a secret vault in the database that every server can read and decrypt,
  holding network passwords and other sensitive values each server needs (the previous system
  used a derived key-encryption key; ADV-001 already seals values under a board
  key-encryption key that join carries to each server); other sensitive fields encrypted in
  the database; keys managed. Depends on: servers.
- **Scripting layer**: all BBS logic runs in theme scripts through a public `bbs.*` API with a
  deprecation contract; the engine has no BBS logic of its own. Depends on: servers,
  configuration.
- **Theme packs**: scripts plus terminal text and graphics plus web code, in one pack. A
  board installs several; each user picks the one they use, and a new user starts on the pack
  the sysop has flagged as the default; the sysop installs, flags and disables packs. Two ship.
  The modern theme is the fallback every other pack falls back to, cannot be deleted, is not
  supported if edited; a sysop can disable it from selection and flag another pack as the
  default. Packs carry metadata and versioning, and are installed and updated through
  `hadv-config` and `hadv-config-gui`. Where theme files live (database or disk, and how every
  server gets them) is decided here, not assumed. Depends on: scripting
  layer.
- **Certificates**: `hadv-cert` (TUI only) generates self-signed certificates and installs
  supplied ones; TLS Telnet, HTTPS and SSH host keys draw on it. ACME is not spoken by the
  engine; an ACME client uses `hadv-cert` to install what it obtained. Certificates reload
  without a restart, so an ACME client can update them while the board runs. Every networked
  service that offers encryption does it over TLS 1.2 or TLS 1.3; the default key exchange
  uses perfect forward secrecy. SAN (Subject Alternative Name) and wildcard certificates are
  supported for all TLS services. High key sizes are supported and compromised key sizes
  rejected. The sysop configures TLS 1.2, TLS 1.3 and the key exchange in `hadv-config` and
  `hadv-config-gui`; they default to secure settings. Depends on: configuration.
- **Time zones and daylight saving**: times shown to callers and sysops follow daylight saving
  time where appropriate. Depends on: configuration.
- **Scheduled maintenance**: jobs the board runs on a schedule, once for the whole board.
  Jobs other entries already hand it: the daily statistics rollover, deleting accounts past
  their role's Maximum Days of User Inactivity, permanently deleting accounts whose time in the
  virtual deleted state is up, the re-scan sweep of quarantined uploads, and message base
  packing and renumbering. Depends on: servers, nodes and one board; time zones and daylight
  saving.
- **Attribute codes**: the colour and heart codes the board supports: WWIV, VBBS and VADV
  heart codes, with WWIV taking precedence over VBBS and VADV when both are entered; PCBoard
  (`@Xxx`) codes; Wildcat (`@xx@`) codes; Celerity (`|x`) codes; Renegade (`|xx`) codes;
  Synchronet (CTRL) codes. When importing from VirtualNET-type networks, VBBS and VADV codes
  are converted to correct ANSI; when importing from WWIV-type networks, WWIV codes are
  converted to correct ANSI. Depends on: nothing.
- **External archivers**: the sysop adds, edits and deletes external archivers (for example
  7-Zip, PKZIP, unarc) in `hadv-config` and `hadv-config-gui`. Each has command lines with
  replaceable variables, like the upload and download protocols: a string to detect the
  archive type from the file header (if possible), and compress, decompress, test and view
  command lines. Seeded with 7-Zip CLI command lines for the formats 7-Zip supports for both
  compression and decompression. Depends on: configuration.

## Callers

- **Terminal negotiation**: terminal capability negotiation shared by Telnet, SSH and
  WebSocket: CP437 or UTF-8, colour tier and screen size. xterm-256 and 24-bit colour in the
  theme colour model, with automatic downgrade to 16 colours; themes declare the tier they were
  drawn for. Depends on: nothing.
- **Telnet caller**: a caller connects over Telnet to a node and reaches the theme's welcome;
  option negotiation; connection limits, per-source throttling (one mechanism shared by every
  caller surface, honouring the exempt-source list from accounts and login), idle timeouts. Off
  by default. Default port TCP/23, default binding all addresses; whether it is on, the port and
  the binding all changeable in `hadv-config`. Depends on: servers, scripting layer, theme
  packs, languages, terminal negotiation. Touches the load tester.
- **Accounts and login**: sign-up, login, sessions across servers, lockouts; a second factor
  when the account's role requires it. A user's profile is private by default, and they may
  make it public: a private user is hidden from search, profile views, who's-online, activity
  lists and anything else where a regular user could see them or their activity, except from a
  role holding the permission to see private users; viewing a private profile shows only
  "This profile is private". A post or upload to a public area is the user's own affirmative
  act and shows as usual. A user never sees someone they have blocked in who's-online, unless
  they hold the permission to see everyone (the who's-online contract takes the viewer as an
  input for this). Lockout is board-wide policy with one implementation that
  every surface's sign-in uses (Telnet, SSH, web, the Admin API), counted in the database so
  moving between servers or surfaces resets nothing. Account #1, always the main sysop
  account, is never locked; any other account locks after x failed attempts for x amount of
  time, both configurable in `hadv-config`. An account holding the Sysop or Co-Sysop role
  that is locked out a few times within a window is locked permanently until a sysop unlocks
  it (a Sysop account only by a Sysop). Failed sign-ins also slow the source down on every
  surface and every account: each failure from an address makes that address's next attempt
  wait longer, and past a threshold the address is refused for a while; the server's own host
  is slowed but never refused. A list of exempt sources, separate from the trusted proxy list,
  covers addresses that stand for many callers (the HeliosSIP gateway, a load tester, a
  shared address). Every tunable here has a floor and a ceiling; loosening any of them, or
  adding an exempt source, warns loudly and needs the sysop's confirmation. The next
  successful sign-in shows how many failures there were and from where. Depends on: scripting
  layer, Telnet caller.
- **Reserved and former usernames**: nobody can register these usernames, in any letter case:
  `!@-REMOTE-@!`, `!@-NETWORK-@!`, `GUEST`, `NEW`, `SIGNUP`, `DEMO`, `SYSOP`, `W`, `WANDERER`,
  `ANONYMOUS`, `hostmaster`, `postmaster`, `abuse`, `webmaster`, `admin`, `administrator`,
  `soc`; nor any username starting with `~`, `` ` ``, `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`,
  `(`, `)`, `-`, `_`, `=`, `+`, `"` or `'`; nor any username with `@` anywhere in it. Days to
  Preserve Former Handles: a separate retention period, sysop-configurable with a default of 30
  days, during which a released or former handle, and its confusable lookalikes, is withheld
  from re-registration by anyone. Handle validation is one shared check, used wherever a handle
  is set (sign-up, a username change, the sysop's editor): legality, reserved names,
  uniqueness, and UTS #39 confusable skeletons, so look-alike handles cannot be registered.
  A handle may contain spaces, single spaces between words only: leading and trailing spaces
  are trimmed and runs of spaces collapsed. The mailbox name derived from a handle (a space
  becoming `.` or `_`) goes through the same uniqueness and confusable check, so "Dark Lord"
  and "Dark.Lord" cannot both exist. The maximum handle length fits the name fields of the
  networks the board supports (FTN and QWK among them; the brainstorm confirms the limits).
  Spaces are revisited if a compatibility issue turns up. Depends on: accounts and login.
- **Username change**: a user can change their own username; how often is a sysop-configurable
  setting. The old username becomes a former handle. Depends on: reserved and former
  usernames.
- **Language choice**: a user picks from the available languages when creating their account
  and can change it in their preferences. Depends on: languages, accounts and login.
- **Role-based access control**: roles carry permissions and configuration (upload/download
  ratio, whether 2FA is required, and the like). Every gate fails closed; every operator action
  is audited. Seeded roles, by fixed ID because names are editable: 1 Sysop, 2 Co-Sysop,
  3 User, 4 Guest, 5 New User. Sysop: super user, unrestricted global access; cannot be
  deleted; display name changeable, access not editable. Co-Sysop: limited administration
  (users, file areas, message bases); cannot touch system configuration, promote anyone to
  Sysop or Co-Sysop, take over Sysop or Co-Sysop accounts, or lock out a Sysop; cannot be
  deleted; editable (display name, additional restrictions). User: regular registered users;
  cannot be deleted; editable. Guest: not signed in; cannot be deleted; editable. New User:
  baseline probationary access; can be deleted; fully editable. Account #1 is always the main
  sysop account and owner of the system. The Sysop role requires 2FA by default; the sysop may
  turn that off for the role. Sysop and Co-Sysop hold the permission to see everyone in
  who's-online, private or blocked, by default. Depends on: accounts and login.
- **Who's online**: a list of who is currently online on the BBS; see classic BBSes for
  examples. A user whose profile is private does not show up in who's online, and a user does
  not see someone they have blocked. Sysop and Co-Sysop hold a permission to see everyone,
  bypassing a private profile or a block. Depends on: role-based access control.
- **Account deletion**: a user can delete their own account after a confirmation (typing
  something, or their second factor); account #1, the main sysop account, cannot delete
  itself. Deleting an account, whether the user, the Sysop or maintenance does it, puts it in
  a virtual deleted state, like a recycle bin, for a period configurable in `hadv-config` and
  `hadv-config-gui` up to a ceiling of 30 days, before it is deleted permanently. Maintenance
  deletes an account that has been inactive for longer than its role's Maximum Days of User
  Inactivity, a setting every role carries and the sysop can change on it: the Sysop role
  defaults to unlimited, Co-Sysop to 365 days, User to 180, New User to 30, and a new role to
  180. Account #1, the main sysop account, is never deleted for inactivity. While in the
  virtual deleted state the account is hidden, blocked from login and absent from the user list; its
  username and email address cannot be reused by a new user; the Sysop or a Co-Sysop can
  restore it. When the account is deleted permanently, any messages in its mailbox are
  deleted and cannot be restored, and its username and email address may be reused, subject
  to the former-handle period. The Sysop can delete an account permanently straight from the
  virtual deleted state, to comply with the EU GDPR; its posts, uploads and other data then
  show the placeholder [Deleted User]. Research whether and how the GDPR applies to the audit
  log and other logs. Depends on: accounts and login, RBAC, scheduled maintenance.
- **Second factor**: TOTP (RFC 6238), with self-service enrolment in text mode and by QR code
  on connections that support it; passkeys where the surface allows; required per role; the
  initial #1 Sysop enrols during first-run setup. Depends on: accounts, RBAC. Touches the Portal.
- **Account recovery**: a user who has forgotten their password, or lost their second factor,
  gets their account back. Depends on: accounts and login, second factor.
- **User profile and new-user questions**: the board stores, per account: deleted status, user
  number, handle, real name, company name, BBS name, email address, gender, birth date,
  address, location, zip code and phone number. Each question a new user is asked has a
  setting in `hadv-config` and `hadv-config-gui` of No, Optional or Required: real name
  (default Required; the sysop chooses, because a board that joins FidoNet must use real
  names; force a multi-word name, default Yes); company name (default No); email address (default Required); gender (No or Optional
  only, default No; the accepted gender codes are configured elsewhere); birth date (default
  No); address and zip code (default No; US and international); location, such as city, state
  and country (default Optional; optionally require a comma, default No); phone number
  (default No; US and international). A feature that needs a field the user has not given
  (real name, email address, gender, age) cannot be used by that user. Depends on: accounts
  and login.
- **Telnet over TLS caller**: the Telnet experience over a TLS-wrapped listener. Off by default.
  Default port TCP/992, default binding all addresses; whether it is on, the port and the
  binding all changeable in `hadv-config`. Depends on: certificates, Telnet caller.
- **SSH caller**: the same over SSH, host keys from certificates, option negotiation. Off by
  default. Default port TCP/22, default binding all addresses; whether it is on, the port and
  the binding all changeable in `hadv-config`. The sysop guide must explain that on a Linux host
  the system's own SSH service usually holds TCP/22, and how to move that service to another
  port (or the board's SSH to another port) so the two do not conflict. Depends on:
  certificates, Telnet caller. Touches the load tester and the SIP gateway.
- **Web caller**: a browser reaches the board over HTTP, HTTPS and HTTP/3 and gets the selected
  theme's web side. Off by default. Default ports TCP/80 (HTTP), TCP/443 (HTTPS), UDP/443
  (QUIC); HTTP redirects to HTTPS by default; default binding all addresses; whether it is on,
  the ports, the binding and the redirect all changeable in `hadv-config`. Depends on: scripting
  layer, theme packs, certificates.
- **Terminal-in-browser rendering**: the classic theme's terminal experience rendered in the
  browser: ANSI with animation and ANSI music. Web users can also play classic ANSI DOS games,
  carried over a WebSocket. The screen is not locked to a fixed 80x25 size that looks tiny on a
  2K or 4K monitor: the font scales to take up more of the page without breaking the aspect
  ratio, and rescales dynamically when the window is resized. Depends on: web caller.
- **Terminal capabilities**: the capabilities beyond terminal negotiation, shared by Telnet,
  SSH and WebSocket: graphics, mouse and fonts. SyncTERM font-loading sequences (PC and Amiga
  fonts), emitted only when the client announces support. Sixel inline graphics where negotiated
  (file previews, art gallery, TOTP enrolment QR), falling back to nothing, never to garbage.
  Mouse click regions for lightbar menus and file lists where the client reports mouse
  support. Baud-rate emulation as a user preference: off, 2400, 9600, 14400, 28800 or 57600,
  default off. ANSI music (`ESC[M` MML) passed through where supported, with a per-user
  opt-out, and stripped where not supported, since to most terminals `ESC[M` means delete
  line. Depends on: terminal negotiation, SSH caller, terminal-in-browser rendering.
- **Modern theme**: rich HTML on the web and a lightbar ANSI system on the terminal; shipped;
  the fallback. Depends on: theme packs, Telnet caller, web caller.
- **Classic theme**: strictly text-based; shipped; the web server renders it by conversion.
  Depends on: theme packs, Telnet caller, terminal-in-browser rendering.
- **Proxies in front of the board**: PROXY protocol v1 and v2, `X-Forwarded-For`,
  `X-Real-IP`, `Forwarded`; honoured only from a trusted proxy list so the caller's address
  cannot be forged. Depends on: Telnet, SSH and web callers.
- **Doors**: the board offers door games through BBSLink, DoorParty and Helios Doors
  (`hadv-doors`); the board never runs a door itself. Helios Doors is a separate,
  BBS-agnostic service, on the same hardware or its own; the board can use several
  `hadv-doors` instances, each separate, with no federation. The board registers with each
  instance and talks to it over the door hosting protocol: the board keeps the caller's
  connection and relays the game, passes the chosen game and only the player details its drop
  file needs (never a password), identifies a player by board and account number rather than
  handle, tells the instance when an account is permanently deleted, and turns the instance's
  status codes (full, all nodes busy and so on) into messages for the caller. BBSLink and
  DoorParty credentials live in the secret vault. `hadv-config` and `hadv-config-gui` can
  configure an instance. Web callers play legacy doors through terminal-in-browser rendering;
  doors built with the Door Kit are also drawn as HTML for web callers. Depends on: terminal
  capabilities, account deletion, languages, sensitive data encrypted at rest; blocked on the
  door hosting protocol (HeliosDoors).

## Operating the board

- **Public API**: the board's HTTP interface for clients, with its OpenAPI description.
  Depends on: web caller, accounts, RBAC. Touches the Portal and the load tester.
- **Waiting-for-Caller console**: `hadv-console` (TUI only; no CLI unless a use case appears)
  and `hadv-console-gui`, run on the server or remotely; long-lived tokens; the GUI minimises
  to the taskbar and can start minimised so it starts after login. It shows who is on which
  node on which server, and their activity; it spawns the user editor. Depends on: remote
  administration, classic text-mode interface.
- **Taskview**: in the WFC, see running tasks, with progress if the task supports it, and
  cancel a task if the task supports it, much as Nutanix Prism Central does. Depends on:
  Waiting-for-Caller console, scheduled maintenance.
- **User editor**: `hadv-useredit` and `hadv-useredit-gui`, spawned from the console or run
  alone. Depends on: RBAC, remote administration.
- **Server join by pairing code**: a sysop adds a server to the board: on the existing server,
  `hadv-config` shows a code; on the new server, `hadv-setup` asks for the existing server's
  address and the code; once the two agree, the new server receives what it needs over a
  secure channel. Settled for its brainstorm: the code is the secret of a password-
  authenticated key exchange, so a machine in the middle cannot complete the join and a wrong
  guess learns nothing; codes are single-use, expire in minutes, and a source that fails a few
  times is locked out; no private key is ever transferred, each server generates its own and
  gets a certificate signed over the paired channel from a board signing key held encrypted in
  the database; each server gets its own database login so removing a server revokes it alone;
  KEK rotation is a separate documented action for a compromised server; the local secrets
  file is protected by the operating system's best available tier (DPAPI at machine scope,
  systemd credentials, else a service-user-only file with a warning) and `hadv-setup` says
  which tier it got. The earlier design is read for the questions it settled, not for
  answers. Depends on: servers.
- **First-run setup**: `hadv-setup` (TUI and CLI; the CLI supports automation; runs only
  locally on the server) takes a fresh install to a running board:
  sysop account with its second factor enrolled, listeners, database, certificates. Depends on:
  servers, certificates, RBAC, second factor.
- **Installation**: Inno Setup (`setup.exe`) on Windows, WinGet wrapping it, RPM and DEB on
  Linux, a container image built from a Dockerfile; the same result on every target. Depends
  on: service lifecycle.
- **Auto-update**: a server updates itself from the published releases, verifying the
  release's signature and build-provenance attestation against the project's publishing
  identity before anything is applied (supply-chain protection built on the git and release
  infrastructure), rolling across a multi-server board one server at a time within the
  one-version skew rule. Depends on: installation, servers, nodes and one board.
- **Fault-tolerant database, documented**: a sysop guide chapter on running the board behind a
  PostgreSQL proxy that provides failover and pooling (Pgpool-II, or PgBouncer with Patroni
  and HAProxy); the engine needs nothing special. The proxy must pool in session mode: the
  servers' inter-server bus is LISTEN/NOTIFY, which needs a persistent session, and
  transaction-mode pooling breaks it silently. Depends on: servers, nodes and one board;
  the sysop guide.
- **Developer mode**: a mode that, when enabled, logs additional statistics needed for future
  development and optimisation, and measures the performance of routines and functions to
  show where code needs improving. Which metrics is still to be determined; the platform
  architecture (x86-64, ARM) and the operating system are included. The format is JSON.
  Metrics are local to each server and are never sent anywhere. It works hand in hand with the
  load tester. Depends on: servers, Telnet caller. Touches the load tester.
- **Language packs and string editors**: language packs carry metadata and versioning,
  mirroring themes, and are installed and updated through `hadv-config` and
  `hadv-config-gui`. `hadv-strings` and `hadv-strings-gui` edit the files. Depends on:
  languages, configuration, theme packs.

## Content

- **Conferences**: message and file bases live under conferences; a conference's permissions
  gate every base beneath it (no permission at the conference means none on any base below),
  and each base adds its own. Message conferences and file conferences share one shape. The
  sysop can easily move areas between conferences in `hadv-config` and `hadv-config-gui`.
  Restrictions: the roles that can access (default Sysop, Co-Sysop, User, New User, Guest);
  required minimum and maximum age (off, or an age); required genders (off, or a selection);
  required terminal type (off, or a selection). Duplicate checking, by a hash of the message or
  file searched across every area in the conference: off, or the number of duplicates allowed;
  default off. The initial conference is General, for messages and for files. Default
  conferences are created only by initial setup (`hadv-setup`) and are not changed
  automatically afterwards; sysops may freely edit or delete them. A conference cannot be
  deleted until it has no areas below it; existing areas must be moved or deleted first.
  Depends on: RBAC, user profile and new-user questions, first-run setup.
- **Message bases**: public message areas under conferences. If the network type supports it,
  adding a Sub or Echo asks whether to send a Sub request automatically; deleting one asks
  whether to send a Drop request; and if the network supports it and the sysop chooses to
  advertise, the sysop is asked whether to send an update of the Sub or Echo list.
  Restrictions: the roles that can read (default Sysop, Co-Sysop, User, New User, Guest), post
  (default Sysop, Co-Sysop, User, New User) and moderate (default Sysop, Co-Sysop); required
  minimum and maximum age, genders and terminal type, as for conferences. Settings, with
  defaults: maximum messages (5000); purge by age (off, or days; off); duplicate checking by a
  hash searched in the area (off, or the number allowed; off); allow anonymous posts (no);
  require real names (no); require an internet email address (no); allow message quoting
  (yes); allow word wrap (yes); required reading (no); allow message edit (off, within N
  minutes, or always; within 15 minutes; networked areas force off), edited messages keeping
  their prior bodies, readers seeing an "edited" marker and moderators the diff; slow mode, one
  post per user per N minutes (off); auto-close inactive threads (off, or days; off); pinned
  messages with an optional expiry date, set by the area's moderators; watched words with an
  action of block, send to the moderation queue, or tag silently (none seeded); required
  approval (no). Moderator thread tools: split, merge, move (leaving a stub), close. Maximum
  message size in bytes or lines (64 KB; networked areas clamp to the network's limit).
  Attachment policy: off, allowed, or allowed with approval, with a maximum attachment size and
  count. An origin line or network tagline per area, with a board-wide default. A read-only,
  archived state: no new posts, existing ones readable (off). Message base packing and
  renumbering as a maintenance job, safe against in-flight readers. Export a message or thread
  to text, to print or save to the user's download area. Area aliases or short names usable in
  menu commands and the `area:` search filter. Default new-scan participation: force on,
  default on, or default off (default on). Area sort order and numbering independent of
  creation order, shared with the web front end. Per-area header display: real name or handle,
  location, and whether the network address is shown. An "Attachment Storage Backend" setting
  per area, letting its attachments live on a different storage-registry entry from the area's
  own files. Initial areas, created only during initial setup and freely editable or deletable
  afterwards: Announcement (read by Sysop, Co-Sysop, User, New User, Guest; required reading,
  yes) and General Discussion (read by Sysop, Co-Sysop, User, New User, Guest; post by Sysop,
  Co-Sysop, User, New User; moderate by Sysop, Co-Sysop). Depends on: conferences, account
  deletion, scheduled maintenance.
- **File bases**: file areas under conferences. Storage is a separate entry, since more than
  file areas need it. Local directory and file paths are supported; the architecture must
  handle availability across servers: a file local to one server may need to be transferred
  temporarily to another, or marked OFFLINE when its owning server is unavailable. An OFFLINE
  file stays listed and requestable (default: listed). Metadata is read from files that
  support it (audio, images) when uploaded outside an archive; EXIF and other embedded
  metadata are stripped from images on upload after being harvested into the file record
  (default: strip). A free-file, no-ratio flag per file and per area. A new-files scan since
  the last call, honouring the same follow graph as the new-message scan. File comments and
  ratings by users who downloaded the file, using the same reaction model as social media
  features. Resumable, chunked HTTP uploads on the web front end. Maximum upload size per file
  and per area (off, or bytes; off). Upload description requirements: minimum length, extended
  multi-line (default one line, at least 10 characters). An upload credit model: bytes, files
  or ratio-exempt, with per-role and per-area overrides (default 3:1 by bytes). Download
  counters per file, with most-downloaded and newest-files listings. Listing options: sort by
  name, date, size or downloads; pattern filter; paged or full list. A tagged-file batch queue:
  tag while browsing, download the batch at the session's end. Aborted-upload handling, with
  resume on the next call for legacy protocols. Uploader attribution in listings, and a "my
  uploads" view per user. A per-area file naming policy: long names or 8.3, case handling,
  illegal-character rewriting. Ad-file injection: sysop-configured advertisement text stamped
  as an extra file into outgoing archives, with its own enable, text and filename settings;
  default off, and never into an archive that carries a signature. Depends on: conferences,
  account deletion, storage.
- **Private messages**: user-to-user mail on the board. Depends on: accounts, RBAC, account
  deletion.
- **File transfer on classic connections**: upload and download protocols over Telnet and SSH
  sessions. Depends on: Telnet and SSH callers, file bases.
- **SSH public-key login**: a user uploads a public key (on the web, or by file transfer on a
  classic connection) and logs in with it; a required second factor still applies. Depends
  on: SSH caller, accounts, second factor, file transfer.
- **Full-screen text editor**: a full-screen text editor for legacy protocols, with ANSI
  cursor positioning, automatic word wrap, insert and overwrite modes, block and line
  operations, inline colour code support, extended ASCII support, message quoting and CTRL
  command support. File attachments are supported where allowed. External full-screen editors
  may be added later. Web users always get a full-screen editor. Depends on: message bases,
  private messages, file transfer on classic connections, attribute codes.
- **Basic line text editor**: a basic line editor with message quoting, for legacy protocols;
  web users always get a full-screen editor, and legacy protocols default to the full-screen
  editor. A caller without ANSI gets the line editor, whatever the preference. Depends on:
  message bases, private messages.
- **Bulk file import**: `hadv-fileimport` loads files into the board's file bases from the
  command line. Depends on: remote administration, file bases.
- **SMTP client (sending email)**: the board delivers outbound email directly to destination
  mail servers, or forwards it to a dedicated SMTP relay configured in `hadv-config` and
  `hadv-config-gui`; configuring a relay automatically disables direct delivery (possibly a
  dynamic toggle). Per-domain rate limiting, thresholds configurable, so destination servers
  do not block the board. A robust local mail queue for deferrals and retries, with
  configurable exponential backoff for connection and delivery retries. DKIM signing; ARC
  (Authenticated Received Chain); modern forwarding mechanics that preserve upstream
  validation (DKIM, SPF, DMARC). The goal is not for users to set up an email client and send
  through the board; that may be a later feature. Depends on: private messages, sensitive data
  encrypted at rest.
- **SMTP server (receiving email)**: the board receives email for its users. Strict anti-relay
  rules: accept only email for local users and local domains. Port binding and listening
  addresses configurable. Maximum simultaneous connections configurable, default 100, shared
  across the SMTP, POP3 and IMAP servers. The SMTP server and each transport mode can be
  enabled and disabled individually in configuration, and all are off by default. The normal
  internet ports by default: TCP/25 receives from other mail servers, with STARTTLS offered and
  plain text accepted from a server that does not use it, for legacy network compatibility;
  TCP/587 (STARTTLS) and TCP/465 (implicit TLS, SMTPS) are the submission ports for users'
  email clients, a later feature. Per-user address format: `handle@domain`, `first.last@domain`
  or a user-chosen alias, default `handle@domain`. Per-user address aliases; a catch-all or
  postmaster destination. Mailbox quota per user and per role, with a warning threshold,
  default off. Maximum accepted message size and maximum attachment size, default 25 MB. The
  board's private mail and external email share one store. Depends on: private messages,
  certificates, user profile and new-user questions.
- **POP3 client (receiving email)**: the board retrieves inbound mail from a catch-all mailbox
  on an external POP3 server, over POP3 or POP3S (SSL/TLS), and automatically parses and
  routes it to the right internal user. It generates a bounce when the recipient does not
  exist or delivery fails; the sysop can suppress bounces to bound backscatter. Background
  polling interval configurable; deleting mail from the server after processing is a
  configurable option. Depends on: SMTP server, SMTP client.
- **IMAP client (receiving email)**: the board retrieves inbound mail from a catch-all mailbox
  on an external IMAP server, over IMAP or IMAPS (SSL/TLS), and parses and routes it to
  internal users. It generates a bounce for a non-existent or failed recipient; the sysop can
  suppress bounces to bound backscatter. It keeps the IMAP session connected to use push (the
  IDLE command), and falls back to background polling, interval configurable, for a server
  without push. Deleting processed mail from the server is a configurable option. Depends on:
  SMTP server, SMTP client.
- **User statistics**: per account: first on, last on, logons today and in total, posts today
  and in total, netmail and email sent and received today and in total, netmail and email sent
  to sysops in total, uploads and upload bytes in total, downloads and download bytes in total.
  A day for the "today" counters is a day in the board's time zone. Depends on: accounts and
  login, message bases, private messages, file bases, time zones and daylight saving.
- **BBS statistics**: board-wide counters: logons, online time, netmail and email sent,
  feedback sent, new users, posts, uploads and upload bytes, downloads and download bytes
  today, and the maximum concurrent connections, in total and per connection type. Every
  counter is recorded per node and BBS-wide, and the console can view either. All-time totals
  sit alongside today's counters; the daily rollover is owned by daily maintenance. Statistics
  export as CSV or JSON from the Admin API and the console. A histogram of the busiest hours
  and days, and the peak concurrent sessions with the time they occurred. Depends on: user
  statistics, Waiting-for-Caller console, scheduled maintenance.
- **User preferences**: each user sets, with its default: language and time zone (the
  board's); short date format such as MM/DD/YYYY, and time format, 12 or 24 hour (the board's);
  theme (the default theme set in `hadv-config` and `hadv-config-gui`); terminal type:
  auto-detect, extended ASCII, ANSI or RIP (auto-detect); colour: auto-detect, yes or no
  (auto-detect); screen length and width: auto-detect or a number (auto-detect); expert mode,
  menus hidden unless `?` is pressed (no); pause at the end of each screen (yes); forward all
  netmail and email to the external email address (no); clear screen between messages (no);
  ask for a new message scan (no); remember the current message area (no) and file area (no);
  default download protocol, from the protocols the system defines (ZModem); hang up after a
  file transfer (no); editor: full-screen or line, on classic connections only (full-screen);
  message reading order: forward, reverse or threaded (forward); show signature on posts
  (yes); private profile (yes, as accounts and login describes). Some of these may be better
  stored in a separate table linked to the user. Depends on: language choice, time zones and
  daylight saving, theme packs, message bases, private messages, file transfer on classic
  connections, SMTP client, full-screen text editor, basic line text editor, terminal
  capabilities.
- **Voting booth**: a voting booth that allows polling. A poll is a question with up to 10
  replies and an optional write-in, single-choice or multiple-choice (pick N); a poll can be
  made required at login. RBAC decides who can create polls, set one required, vote, see the
  summary after voting and see detailed results, and each poll has its own RBAC and
  restrictions. Defaults: create and set required, Sysop and Co-Sysop; vote and see the
  summary, Sysop, Co-Sysop, User and New User; see detailed results, Sysop and Co-Sysop.
  Detailed results honour private profiles. A poll has an expiry date and closes
  automatically; a closed poll stays readable with its results. Changing your vote: off or
  until the poll closes, default off. Result visibility: after voting, after close or always,
  default after voting. A voting booth menu; configurable in `hadv-config`, `hadv-config-gui`
  and inside the BBS. Depends on: role-based access control.
- **ANSI art gallery**: a gallery driven by SAUCE metadata: artist pages, pack browsing and
  group credits. Art renders to the terminal, to HTML and to PNG (for link previews). An
  optional seeded gallery area on a fresh install points at a public art-pack archive.
  Depends on: file bases, external archivers, terminal capabilities, first-run setup.

## Mail networks

- **Mail networks**: the board supports several kinds of BBS network, and each kind's mail
  processor (tosser) is an external CLI program: `hadv-fido` for FTN (FidoNet Technology
  Networks), `hadv-vnet` for VirtualNET networks, `hadv-qwk` for QWK BBS networks, `hadv-ww4`
  for WWIVnet technology networks and `hadv-nntp` for Usenet. The CLIs only process message
  packets and take no incoming connections; every transport, incoming and outgoing (BinkP, BinkP
  over TLS, FTP and FTPS), lives in `hadv-service`. `hadv-nntp` is the one exception: an NNTP
  client that reaches out, pulls in the selected newsgroups, posts messages, then processes
  them. Whether the CLIs reach the board's data through the Admin API or through the database
  directly is decided in the brainstorm: CPU cost through a web server is the concern. The BinkP
  listeners, BinkP TCP/24554 and BinkP over TLS TCP/24553, are off by default and bind to all
  addresses; whether each is on, its port and its binding changeable in `hadv-config`. Incoming
  FTP and FTPS are the FTP and FTPS server's listeners. Depends on: remote administration,
  message bases, private messages.
- **FTN networks (`hadv-fido`)**: multiple FTN networks and multiple AKAs per network, with AKA
  matching on export. NODELIST and NODEDIFF filenames configurable per network; when they
  arrive by TIC the nodelist is compiled, for viewing, searching and validating systems for
  netmail, and a netmail destination is validated against it before queueing, unknown
  addresses rejected. Netmail: inbound routing to local users; outbound with crash, hold,
  direct and file-attach flags; file-attach and FREQ handling with per-link RBAC and size
  caps. Echomail import and export per area, with area-tag mapping to local message areas;
  an origin line per area; tear line, SEEN-BY and PATH kludges handled on export. A
  duplicate-message database with configurable retention, default 30 days. AreaFix and
  AreaMgr, inbound and outbound. TIC processing: inbound files routed to file areas, outbound
  hatching. Per-link session, packet, TIC and AreaFix passwords, stored in the shared secret
  store. BinkP 1.1 transport with CRAM-MD5, BinkP over TLS, and BinkD-compatible outbound scheduling. Type
  2+ and 2.2 packets read and written; a maximum message body size on export. A routing
  table: which links get which netmail, hub and uplink designation, bundle archive format.
  Unknown-node inbound handling: Reject, Unsecure inbound or Accept, default Reject. Hub
  operation: per-link read-only echoes and area passthrough. Per-link flow reports: packets
  and bytes in and out, dupes rejected, last successful session. Depends on: mail networks,
  file bases, external archivers.
- **QWK BBS networks (`hadv-qwk`)**: several QWK networks, each with its settings and their
  defaults: enabled (disabled); support gating (no); network name, hub system ID, hub address
  (IP or FQDN), QWK username and QWK password (blank); archive format, from the list in
  `hadv-config` (ZIP); connection method, hidden for the future, FTP only (FTP); call-out days
  of the week, and call-out frequency in times per day (4); include kludge lines (no),
  VOTING.DAT (yes), HEADERS.DAT (yes), UTF-8 characters (yes) and MIME-encoded text (no);
  word-wrap exported messages (no); extended (QWKE) packets (no); export colour code format:
  remove, ANSI or SBBS (remove). Each QWK network keeps its own new-post pointer so no message
  is sent twice. Depends on: mail networks, external archivers.
- **QWK network accounts**: an account flagged as a QWK network account (default no) is the
  account another BBS on a QWK BBS network, such as DoveNET, uses; it is taken straight to the
  QWK menu and logged off when it quits that menu. A setting, default No, has sign-up ask
  whether the new account is a QWK network account, and a yes prompts for its BBS name.
  Depends on: user profile and new-user questions, QWK BBS networks.
- **QWK offline mail**: a user downloads their messages as a QWK packet and reads them
  offline. Per-user packet settings: maximum messages, maximum packet size, areas included,
  personal mail only, and archive format from the configured archiver list (default the
  board's). Per-user pointers honoured when a packet is built; "reset pointers" and "set
  pointers to date". CONTROL.DAT, MESSAGES.DAT and *.NDX generation options; BULLETIN, NEWS
  and GOODBYE files included. REP import validates the packet's BBS ID, rejects foreign
  packets and handles stale pointers. Depends on: message bases, private messages, file
  transfer on classic connections, external archivers.
- **FTP and FTPS server (uploading and downloading files)**: a secure FTP server in
  `hadv-service`, supporting standard FTP and secure FTPS (SSL/TLS). Port binding and
  listening addresses configurable; by default the normal ports, TCP/21 for FTP and TCP/990
  for FTPS, bound to all addresses. Structured logging and monitoring of every access attempt.
  Integrated with RBAC. A global enable and disable, off by default. Session timeout and
  inactivity handling. QWK and QWK network file transfers: special files generated per user,
  and an uploaded QWK REP packet processed by the mail tosser. Maximum simultaneous
  connections configurable, default 100. Virtual accounts: special access accounts whose
  username and password are stored outside the user table, such as
  `<nodenumber>@~<networkname>`. Depends on: QWK offline mail, QWK BBS networks, sensitive
  data encrypted at rest.
- **VirtualNET networks (`hadv-vnet`)**: first-class support for every feature: netmail
  inbound and outbound, posts and file areas. Multiple VirtualNET networks. Advanced Update of
  BBSLIST.* and AREALIST.* files. Network roles NC, RC, AC and SC. ADD and DROP SUB requests
  and SUB CREATE. Flow reports. ORIGIN.ID. Being a hub for other nodes, which log in by FTP or
  FTPS as `<nodenumber>@~<networkname>`. The developer will provide a full specification.
  Depends on: mail networks, file bases, FTP and FTPS server, attribute codes.
- **WWIV networks (`hadv-ww4`)**: the WWIVnet packet specification. Address format
  `@node.netname`; multiple WWIVnet networks, each with its own node number. Sub hosting: the
  host and subscriber model, add and drop sub requests, a host designated per sub. BBSLIST,
  CONNECT and CALLOUT data maintained and distributed. Packet transport by BinkP
  through `hadv-service`, with per-link passwords. WWIV email routed inbound and outbound to local
  users. Heart codes translated on import and export (see attribute codes). Depends on: mail
  networks, attribute codes.
- **Usenet (`hadv-nntp`)**: an NNTP client and tosser for Usenet. Multiple NNTP networks (such as "Usenet"
  and "InterNetNews"), each with several Usenet servers for backfill and one designated for
  sending posts. Nothing is imported automatically: the sysop sets up each newsgroup as a
  message base, or links a file area to a binary newsgroup, and links it to a network, an
  affirmative step that shows a warning for binary groups. The list of available groups
  downloaded automatically; a group subscription list with search; an initial backfill
  article count, default 500. Per-group article retention: off, days or maximum articles,
  default 30 days. Message-ID and References headers mapped to the local thread model both
  ways. Posting identity: the From: address for local posts, with a per-network override.
  AUTHINFO USER/PASS authentication, TLS and per-server connection limits. Depends on: mail
  networks, file bases.

## Moderation

- **Content moderation**: one moderation queue where the Sysop, Co-Sysops and users with a
  moderator role see all content that needs human verification, in a single consolidated view
  covering every content type: pending message posts, pending file uploads and user-reported
  content. The backend may be one queue or several aggregated at the presentation layer, as
  long as the view is unified. The main view is a list of high-level subjects; selecting one
  opens a detail view with full context (message text, file metadata and virus-scan results,
  report reason). Actions depend on the type. Messages: approve, delete, view user, ban user,
  skip, flag to #1 Sysop. Files: approve, move, delete, view user, ban user, skip, flag to #1
  Sysop. Reported content: approve, delete, view user, view reporter, ban user, skip, reply to
  reporter, message the content's creator, flag to #1 Sysop. Sequential review mode feeds
  items one after another, where skip defers the item and loads the next; in the list, skip
  returns to the list. Multi-select in the list allows mass approve and mass delete, to handle
  floods and spam. A moderator claims an item so two moderators do not work the same one. RBAC
  strictly governs what a user sees (only content they are allowed to moderate) and every
  action and sub-action; the sysop defines the permissions (for example, a moderator who can
  delete content but not ban users). Reported content is never visible to the user who posted
  it, except the #1 Sysop. Flag to #1 Sysop raises a high-visibility notification or
  indicator, such as a prominent red `!`. Every action (approvals, deletions, bans, skips,
  escalations) is audited with timestamp, item, action and moderator; deleting content
  prompts for a brief reason, kept with the audit entry or the user's profile. A report
  carries a structured reason (spam, off-topic, abuse, illegal, or other with text) that
  drives queue priority. When an active post collects a configurable number of reports from
  different users, it is withheld from public view and moved to the queue ("withheld", not
  "quarantined": virus scanning uses quarantine for an upload stuck on a scanner failure, and
  one word for two states in two subsystems is a defect waiting to happen). A moderator can
  approve and release a file the scanner flagged as infected: accountable, not the default,
  and always writing an audit entry naming the verdict overridden. Per-user approval requires
  approval of a specific user's next N posts, not just per area. The queue can be reviewed
  from `hadv-console` and `hadv-console-gui`, which show when content is waiting. Each
  moderator can opt in or out of real-time alerts when a new item enters the queue. Depends
  on: message bases, file bases, private messages, Waiting-for-Caller console.
- **Virus scanning and archive conversion**: uploads are virus scanned online, offline or in
  the background, chosen in `hadv-config` and `hadv-config-gui`. Online scans immediately
  after the upload and shows the user a progress screen; offline scans after the user has
  signed off and sends a notification with the results; background scans while the user is
  still online, followed by a notification of the results. The virus scanner and its command
  line or lines are configurable, default the ClamAV command line. A maximum file size: a file
  over it cannot be scanned. A maximum recursion: how deep the scan goes into archives inside
  archives. Notifying the user is configurable, default notify. A file that fails its scan is
  flagged or deleted, default delete; a file that cannot be scanned, an oversized one
  included, is flagged or deleted, default flag. Flag sends the file to content moderation,
  hidden until approved. Archives can be converted to a different format, default no
  conversion: a file type that cannot be decompressed is compressed into the converted
  archive type, and the directory structure inside an archive is preserved when decompressing
  and carried into the converted archive. Archives inside archives are detected, decompressed
  and scanned as well, but not converted. Files arriving through BBS networks are scanned too;
  when the board is a network hub, files only passing through, not being added to the board,
  are neither converted nor scanned. Email attachments to local users are scanned but not
  converted. An upload the scanner itself failed on is quarantined, a state separate from
  cannot be scanned: an automatic re-scan sweep periodically re-submits quarantined uploads
  and releases each on a clean result, with no human queue entry. Depends on: content
  moderation, file transfer on classic connections, mail networks, SMTP server, external
  archivers, scheduled maintenance.
- **Bans, suspensions and appeals**: ban user, from the moderation queue, offers a permanent
  ban or a temporary suspension (such as 24 hours, 7 days or 30 days) with automatic
  restoration. A shadow-ban ("silence") sits between suspension and ban: the user sees their
  own posts and nobody else does (default: Sysop and Co-Sysop). Banning prompts for a brief
  reason, kept with the audit entry or the user's profile, and for what happens to the user's
  content: delete all of it, replace their name with a placeholder such as "Banned User", or
  take no action. A banned user from an external network is added to a global ban list, and
  the mail tossers reject their future messages. Shared ban lists are an opt-in subscription
  to another Helios system's signed, exported ban list. Appeals (default on, one per 7 days):
  a banned or suspended user can log in to one restricted screen that sends one message to the
  moderation queue. An appeal escalates to the #1 Sysop automatically when every
  otherwise-eligible moderator has a conflict of interest with it (for example, the only
  moderator is the one who applied the ban). Depends on: content moderation, mail networks.
- **Sysop notification triggers**: the Sysop is notified of a new user, an upload awaiting
  approval, feedback received and an appeal filed, in the inbox and optionally by email.
  Depends on: bans, suspensions and appeals, SMTP client.

## Chat

- **Multi-user chat**: users chat with other online users in an IRC-style chat, supported by
  the content moderation system, honouring blocks and private profiles as who's online does.
  Depends on: who's online, content moderation.
- **Sysop break-in chat**: the Sysop can break in on a caller with a two-way split-screen chat
  from the WFC consoles (`hadv-console`, `hadv-console-gui`). Sysop only by default; the Sysop
  can grant the permission to other roles. A caller without ANSI gets line-by-line chat.
  Depends on: Waiting-for-Caller console, terminal negotiation.

## Not yet described

Storage (one storage registry shared by file areas, message attachments and more), social
media features (the reaction model and the follow graph), blocking a user (accounts and login,
who's online and multi-user chat honour it), notifications (the inbox and alerts that virus
scanning, content moderation and sysop notification triggers send), feedback to the sysop
(counted in BBS statistics, notified by sysop notification triggers), RIP graphics (offered as
a terminal type in user preferences), and everything else the developer adds as it comes up.

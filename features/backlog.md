# Backlog

Features mentioned and not yet brainstormed, in dependency order. A line here is a name, a
purpose and what it depends on, plus anything the developer has already said about it, kept in
their words so nothing is lost before its brainstorm. Nothing on this list is designed or
built until it has been through `feature-brainstorm` and has a brief of its own.

## Foundations

- **Service lifecycle**: `hadv-service` runs as a Windows service or a daemon; starts, stops,
  reloads, reports health. Depends on: servers, nodes and one board.
- **Configuration**: every board setting has a key, default and kind; `hadv-config` (TUI and
  CLI; the CLI is for automation) and `hadv-config-gui` expose all of them with parity. Most
  settings are tunable there. Defaults are secure by default; loosening is the sysop's
  explicit choice. Runs on the server or on a separate computer for remote administration
  (the board hosted at a cloud provider, configured from the sysop's home computer as if it
  were local). Configuration changes are held until applied. Sign-in by the Sysop role only;
  no one can grant that permission to another role. Depends on: servers, remote
  administration, classic text-mode interface.
- **Classic text-mode interface**: the TUI tools have a classic BBS feel, similar to the
  RemoteAccess configuration menu: a pull-down menu system with a modal dialog box for
  settings; our own menu items and colour scheme; a bottom help line giving the field's valid
  range; mouse support nice to have, not required. Shared by every TUI tool. Depends on:
  nothing.
- **Sensitive data encrypted at rest**: passwords hashed, secrets and other sensitive fields
  encrypted in the database, keys managed. Depends on: servers.
- **Scripting layer**: all BBS logic runs in theme scripts through a public `bbs.*` API with a
  deprecation contract; the engine has no BBS logic of its own. Depends on: servers,
  configuration.
- **Theme packs**: scripts plus terminal text and graphics plus web code, in one pack. A
  board installs several; each user picks the one they use, and a new user starts on the pack
  the sysop has flagged as the default; the sysop installs, flags and disables packs. Two ship.
  The modern theme is the fallback every other pack falls back to, cannot be deleted, is not
  supported if edited; a sysop can disable it from selection and flag another pack as the
  default. Where theme files live (database or
  disk, and how every server gets them) is decided here, not assumed. Depends on: scripting
  layer.
- **Certificates**: `hadv-cert` (TUI only) generates self-signed certificates and installs
  supplied ones; TLS Telnet, HTTPS and SSH host keys draw on it. ACME is not spoken by the
  engine; an ACME client uses `hadv-cert` to install what it obtained. Depends on:
  configuration.

## Callers

- **Telnet caller**: a caller connects over Telnet to a node and reaches the theme's welcome;
  option negotiation; connection limits, per-source throttling (one mechanism shared by every
  caller surface, honouring the exempt-source list from accounts and login), idle timeouts.
  Default port
  TCP/23, default binding all addresses, both changeable in `hadv-config`. Depends on:
  servers, scripting layer, theme packs. Touches the load tester.
- **Accounts and login**: sign-up, login, sessions across servers, lockouts; a second factor
  when the account's role requires it. A user's profile is private by default, and they may
  make it public: a private user is hidden from search, profile views, who's-online, activity
  lists and anything else where a regular user could see them or their activity, except from a
  role holding the permission to see private users; viewing a private profile shows only
  "This profile is private". A post or upload to a public area is the user's own affirmative
  act and shows as usual. A user never sees someone they have blocked in who's-online (the who's-online contract takes
  the viewer as an input for this). Lockout is board-wide policy with one implementation that
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
  turn that off for the role. Sysop and Co-Sysop hold the permission to see private users in
  who's-online by default. Depends on: accounts and login.
- **Second factor**: TOTP; passkeys where the surface allows; required per role; the initial
  #1 Sysop enrols during first-run setup. Depends on: accounts, RBAC. Touches the Portal.
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
- **Telnet over TLS caller**: the Telnet experience over a TLS-wrapped listener. Default port
  TCP/992, default binding all addresses, both changeable in `hadv-config`. Depends on:
  certificates, Telnet caller.
- **SSH caller**: the same over SSH, host keys from certificates, option negotiation. Default
  port TCP/22, default binding all addresses, both changeable in `hadv-config`. The sysop
  guide must explain that on a Linux host the system's own SSH service usually holds TCP/22,
  and how to move that service to another port (or the board's SSH to another port) so the
  two do not conflict. Depends on: certificates, Telnet caller. Touches the load tester and
  the SIP gateway.
- **SSH public-key login**: a user uploads a public key (on the web, or by file transfer on a
  classic connection) and logs in with it; a required second factor still applies. Depends
  on: SSH caller, accounts, second factor, file transfer.
- **Web caller**: a browser reaches the board over HTTP, HTTPS and HTTP/3 and gets the
  selected theme's web side. Default ports TCP/80 (HTTP), TCP/443 (HTTPS), UDP/443 (QUIC);
  HTTP redirects to HTTPS by default; default binding all addresses; ports, binding and the
  redirect all changeable in `hadv-config`. Depends on: scripting layer, theme packs,
  certificates.
- **Terminal-in-browser rendering**: the classic theme's terminal experience rendered in the
  browser: ANSI to HTML with animation and ANSI music. Depends on: web caller.
- **Modern theme**: rich HTML on the web and a lightbar ANSI system on the terminal; shipped;
  the fallback. Depends on: theme packs, Telnet caller, web caller.
- **Classic theme**: strictly text-based; shipped; the web server renders it by conversion.
  Depends on: theme packs, Telnet caller, terminal-in-browser rendering.
- **Proxies in front of the board**: PROXY protocol v1 and v2, `X-Forwarded-For`,
  `X-Real-IP`, `Forwarded`; honoured only from a trusted proxy list so the caller's address
  cannot be forged. Depends on: Telnet, SSH and web callers.
- **Languages**: every string in one TOML file per language, shared by every executable;
  plural, gender and case handled so languages other than English read correctly;
  `hadv-strings` and `hadv-strings-gui` edit them. Where language files live (database or
  disk, and how every server gets them) is decided here, not assumed. Depends on:
  configuration.

## Operating the board

- **Admin API**: being brainstormed as part of **remote administration** (ADV-002), with
  operator sign-in and tokens: sign-in with 2FA, session tokens scoped for automation, the
  audit naming the credential, long-lived console tokens whose lifetime is tunable in
  `hadv-config` between a hard floor and ceiling. The Admin API is TCP only; HTTP/3 is
  dropped for it. The original line: what the configuration,
  console, user-editor and strings tools use; nothing
  but the engine touches the database. Default ports TCP/8443 (HTTPS) and UDP/8443 (QUIC),
  default binding all addresses, changeable in `hadv-config`. Depends on: RBAC.
- **Public API**: the board's HTTP interface for clients, with its OpenAPI description.
  Depends on: web caller, accounts, RBAC. Touches the Portal and the load tester.
- **Waiting-for-Caller console**: `hadv-console` (TUI only; no CLI unless a use case appears)
  and `hadv-console-gui`, run on the server or remotely; long-lived tokens; the GUI minimises
  to the taskbar and can start minimised so it starts after login. Depends on: remote
  administration, classic text-mode interface. The original line: who is on which node
  on which server, activity; spawns the user editor. Depends on: Admin API.
- **User editor**: `hadv-useredit` and `hadv-useredit-gui`, spawned from the console or run
  alone. Depends on: RBAC, Admin API.
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
- **Installation**: Inno Setup on Windows, WinGet wrapping it, RPM and DEB on Linux, a
  container image; the same result on every target. Depends on: service lifecycle.
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

## Content

- **Conferences**: message and file bases live under conferences; a conference's permissions
  gate every base beneath it (no permission at the conference means none on any base below),
  and each base adds its own. Depends on: RBAC.
- **Message bases**: public message areas under conferences. Depends on: conferences.
- **File bases**: file areas under conferences. Depends on: conferences.
- **Private messages**: user-to-user mail on the board. Depends on: accounts, RBAC.
- **File transfer on classic connections**: upload and download protocols over Telnet and SSH
  sessions. Depends on: Telnet and SSH callers, file bases.
- **Bulk file import**: `hadv-fileimport` loads files into the board's file bases from the
  command line. Depends on: Admin API, file bases.
- **User statistics**: per account: first on, last on, logons today and in total, posts today
  and in total, netmail and email sent and received today and in total, netmail and email sent
  to sysops in total, uploads and upload bytes in total, downloads and download bytes in total.
  A day for the "today" counters is a day in the board's time zone. Depends on: accounts and
  login, message bases, private messages, file bases, time zones and daylight saving.
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
  stored in a separate table linked to the user. Depends on: languages, time zones and
  daylight saving, theme packs, message bases, private messages, file transfer on classic
  connections.

## Mail networks

- **Mail networks**: the board supports several kinds of BBS network, and each kind's mail
  processor (tosser) is an external CLI program: `hadv-fido` for FTN (FidoNet Technology
  Networks), `hadv-vnet` for VirtualNET networks, `hadv-qwk` for QWK BBS networks, `hadv-ww4`
  for WWIVnet technology networks and `hadv-nntp` for Usenet. The CLIs only process message
  packets and take no incoming connections; every transport, incoming and outgoing (BinkP,
  BinkP over TLS, FTP and FTPS), lives in `hadv-service`. `hadv-nntp` is the one exception:
  an NNTP client that reaches out, pulls in the selected newsgroups, posts messages, then
  processes them. Whether the CLIs reach the board's data through the Admin API or through
  the database directly is decided in the brainstorm: CPU cost through a web server is the
  concern. Depends on: remote administration, message bases, private messages.
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
  file bases.
- **VirtualNET networks (`hadv-vnet`)**: first-class support for every feature: netmail
  inbound and outbound, posts and file areas. Multiple VirtualNET networks. Advanced Update of
  BBSLIST.* and AREALIST.* files. Network roles NC, RC, AC and SC. ADD and DROP SUB requests
  and SUB CREATE. Flow reports. ORIGIN.ID. Being a hub for other nodes, which log in by FTP or
  FTPS as `<nodenumber>@~<networkname>`. The developer will provide a full specification.
  Depends on: mail networks, file bases, FTP and FTPS server.
- **QWK BBS networks (`hadv-qwk`)**: several QWK networks, each with its settings and their
  defaults: enabled (disabled); support gating (no); network name, hub system ID, hub address
  (IP or FQDN), QWK username and QWK password (blank); archive format, from the list in
  `hadv-config` (ZIP); connection method, hidden for the future, FTP only (FTP); call-out days
  of the week, and call-out frequency in times per day (4); include kludge lines (no),
  VOTING.DAT (yes), HEADERS.DAT (yes), UTF-8 characters (yes) and MIME-encoded text (no);
  word-wrap exported messages (no); extended (QWKE) packets (no); export colour code format:
  remove, ANSI or SBBS (remove). Each QWK network keeps its own new-post pointer so no message
  is sent twice. Depends on: mail networks.
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
  transfer on classic connections.
- **WWIV networks (`hadv-ww4`)**: the WWIVnet packet specification. Address format
  `@node.netname`; multiple WWIVnet networks, each with its own node number. Sub hosting: the
  host and subscriber model, add and drop sub requests, a host designated per sub. BBSLIST,
  CONNECT and CALLOUT data maintained and distributed. Packet transport by BinkP
  through `hadv-service`, with per-link passwords. WWIV email routed inbound and outbound to local
  users. Heart codes translated on import and export (see attribute codes). Depends on: mail
  networks.
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

## Not yet described

Doors (through the HeliosDoors hosting protocol), attribute codes (colour and heart codes),
an FTP and FTPS server in `hadv-service`, node chat, and everything else the developer adds as it comes up.

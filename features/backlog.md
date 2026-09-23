# Backlog

Features mentioned and not yet brainstormed, in dependency order. A line here is a name, a
purpose and what it depends on, plus anything the developer has already said about it, kept in
their words so nothing is lost before its brainstorm. Nothing on this list is designed or
built until it has been through `feature-brainstorm` and has a brief of its own.

## Foundations

- **Service lifecycle**: `hadv-service` runs as a Windows service or a daemon; starts, stops,
  reloads, reports health. Depends on: servers, nodes and one board.
- **Configuration**: every board setting has a key, default and kind; `hadv-config` (TUI) and
  `hadv-config-gui` expose all of them with parity. Most settings are tunable there. Defaults
  are secure by default; loosening is the sysop's explicit choice. Depends on: servers.
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
  option negotiation; connection limits, per-source throttling, idle timeouts. Default port
  TCP/23, default binding all addresses, both changeable in `hadv-config`. Depends on:
  servers, scripting layer, theme packs. Touches the load tester.
- **Accounts and login**: sign-up, login, sessions across servers, lockouts; a second factor
  when the account's role requires it. A user may set themselves private and then does not
  appear in who's-online except to a role holding the permission to see private users; a
  user never sees someone they have blocked in who's-online (the who's-online contract takes
  the viewer as an input for this). Depends on: scripting layer, Telnet caller.
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

- **Admin API**: what the configuration, console, user-editor and strings tools use; nothing
  but the engine touches the database. Default ports TCP/8443 (HTTPS) and UDP/8443 (QUIC),
  default binding all addresses, changeable in `hadv-config`. Depends on: RBAC.
- **Public API**: the board's HTTP interface for clients, with its OpenAPI description.
  Depends on: web caller, accounts, RBAC. Touches the Portal and the load tester.
- **Waiting-for-Caller console**: `hadv-console` and `hadv-console-gui`: who is on which node
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
- **First-run setup**: `hadv-setup` (TUI only) takes a fresh install to a running board:
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

## Not yet described

Doors (through the HeliosDoors hosting protocol), mail networks (VirtualNET, FTN), node chat,
and everything else the developer adds as it comes up.

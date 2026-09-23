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
  encrypted in the store, keys managed. Depends on: servers.
- **Scripting layer**: all BBS logic runs in theme scripts through a public `bbs.*` API with a
  deprecation contract; the engine has no BBS logic of its own. Depends on: servers,
  configuration.
- **Theme packs**: scripts plus terminal text and graphics plus web code, in one pack;
  installed, selected, defaulted and disabled by the sysop. Two ship. The modern theme is the
  fallback for everything, cannot be deleted, is not supported if edited; a sysop can disable it
  from selection and make another theme the default. Depends on: scripting layer.
- **Certificates**: `hadv-cert` (TUI only) generates self-signed certificates and installs
  supplied ones; TLS Telnet, HTTPS and SSH host keys draw on it. ACME is not spoken by the
  engine; an ACME client uses `hadv-cert` to install what it obtained. Depends on:
  configuration.

## Callers

- **Telnet caller**: a caller connects over Telnet to a node and reaches the theme's welcome;
  option negotiation; connection limits, per-source throttling, idle timeouts. Depends on:
  servers, scripting layer, theme packs. Touches the load tester.
- **Accounts and login**: sign-up, login, sessions across servers, lockouts; a second factor
  when the account's role requires it. Depends on: scripting layer, Telnet caller.
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
  turn that off for the role. Depends on: accounts and login.
- **Second factor**: TOTP; passkeys where the surface allows; required per role; the initial
  #1 Sysop enrols during first-run setup. Depends on: accounts, RBAC. Touches the Portal.
- **Telnet over TLS caller**: the Telnet experience over a TLS-wrapped listener. Depends on:
  certificates, Telnet caller.
- **SSH caller**: the same over SSH, host keys from certificates, option negotiation.
  Depends on: certificates, Telnet caller. Touches the load tester and the SIP gateway.
- **SSH public-key login**: a user uploads a public key (on the web, or by file transfer on a
  classic connection) and logs in with it; a required second factor still applies. Depends
  on: SSH caller, accounts, second factor, file transfer.
- **Web caller**: a browser reaches the board over HTTP, HTTPS and HTTP/3 and gets the
  selected theme's web side. Depends on: scripting layer, theme packs, certificates.
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
  `hadv-strings` and `hadv-strings-gui` edit them. Depends on: configuration.

## Operating the board

- **Admin API**: what the configuration, console, user-editor and strings tools use; nothing
  but the engine touches the store. Depends on: RBAC.
- **Public API**: the board's HTTP interface for clients, with its OpenAPI description.
  Depends on: web caller, accounts, RBAC. Touches the Portal and the load tester.
- **Waiting-for-Caller console**: `hadv-console` and `hadv-console-gui`: who is on which node
  on which server, activity; spawns the user editor. Depends on: Admin API.
- **User editor**: `hadv-useredit` and `hadv-useredit-gui`, spawned from the console or run
  alone. Depends on: RBAC, Admin API.
- **Server join by pairing code**: a sysop adds a server to the board with a code shown on an
  existing server's console, through `hadv-setup`. Depends on: servers.
- **First-run setup**: `hadv-setup` (TUI only) takes a fresh install to a running board:
  sysop account with its second factor enrolled, listeners, store, certificates. Depends on:
  servers, certificates, RBAC, second factor.
- **Installation**: Inno Setup on Windows, WinGet wrapping it, RPM and DEB on Linux, a
  container image; the same result on every target. Depends on: service lifecycle.

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

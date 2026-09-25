# Backlog

Features mentioned and not yet brainstormed, in dependency order. A line here is a name, a
purpose and what it depends on, plus anything the developer has already said about it, kept in
their words so nothing is lost before its brainstorm. Nothing on this list is designed or
built until it has been through `feature-brainstorm` and has a brief of its own.

## Foundations

- **Service lifecycle**: `hadv-service` runs as a Windows service or a daemon; starts, stops,
  reloads, reports health. Liveness and readiness are separate: a server is ready when ADV-001's
  health report says it is healthy and its migrations are applied, and only then does it tell
  systemd or the Windows service manager that it is ready. Logs go to stdout by default; file
  logging with rotation is an explicit option, for the Windows service. Depends on: servers,
  nodes and one board.
- **IPv4 and IPv6**: every listener and every outbound connection works over IPv4 and IPv6.
  Every source count, ban, limit and allow list treats an IPv6 source by its prefix, not by a
  single address. Depends on: servers.
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
  no one can grant that permission to another role. Each server's database connection pool
  size is a setting, and the setting notes that every server's pool counts against the
  database's connection limit. Depends on: servers, remote
  administration, classic text-mode interface.
- **Sensitive data encrypted at rest**: user passwords stored as a hash (the previous system
  used Argon2id); a secret vault in the database that every server can read and decrypt,
  holding network passwords and other sensitive values each server needs (the previous system
  used a derived key-encryption key; ADV-001 already seals values under a board
  key-encryption key that join carries to each server); other sensitive fields encrypted in
  the database; keys managed. Depends on: servers.
- **Scripting layer**: all BBS logic runs in theme scripts through a public `bbs.*` API with a
  deprecation contract; the engine has no BBS logic of its own. Every script runs in a sandbox
  with ceilings on instructions, memory and wall-clock time. Depends on: servers,
  configuration.
- **Theme packs**: scripts plus terminal text and graphics plus web code, in one pack. A
  board installs several; each user picks the one they use, and a new user starts on the pack
  the sysop has flagged as the default; the sysop installs, flags and disables packs. Two ship.
  The modern theme is the fallback every other pack falls back to, cannot be deleted, is not
  supported if edited; a sysop can disable it from selection and flag another pack as the
  default. Packs carry metadata and versioning, and are installed and updated through
  `hadv-config` and `hadv-config-gui`. Where theme files live (database or disk, and how every
  server gets them) is decided here, not assumed. A pack's drawn assets (ANSI and ASCII
  screens, menus, art; not the language strings) may come in more than one character set, and
  the user gets the variant for their character set: the user's set first, then the pack's
  default set, then the default theme. A pack's metadata names the minimum engine version it
  needs, and installing refuses a pack that needs a newer engine. Installing checks the pack,
  reporting missing assets and listing what falls back to the default theme. The Sysop can use
  a pack before it is offered to users, to preview it. A pack does not assume 80x25: 132
  columns and tall terminals are part of the theme contract. When an update replaces a shipped
  theme, a file the sysop edited is found by comparing it with the shipped file's hash, and the
  sysop's copy is set aside and the sysop told. On legacy connections `/` starts a long command
  (such as `/SYSOP`) in every theme, and no theme binds `/` as a hotkey; with hotkeys on, typing
  `/` switches to line entry until Enter. The sysop guide says editing a shipped theme is not
  supported and shows how to fork one instead. Depends on: scripting layer.
- **Add-on modules**: sysop-installed Lua modules that add something to the board, such as a
  trivia game, a weather screen or a local-news menu, and work under any theme, so a sysop does
  not fork a theme for one addition. A module carries metadata and a minimum engine version, is
  installed, updated and checked through `hadv-config` and `hadv-config-gui` as theme packs
  are, runs in the same sandbox with the same ceilings, and reaches the board only through
  `bbs.*`; using one is a permission per module. Depends on: scripting layer, theme packs.
- **Certificates**: `hadv-cert` (TUI only) generates self-signed certificates and installs
  supplied ones; TLS Telnet, HTTPS and SSH host keys draw on it. ACME is not spoken by the
  engine; an ACME client uses `hadv-cert` to install what it obtained. Certificates reload
  without a restart, so an ACME client can update them while the board runs. Every networked
  service that offers encryption does it over TLS 1.2 or TLS 1.3; the default key exchange
  uses perfect forward secrecy. SAN (Subject Alternative Name) and wildcard certificates are
  supported for all TLS services. High key sizes are supported and compromised key sizes
  rejected. The sysop configures TLS 1.2, TLS 1.3 and the key exchange in `hadv-config` and
  `hadv-config-gui`; they default to secure settings. The sysop guide shows how to set up an
  ACME client (certbot or lego on Linux, win-acme on Windows) with a renewal hook that calls
  `hadv-cert`. Depends on: configuration.
- **Time zones and daylight saving**: times shown to callers and sysops follow daylight saving
  time where appropriate. Depends on: configuration.
- **Cross-server task ownership**: the board is aware, across servers, of which server owns a
  task, so two servers never do the same work at once: two servers never dial out for a network
  call on the same packet, and an event such as Daily Maintenance runs on one server only. The
  same holds for anything else where servers could race. The developer's thinking: a NOTIFY
  between servers as well as a record lock in the database. Depends on: servers, nodes and one
  board.
- **Event scheduler**: an event scheduler, like cron, that runs built-in actions and external
  programs and scripts on a schedule. Each event is pinned to any server (one server picks
  itself to run it and locks the others out; done when that server has run it), all servers
  (done when every server has run it) or a specific server; default all servers. An event has a
  maximum runtime, after which it is killed; runs a missed event, default yes; retries on
  failure, off or N retries with backoff, default off; and has an overlap policy for when the
  previous run is still going, skip, queue or kill the previous, default skip. Events can be
  disabled without being deleted and run now from the console. Run history (last run, duration,
  exit code, the server that ran it) is kept for N days. An event that runs an external program
  is created only in `hadv-config`, and audited. A midnight repeated by a daylight-saving change
  never runs an event twice. Daily Maintenance is event 1: it cannot be deleted or edited, runs
  at midnight local time once a day on any server, runs if missed, and resets the user and BBS
  statistics and does anything else that must be done daily. Jobs other entries already hand it:
  the daily statistics rollover, deleting accounts past their role's Maximum Days of User
  Inactivity, permanently deleting accounts whose time in the virtual deleted state is up, the
  re-scan sweep of quarantined uploads, message base packing and renumbering, and mail polling.
  Depends on: servers, nodes and one board; time zones and daylight saving; cross-server task
  ownership.
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
  drawn for. When auto-detection fails, the board asks, assumes ANSI or assumes ASCII, as the
  sysop sets; default ask. Depends on: nothing.
- **Telnet caller**: a caller connects over Telnet to a node and reaches the theme's welcome;
  option negotiation; connection limits, per-source throttling (one mechanism shared by every
  caller surface, honouring the exempt-source list from accounts and login), idle timeouts.
  Options negotiated: ECHO, SGA, BINARY, TTYPE, NAWS, NEW-ENVIRON and TSPEED; LINEMODE is
  refused, because hotkeys and lightbars need a character at a time. NEW-ENVIRON may fill in the
  login prompt but is never trusted to sign anyone in. Binary mode runs in both directions, so
  8-bit CP437 arrives intact. A keepalive, every 60 seconds by default, finds a caller whose
  connection has dropped. Each listener can have a pre-login banner, drawn by the theme. Off by
  default. Default port TCP/23, default binding all addresses; whether it is on, the port and
  the binding all changeable in `hadv-config`. Depends on: servers, scripting layer, theme
  packs, languages, terminal negotiation. Touches the load tester.
- **Accounts and login**: sign-up, login, sessions across servers, lockouts; a second factor
  when the account's role requires it. A user's profile is private by default, and they may make
  it public: a private user is hidden from search, profile views, who's-online, activity lists
  and anything else where a regular user could see them or their activity, except from a role
  holding the permission to see private users; viewing a private profile shows only "This
  profile is private". A post or upload to a public area is the user's own affirmative act and
  shows as usual. A user never sees someone they have blocked in who's-online, unless they hold
  the permission to see everyone (the who's-online contract takes the viewer as an input for
  this). Lockout is board-wide policy with one implementation that every surface's sign-in uses
  (Telnet, SSH, web, the Admin API), counted in the database so moving between servers or
  surfaces resets nothing. Account #1, always the main sysop account, is never locked; any other
  account locks after 5 failed attempts for 15 minutes by default, both configurable in
  `hadv-config`. While an account is locked, sign-in asks for the password and the second factor
  together and answers only success or failure, never which was wrong: an owner with a second
  factor gets in with both right, an account without one stays locked, and every locked account
  shows the same prompt; a few attempts per lock are allowed, and counted. An account holding
  the Sysop or Co-Sysop role that is locked out a few times within a window is locked
  permanently until a sysop unlocks it (a Sysop account only by a Sysop). Failed sign-ins also
  slow the source down on every surface and every account: each failure from an address makes
  that address's next attempt wait longer, and past a threshold the address is refused for a
  while; the server's own host is slowed but never refused. A list of exempt sources, separate
  from the trusted proxy list, covers addresses that stand for many callers (the HeliosSIP
  gateway, a load tester, a shared address). Every tunable here has a floor and a ceiling;
  loosening any of them, or adding an exempt source, warns loudly and needs the sysop's
  confirmation. The next successful sign-in shows how many failures there were and from where,
  and when and from where the last successful sign-in came. Password policy: a minimum length,
  optional character classes, a maximum age and a reuse history, defaulting to 12 characters, no
  expiry and the last 5 remembered; a password may be at least 64 characters long, with spaces
  and any Unicode. After a sysop resets a password, the user must change it at the next login
  (default yes); nobody but account #1 itself can reset account #1's password. Concurrent
  logins: allow, deny, or deny on the same front end; default deny on the same front end,
  offering to end the old session. Changing a password ends every other session. The idle
  timeout is separate from the session time limit and set per front end, default 15 minutes. A
  setting, default yes, allows the Sysop to log in from outside sources rather than only from
  the WFC. Depends on: scripting layer, Telnet caller.
- **Breached-password check**: a new or changed password is checked against Have I Been
  Pwned's Pwned Passwords, sending only the first five characters of its SHA-1 hash and nothing
  else, so the service never sees the password. On by default; the sysop chooses warn or
  block, default warn. Responses are cached by hash prefix for a limited time, never a password
  or a full hash, and never linked to a user. When the service cannot be reached, the check is
  skipped and logged, and the password is allowed. Depends on: accounts and login.
- **Address bans**: the sysop bans an IP address or a range, with an optional expiry; a ban
  applies before sign-in on every surface. A range wider than IPv4 /29 or IPv6 /48 gets the
  same loud warning and confirmation as the Admin API's allow list. The server's own host
  cannot be banned, and banning an exempt source warns loudly. A banned caller sees a "you are
  banned" screen by default, or the connection closes silently, as the sysop chooses; the
  shipped themes draw it as an animated ANSI ban hammer. No country blocking. Depends on:
  accounts and login, IPv4 and IPv6, theme packs.
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
  Spaces are revisited if a compatibility issue turns up. A handle may not be purely numeric,
  since commands accept a user number or a name. User numbers have no cap; a permanently
  deleted number is never reused, and a legacy format that cannot carry a large number deals
  with it at its own boundary. When an upgrade changes the confusables data, every stored
  skeleton is recomputed automatically and the sysop is told of any collisions between
  existing accounts. Depends on: accounts and login.
- **Username change**: a user can change their own username; how often is a sysop-configurable
  setting. The old username becomes a former handle. The Sysop and Co-Sysop see every handle
  an account has had; moderators see "formerly known as" for a configurable period after a
  change, and regular users never do. The history is deleted with the account. The sysop guide
  notes that posts already sent to networks keep the old name. Depends on: reserved and former
  usernames.
- **Language choice**: a user picks from the available languages when creating their account
  and can change it in their preferences. Depends on: languages, accounts and login.
- **Role-based access control**: roles carry permissions and configuration (upload/download
  ratio, whether 2FA is required, and the like). Every gate fails closed; every operator action
  is audited. The direction for the brainstorm, not yet a decision: every user has one primary
  role, which carries the settings (ratio, time limits, the second-factor requirement,
  inactivity days, the New User sandbox) and which promotion moves; grant roles only add
  permissions, such as moderating certain message and file areas, carry no settings, and are
  untouched by promotion. Sysop and Co-Sysop are primary roles only; a grant never carries a
  permission a brief fixes to the Sysop role or to account #1; a restriction from the primary
  role or an area still applies to what a grant adds. It is rederived in the brainstorm, not
  taken from the previous project's notes. The developer's thinking on its shape, not settled:
  RBAC owns every permission check, and each subsystem registers its own permissions, with their
  defaults, next to its own code, so a new subsystem never touches RBAC; permissions are
  registered once when a server starts (a duplicate name stops the start, and an unregistered
  permission is denied), named by constants, and all listed in the sysop's permission editor; an
  add-on module registers its permissions at install, under the module's own prefix. Default
  holders are seed values: set at first-run setup and never imposed again. For an upgrade that
  brings a new permission, proposed for the brainstorm: an upgrade only adds grants for
  permissions that did not exist before and never changes a grant the sysop made; a new
  permission that refines an existing one goes to whoever holds that one; any other new
  permission goes to the seeded roles by their fixed IDs, and an administrative one to Sysop
  only, never to roles the sysop made; after the upgrade the sysop is shown the new permissions
  and who got them. The direction for the brainstorm: only account #1 itself, or the local
  operator at the server's own host, can change account #1's password, second factor, email
  address, SSH keys or role; removing a key or ending a session, which can only lock #1 out, is
  not barred. Seeded roles, by fixed ID because names are editable: 1 Sysop, 2 Co-Sysop, 3 User,
  4 Guest, 5 New User. Sysop: super user, unrestricted global access; cannot be deleted; display
  name changeable, access not editable. Co-Sysop: limited administration (users, file areas,
  message bases); cannot touch system configuration, promote anyone to Sysop or Co-Sysop, take
  over Sysop or Co-Sysop accounts, or lock out a Sysop; cannot be deleted; editable (display
  name, additional restrictions). User: regular registered users; cannot be deleted; editable.
  Guest: not signed in; cannot be deleted; editable. New User: baseline probationary access; can
  be deleted; fully editable. Account #1 is always the main sysop account and owner of the
  system. The Sysop and Co-Sysop roles require 2FA by default; each role's second factor is
  Required, Optional or Disabled. Every permission can be granted to other roles, except those a
  brief fixes to the Sysop role or to account #1. A role in use cannot be deleted; the refusal
  names what uses it. Guest, on the web, reads public areas and cannot post, upload or run
  doors; Guest downloads only where the sysop turns that on for an area, off by default; Guest
  over Telnet, SSH and FTP may come later. Sysop and Co-Sysop hold the permission to see
  everyone in who's-online, private or blocked, by default. Depends on: accounts and login.
- **Rate limits**: posting, private mail, uploads, search and registration are each limited
  per account and per IP address, by one mechanism on every front end, with a clear "try again
  in N seconds". The defaults are generous and roles can override them; Sysop and Co-Sysop get
  high limits, not none. An IPv6 source counts by its prefix; exempt sources skip the per-IP
  limit while their callers' per-account limits still apply. An area's slow mode stays the
  moderators' own tool. Depends on: accounts and login, RBAC, IPv4 and IPv6.
- **Bot and service accounts**: a flag for accounts that post automatically. A bot is left out
  of who's online, leaderboards and statistics, cannot log in interactively (its credential is
  an API token), is labelled visibly to users, such as "[bot]", and cannot hold the Sysop or
  Co-Sysop role. Depends on: accounts and login, RBAC.
- **Time limits and time bank**: each role can have a daily time limit, a per-call limit, a
  maximum number of calls per day and a time-remaining warning, all off by default; whether
  they apply to web sessions is decided in the brainstorm. A time bank, built into the board
  rather than a door, lets a user deposit and withdraw daily time, with caps per role; using it
  is a permission every role holds by default except New User and Guest. Depends on: RBAC.
- **Who's online**: a list of who is currently online on the BBS; see classic BBSes for
  examples. A user whose profile is private does not show up in who's online, and a user does
  not see someone they have blocked. Sysop and Co-Sysop hold a permission to see everyone,
  bypassing a private profile or a block. Each caller shows a status line they set and their
  idle time, per front end; users see coarse activity (the front end, in a door, reading
  messages), while the sysop's console keeps the full detail, and do not disturb shows here. The
  status line is user content: length-limited, checked against watched words and reportable.
  Depends on: role-based access control; its status-line reporting on content moderation.
- **Account deletion**: a user can delete their own account after a confirmation (typing
  something, or their second factor); account #1, the main sysop account, cannot delete itself.
  Deleting an account, whether the user, the Sysop or maintenance does it, puts it in a virtual
  deleted state, like a recycle bin, for a period configurable in `hadv-config` and
  `hadv-config-gui` up to a ceiling of 30 days, before it is deleted permanently. Maintenance
  deletes an account that has been inactive for longer than its role's Maximum Days of User
  Inactivity, a setting every role carries and the sysop can change on it: the Sysop role
  defaults to unlimited, Co-Sysop to 365 days, User to 180, New User to 30, and a new role to
  180. Account #1, the main sysop account, is never deleted for inactivity. While in the virtual
  deleted state the account is hidden, blocked from login and absent from the user list; its
  username and email address cannot be reused by a new user; the Sysop or a Co-Sysop can restore
  it. When the account is deleted permanently, any messages in its mailbox are deleted and
  cannot be restored, and its username and email address may be reused, subject to the
  former-handle period. The Sysop can delete an account permanently straight from the virtual
  deleted state, to comply with the EU GDPR; its posts, uploads and other data then show the
  placeholder [Deleted User]. Research whether and how the GDPR applies to the audit log and
  other logs. An email warns the user N days before their role's inactivity limit, default 14,
  when the board can send email and the account has an address; it is plain, with no link asking
  for a password, just "log in to keep your account". The sysop turns the warning on or off in
  the configuration tools, default on. Depends on: accounts and login, RBAC, event scheduler;
  its inactivity email on the SMTP client.
- **Second factor**: TOTP (RFC 6238), with self-service enrolment in text mode and by QR code
  on connections that support it; passkeys where the surface allows; required per role; the
  initial #1 Sysop enrols during first-run setup. Ten single-use recovery codes, stored hashed,
  are shown once at enrolment and can be regenerated. Depends on: accounts, RBAC. Touches the
  Portal.
- **Account recovery**: a user who has forgotten their password, or lost their second factor,
  gets their account back. The Sysop, or a Co-Sysop within their scope, can clear a user's
  second factor; if the role requires one, the user enrols again at the next login. Clearing it
  is audited and the user is told by inbox and email; a Co-Sysop cannot clear a Sysop's or a
  Co-Sysop's, and nobody but account #1 itself can clear account #1's. The sysop guide says to
  verify who is asking first. Depends on: accounts and login, second factor.
- **App passwords**: protocols that cannot do a second factor (FTP and FTPS, and later
  newsreader and mail-client access) refuse the main password of an account with a second
  factor and take an app password instead: named, limited to the protocols it is for, shown
  once, stored hashed and revocable on its own. Any account may use them; an account with a
  second factor must. The FTP virtual accounts for network nodes are separate. Depends on:
  accounts and login, second factor.
- **User profile and new-user questions**: the board stores, per account: deleted status, user
  number, handle, real name, company name, BBS name, email address, gender (a single gender
  code), birth date, address, location, zip code and phone number. Each question a new user is
  asked has a setting in `hadv-config` and `hadv-config-gui` of No, Optional or Required: real
  name (default Required; the sysop chooses, because a board that joins FidoNet must use real
  names; force a multi-word name, default Yes); company name (default No); email address
  (default Required); gender (No or Optional only, default No; the user picks one code from the
  gender codes the sysop sets in `hadv-config` and `hadv-config-gui`: a string, one letter per
  gender, default `MFX`, to which the sysop can add codes or delete them); birth date (default
  No); address and zip code (default No; US and international); location, such as city, state
  and country (default Optional; optionally require a comma, default No); phone number (default
  No; US and international). A feature that needs a field the user has not given (real name,
  email address, gender, age) cannot be used by that user. The email address is internet email
  only, used for recovery, alerts and confirmations. A Sysop note, which the Sysop and
  Co-Sysops read and edit, is personal data: it is part of a subject-access export and is
  deleted with the account. Depends on: accounts and login.
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
  the ports, the binding and the redirect all changeable in `hadv-config`. HSTS is sent by
  default only when the certificate is publicly trusted, with a modest duration, and never for
  subdomains or preload unless the sysop asks. The shipped themes can be read without
  JavaScript. Every message, file and profile has a stable permalink that survives moving an
  area, with Open Graph metadata for link previews only on content a Guest can see; a link the
  viewer cannot read gets the same not-found answer as one that does not exist. Depends on:
  scripting layer, theme packs, certificates; its permalinks on message bases and file bases.
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
- **RIP graphics**: RIPscrip 1.54 for clients that can draw it, as SyncTERM now does. The board
  detects RIP with the rest of terminal negotiation; themes may supply RIP screens as another
  variant of an asset, falling back to ANSI and then plain text; RIP buttons send hotkeys, like
  mouse click regions. Web callers get the ANSI version, or the RIP screen drawn in the
  browser. Depends on: terminal negotiation, terminal capabilities, theme packs.
- **Modern theme**: rich HTML on the web and a lightbar ANSI system on the terminal; shipped;
  the fallback. Its web side takes advantage of modern web design and has a modern social-media
  feel, while still reaching everything the board offers. Depends on: theme packs, Telnet
  caller, web caller.
- **Classic theme**: strictly text-based; shipped; the web server renders it by conversion.
  The sysop can delete it, and reinstall it from the release. Depends on: theme packs, Telnet
  caller, terminal-in-browser rendering.
- **Proxies in front of the board**: PROXY protocol v1 and v2, `X-Forwarded-For`,
  `X-Real-IP`, `Forwarded`; honoured only from a trusted proxy list so the caller's address
  cannot be forged. Depends on: Telnet, SSH and web callers.
- **Gateway session details**: a registered gateway, HeliosSIP, passes the caller ID and the
  connect speed into the session record, trusted only from registered gateways, as the PROXY
  protocol is only from trusted proxies. The connect speed shows in the classic style and is
  used in drop files and baud-rate emulation. A caller ID is sensitive: the Sysop sees it,
  users never do, and it is kept only as long as the connection log; banning a number works
  as an address ban does. How the two travel is the design of a contract between the
  repositories, kept in the contracts register. Depends on: SSH caller, proxies in front of the
  board, address bans. Touches the SIP gateway.
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
  doors built with the Door Kit are also drawn as HTML for web callers. Each door can have a
  nightly maintenance hook, run by the event scheduler. Per door: a daily and a per-call time
  limit, off by default; whether door time comes from a separate pool, default no; who can run
  it, and whether it is listed for users who cannot, default hidden; a cost in time-bank
  minutes, default 0. Doors sit in categories and menus with a sort order and per-category
  access. Usage is counted per user and per door: launches, total time, last played. High
  scores the theme can show, and a wait queue for a full door (the user is told how many are
  in it, the place is held only while they stay connected, a freed slot wakes the next waiter
  rather than admitting them, any key abandons the wait), need the door hosting protocol to
  carry them. Depends on: terminal capabilities, account deletion, languages, sensitive data
  encrypted at rest, event scheduler, time limits and time bank; blocked on the door hosting
  protocol (HeliosDoors).

## Operating the board

- **Public API**: the board's HTTP interface for clients, with its OpenAPI description, separate
  from the Admin API. Without a token a client has exactly the Guest role's permissions; with a
  user's API token it has that user's permissions narrowed by the token's scopes, never more
  than its owner. Every answer is filtered by the viewer as the terminal is (private profiles,
  blocks). A token is scoped, expires, is shown once, stored hashed, revocable on its own and
  listed with the user's sessions; creating one with write scopes needs a step-up. It serves
  HeliosPortal and bot accounts. Depends on: web caller, accounts, RBAC; its tokens on sessions
  and devices and step-up re-authentication. Touches the Portal and the load tester.
- **About this BBS**: an about screen (name, location, sysop, version, server and node count,
  contact), drawn by the theme from facts it reads through `bbs.*`, and the same facts exported
  as JSON for BBS directories and the public API. Required: the AGPL section 13 offer of the
  board's source, reachable from the about screen on every front end, and a licence-compliance
  page listing every dependency and its licence, generated at build time and served next to
  the source offer. Uptime and last restart are for the sysop, in the WFC, not for users.
  Depends on: scripting layer, public API.
- **Waiting-for-Caller console**: `hadv-console` (TUI only; no CLI unless a use case appears)
  and `hadv-console-gui`, run on the server or remotely; long-lived tokens; the GUI minimises
  to the taskbar and can start minimised so it starts after login. It shows who is on which
  node on which server, and their activity; it spawns the user editor. The Sysop, and no other
  role, can spy on a connected user, seeing their output only and never their keystrokes; every
  spy is audited, the terms of service tell users it can happen, and it may not work inside an
  external program. A live log viewer filters by severity, server and correlation ID. A last
  callers screen shows connection type, location and a new-user marker, and a connection log
  shows source IP, front end and result. The main screen has indicators for the moderation
  queue, pending users and unread feedback. Quick actions on a node: chat, spy, force logoff,
  lock the node, send a message. Depends on: remote administration, classic text-mode
  interface.
- **Sysop messages and draining**: node-to-node messages and messages from the sysop to a user
  arrive in the live session; a broadcast reaches every online user on every server, with an
  optional shutdown countdown; a forced logoff of a user or a node shows the user the reason.
  One mechanism, draining: draining a server stops new logins there while sessions finish or
  the countdown ends; maintenance mode drains every server, shows the sysop's banner on every
  front end and still lets the Sysop in; an update and a restart drain a server first. The
  console can restart a server for a setting that only takes effect at start-up, with an
  optional announced delay and a readiness check afterwards. A scheduled downtime notice shows
  at login and in the web banner during a window the sysop sets. Do not disturb never blocks a
  broadcast or a message from the sysop. Draining is not turning a service off, which closes
  its listener; the console shows which applies. The theme draws live messages. Depends on:
  Waiting-for-Caller console.
- **Taskview**: in the WFC, see running tasks, with progress if the task supports it, and
  cancel a task if the task supports it, much as Nutanix Prism Central does. It is open to
  every part of the BBS, not only the event scheduler: a background virus scan, mail tossing
  and any other background task show up in it too. Depends on: Waiting-for-Caller console.
- **Turning services on and off**: each service (Telnet, SSH, the web, FTP and the rest) has an
  on or off setting per server, which is its state when the server starts. `hadv-config` and
  the WFC consoles change that same setting; there is no temporary state in the console and no
  board-wide setting. "All servers" is a bulk action in both, not a stored setting. From the
  console, turning a service off needs no extra sign-in and turning it on needs step-up (the
  Sysop's password and second factor); both are audited. Turning the web off never affects the
  Admin API. The sysop guide says to point DNS or a load balancer for a service only at the
  servers that run it. Depends on: configuration, Waiting-for-Caller console; blocked on an
  amendment to ADV-002, whose console tokens change no settings.
- **User editor**: `hadv-useredit` and `hadv-useredit-gui`, spawned from the console or run
  alone. `hadv-useredit` also has a CLI (suspend, unlock, reset, change role) for scripting and
  recovery, signing in and taking secrets as the `hadv-config` CLI does. Depends on: RBAC,
  remote administration.
- **Allow-list self-lockout guard**: a change to the Admin API's allow list that would shut out
  the connection making it is refused outright, with no override; the refusal says to make the
  change from another admitted address or from the server's own host. Depends on: remote
  administration.
- **Permission preview**: the sysop sees the board as a role, or as a user, sees it, read-only:
  which conferences, areas, files and commands are open to them, and why one is not. It shows
  what they can see and never acts as them. Depends on: role-based access control,
  configuration.
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
  sysop account with its second factor enrolled, listeners, database, certificates. The sysop
  guide says the sysop needs an authenticator app before starting. Depends on: servers,
  certificates, RBAC, second factor.
- **Installation**: Inno Setup (`setup.exe`) on Windows, WinGet wrapping it, RPM and DEB on
  Linux, a container image built from a Dockerfile; the same result on every target. Where an
  install sets up PostgreSQL, it is secured: SCRAM-SHA-256 passwords only, never `trust`; TLS
  on; listening locally unless the board has more than one server; the per-server logins
  ADV-001 requires. The container's compose file brings PostgreSQL up configured that way; RPM
  and DEB recommend the distribution's package, configured by setup on first run; Windows does
  not bundle it, and the guide points to PostgreSQL's own installer, whose result `hadv-setup`
  checks. The sysop guide covers securing an existing PostgreSQL and lists every default port
  for firewall rules. Depends on: service lifecycle.
- **Database upgrades**: the database is backed up before every migration, by default; the
  sysop may skip the backup, with a loud warning. Restoring that backup to test it is
  configurable. After an install or an upgrade the schema is checked against what the
  migrations should have produced. Depends on: servers, nodes and one board.
- **Auto-update**: a server updates itself from the published releases, verifying the
  release's signature and build-provenance attestation against the project's publishing
  identity before anything is applied (supply-chain protection built on the git and release
  infrastructure), rolling across a multi-server board one server at a time within the
  one-version skew rule. The sysop picks off, notify only, download and notify, or download
  and install; default notify only, and choosing off warns. RPM, DEB and Docker installs only
  ever notify, since the package manager or Docker does the update; Inno Setup and WinGet
  installs use the built-in updater. A release can be flagged critical, for a louder notice.
  Stable and beta channels, beta opt-in and signed like every release. Across mixed update
  methods, servers that update themselves go one at a time (drain, update, readiness check,
  next), while package-managed servers are reported rather than driven: the console offers to
  drain them and tracks each until it returns on the new version. One console view shows every
  server's version. Migrations run once, on the first server to reach the new version. The
  sysop guide warns against skipping a minor version. Depends on: installation, servers, nodes
  and one board, database upgrades, sysop messages and draining.
- **Configuration export and import**: the board's configuration (settings, areas, roles,
  networks; never secrets) exports as one file that diffs cleanly. An import lands as pending
  changes in the configuration tools, so the dry run is the pending list and applying it is the
  normal apply, with the same checks and loud warnings as a change typed by hand; Sysop only.
  An import lists the secrets to enter again. For now, an import goes to the same board or a
  fresh one. Depends on: configuration.
- **Security checkup**: a screen in `hadv-config` and `hadv-config-gui` listing every setting
  loosened from its secure default (a role without a required second factor, plain FTP on, a
  wide ban range, HSTS off, a listener without TLS and the like), each with who changed it and
  when, so a sysop sees the whole picture long after each loosening's warning. It changes
  nothing itself. Depends on: configuration.
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
- **Metrics**: Prometheus-format metrics on the Admin API listener, only through its allow list
  and a token (an automation token with a read-only metrics scope), never public: sessions per
  front end, login failures, posts, uploads, database pool saturation, tosser queue depth, door
  launches and scheduler durations. Developer mode uses the same counters. Nothing is labelled
  by user or IP address, only by front end, server and area. A Grafana dashboard ships in the
  repository and is kept up to date with the metrics. Depends on: remote administration,
  developer mode.
- **fail2ban support**: failed-login and throttle log lines have a fixed, documented shape, a
  stable contract changed only with a release note; fail2ban filter files ship in the docs, and
  a test runs the shipped filter against real log output so the two cannot drift apart. The
  same lines serve CrowdSec and Windows tools such as IPBan. Depends on: accounts and login.
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
  Since access is already the conference and the area together, configuration keeps settings
  honest: it refuses an area setting wider than its conference and says why (the conference
  requires 18, so the area cannot go lower); a scan finds settings that can never take effect,
  such as a role let into an area but not its conference, and offers to fix them, never
  silently widening the conference; moving an area shows the settings now wider than its new
  conference and offers the same fixes. Depends on: RBAC, user profile and new-user
  questions, first-run setup.
- **Message bases**: public message areas under conferences. If the network type supports it,
  adding a Sub or Echo asks whether to send a Sub request automatically; deleting one asks
  whether to send a Drop request; and if the network supports it and the sysop chooses to
  advertise, the sysop is asked whether to send an update of the Sub or Echo list. Restrictions:
  the roles that can read (default Sysop, Co-Sysop, User, New User, Guest), post (default Sysop,
  Co-Sysop, User, New User) and moderate (default Sysop, Co-Sysop); required minimum and maximum
  age, genders and terminal type, as for conferences. Settings, with defaults: maximum messages
  (5000); purge by age (off, or days; off); duplicate checking by a hash searched in the area
  (off, or the number allowed; off); anonymous posts: no, anonymous or pseudonymous (no), where
  pseudonymous gives each user a stable alias per area, not linkable across areas nor derivable
  by users, both being hidden from users but not from staff, and pseudonymous cannot be combined
  with requiring real names; require real names (no); require an internet email address (no);
  allow message quoting (yes); allow word wrap (yes); required reading (no); allow message edit
  (off, within N minutes, or always; within 15 minutes; networked areas force off), edited
  messages keeping their prior bodies, readers seeing an "edited" marker and moderators the
  diff; slow mode, one post per user per N minutes (off); auto-close inactive threads (off, or
  days; off); pinned messages with an optional expiry date, set by the area's moderators;
  watched words with an action of block, send to the moderation queue, or tag silently (none
  seeded); required approval (no). Moderator thread tools: split, merge, move (leaving a stub),
  close. Maximum message size in bytes or lines (64 KB; networked areas clamp to the network's
  limit). Attachment policy: off, allowed, or allowed with approval, with a maximum attachment
  size and count. An origin line or network tagline per area, with a board-wide default. A
  read-only, archived state: no new posts, existing ones readable (off). Message base packing
  and renumbering as a maintenance job, safe against in-flight readers, and beside it an
  integrity check that rebuilds an area's pointers and indexes, equally safe, reporting its
  progress in Taskview. Area aliases or short names usable in menu commands and the `area:`
  search filter. Default new-scan participation: force on, default on, or default off (default
  on). Area sort order and numbering independent of creation order, shared with the web front
  end. Per-area header display: real name or handle, location, and whether the network address
  is shown. An "Attachment Storage Backend" setting per area, letting its attachments live on a
  different storage-registry entry from the area's own files. Initial areas, created only during
  initial setup and freely editable or deletable afterwards: Announcement (read by Sysop,
  Co-Sysop, User, New User, Guest; required reading, yes) and General Discussion (read by Sysop,
  Co-Sysop, User, New User, Guest; post by Sysop, Co-Sysop, User, New User; moderate by Sysop,
  Co-Sysop). Depends on: conferences, account deletion, event scheduler.
- **Reactions**: users react to posts, files and other content. Likes show as counts, while
  dislikes are a private signal for ranking and moderation, never shown as a count. On the
  terminal, reactions show as counts in the message header, with a hotkey to react. The
  reaction set is configurable per theme. A banned or suspended user's reactions stop counting
  while the restriction lasts and count again when it is lifted. Depends on: message bases.
- **File bases**: file areas under conferences. Each area names the roles that can view it,
  download, upload and moderate, and whether uploads need approval, as message areas name
  theirs; defaults: view and download Sysop, Co-Sysop, User and New User, upload Sysop,
  Co-Sysop, User and New User, moderate Sysop and Co-Sysop, approval no. Storage is a separate
  entry, since more than file areas need it. Local directory and file paths are supported; the
  architecture must handle availability across servers: a file local to one server may need to
  be transferred temporarily to another, or marked OFFLINE when its owning server is
  unavailable. An OFFLINE file stays listed and requestable (default: listed). Metadata is read
  from files that support it (audio, images) when uploaded outside an archive; EXIF and other
  embedded metadata are stripped from images on upload after being harvested into the file
  record (default: strip). A free-file, no-ratio flag per file and per area. A new-files scan
  since the last call, honouring the same follow graph as the new-message scan. File comments
  and ratings by users who downloaded the file, using reactions. Resumable, chunked HTTP uploads
  on the web front end. Maximum upload size per file and per area (off, or bytes; off). Upload
  description requirements: minimum length, extended multi-line (default one line, at least 10
  characters). An upload credit model: bytes, files or ratio-exempt, with per-role and per-area
  overrides (default 3:1 by bytes). Download counters per file, with most-downloaded and
  newest-files listings. Listing options: sort by name, date, size or downloads; pattern filter;
  paged or full list. A tagged-file batch queue: tag while browsing, download the batch at the
  session's end. Aborted-upload handling, with resume on the next call for legacy protocols.
  Uploader attribution in listings, and a "my uploads" view per user. A per-area file naming
  policy: long names or 8.3, case handling, illegal-character rewriting. Ad-file injection:
  sysop-configured advertisement text stamped as an extra file into outgoing archives, with its
  own enable, text and filename settings; default off, and never into an archive that carries a
  signature. FILE_ID.DIZ and DESCRIPT.ION are read into the description, as untrusted text: only
  the board's allowed attribute codes are kept, every other escape sequence is stripped, the
  text is size-bounded, and the archive is opened under the same limits as virus scanning. A ban
  list of filename patterns. Per area, a maximum number of files and a purge by age, both off by
  default, because a purge deletes uploads the sysop curated. Per role, a daily download byte
  limit and a largest downloadable file. A file area can be a text library (G-files): its files
  cost no ratio, open inline with the same stripping, and show the SAUCE title and author in the
  listing. Seeded areas: Sysop, always ID 1, editable but never deleted, viewed and downloaded
  by Sysop and Co-Sysop, open to uploads from every user without approval, receiving uploads
  meant for the sysop and every upload when "all uploads to Sysop" is on (default off); and
  Games and Miscellaneous, whose uploads need approval and where Guest downloads are off by
  default. Depends on: conferences, account deletion, storage, reactions.
- **Private messages**: user-to-user mail on the board. Folders Inbox, Sent and Trash by
  default, with Saved and folders of the user's own optional. CC and BCC. Mail to a role or
  group is a permission, held by Sysop and Co-Sysop by default; mail to the Sysop role
  (feedback) stays open to everyone. A return receipt, off by default, which a recipient can
  choose never to send. Forward with attribution, and reply-all. Read mail can expire, off by
  default; a message can be marked unread or kept permanently. A vacation auto-reply, off by
  default, limited per sender and following RFC 3834, so it never answers a list, bulk mail or
  another auto-reply. One quota for the store private mail shares with email, per user and per
  role, on by default and generous, with a warning; a full mailbox refuses new mail with a
  clear reason and deletes nothing. Depends on: accounts, RBAC, account deletion.
- **Drafts and read state**: a draft is kept on the server, saved on a timer and when the
  connection drops, and resumed from any front end; on by default; one per user per area and
  one per private-mail conversation; drafts are personal data, exported and deleted with the
  account. Read state is per user and kept on the server, shared by Telnet, SSH and the web,
  so no front end keeps its own pointer. Each message has a "new since last visit" marker as
  well as the area pointer, for threaded and out-of-order reading; kept naively that is a row
  per user per message, so how it is stored is decided with that cost in mind. Depends on:
  message bases, private messages.
- **Scheduled posts**: a post publishes itself at a set time, a draft plus a one-off event in
  the event scheduler. Permissions are checked again when it publishes: if its author may no
  longer post there, or the area is gone, it does not publish and the author is told.
  Scheduling a post is a permission, held by Sysop and Co-Sysop by default and grantable to
  area moderators for their own areas. Depends on: event scheduler, drafts and read state.
- **Welcome mail**: each new user gets a welcome message from the sysop, from a template per
  language, on by default; the shipped template is short and friendly. Depends on: private
  messages, languages.
- **Blocking and muting**: two verbs. Block a person, including a user from an external
  network, by name and network address: they disappear for the blocker (posts, netmail, who's
  online, the user list) and cannot contact them (no private mail, mentions or chat
  invitations); they are not told, and their mail is refused with the same answer as for any
  unavailable user. The block list is editable. Mute a person, a thread or an area: the content
  is hidden or collapsed while the person still exists, synced across front ends. Nobody can
  block moderation: notices from the Sysop and moderators, bans and appeal replies always
  arrive, and moderators acting as moderators still see a blocked user's content. Depends on:
  accounts and login, private messages, message bases.
- **Search**: a global search across every searchable area, or a search of one area, chosen from
  where the user is; posts and files; a username search; filters `from:`, `area:`, `before:`,
  `after:` and `has:attachment`. Result counts, "no results" and suggestions are worked out only
  over what the user can read; a username search never finds a private profile, except for a
  role that may see private users; results from users the searcher has blocked never appear, and
  muted content stays hidden. A saved search can notify its owner of new matches, which covers
  keyword watches: only for posts the user can read, never from a muted area or a blocked user,
  and with a cap on such searches per user. Depends on: message bases, file bases, RBAC,
  blocking and muting, rate limits; notifying saved searches on notifications.
- **File transfer on classic connections**: upload and download protocols over Telnet and SSH
  sessions. A protocol registry: XModem, XModem-1K, YModem, YModem-G and ZModem, with HTTP(S)
  and FTP as entries of their own; each protocol is on or off and available per role, default
  ZModem and the web; a batch flag decides whether the tagged queue is offered; a transfer log
  (protocol, bytes, speed, result) feeds the download counters and user statistics. The
  protocols run as external programs, lrzsz or SEXYZ, not yet chosen; one that ships in the
  installers appears on the licence page and its source is offered. The sysop adds external
  protocols with command-line templates, a hotkey and an order. A template is expanded into an
  argument list and run directly, never through a shell; a filename is checked against the
  area's naming policy first; protocols are defined only in `hadv-config`, by the Sysop, and
  audited. Depends on: Telnet and SSH callers, file bases.
- **SSH public-key login**: a user uploads a public key (on the web, or by file transfer on a
  classic connection) and logs in with it; a required second factor still applies. FIDO2
  security keys (`ed25519-sk`, `ecdsa-sk`) are accepted, and a signature carrying the
  user-verified flag (a PIN or biometric, not just a touch) satisfies the second factor on its
  own, checked at every login; a touch-only signature still gets the TOTP prompt. The sysop can
  remove a user's key: audited, the user told by inbox and email, and a Co-Sysop cannot remove
  a Sysop's or a Co-Sysop's. Depends on: SSH caller, accounts, second factor, file transfer.
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
- **Content warnings and spoilers**: a warning on a whole post, and spoiler sections inside
  one; the terminal hides them behind a key ("press R to read") and the web behind a click. On
  network export the warning becomes a plain first line ("CW: ...") and inline spoilers show in
  full, since other boards cannot hide them, and the editor tells the author so in a networked
  area. Depends on: message bases, full-screen text editor.
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
  through the board; that may be a later feature. The sysop guide covers the SPF, DKIM and
  DMARC DNS records and how to check them. Depends on: private messages, sensitive data
  encrypted at rest.
- **Sessions and devices**: a user sees their active sessions across Telnet, SSH, web and FTP
  (the front end, the IP address, the last activity) and ends one or all of them. A login from
  a new network (an IPv4 /24 or IPv6 /48 not seen before) or a new front end alerts the user,
  on by default: in the inbox always, and by email once the board can send it. App passwords
  are listed here too. Depends on: accounts and login, IPv4 and IPv6, SMTP client.
- **Step-up re-authentication**: one mechanism, used by user self-service, by administrators'
  destructive commands and by the console turning a service on. A user gives their password
  or second factor again before changing their email address or password, disabling TOTP,
  deleting their account, adding an SSH key or regenerating recovery codes; a short window
  after a step-up covers several changes. An email address change is confirmed to both
  addresses, and the old one gets a "this wasn't me" link that reverses the change within a
  set period. The Sysop's and Co-Sysops' destructive commands inside a session need a step-up
  on a cadence the sysop sets (per login, per command or per time interval), default every 15
  minutes. Depends on: accounts and login, second factor, SMTP client.
- **Data export**: a user exports their messages, mail, uploads list and profile as zip or
  JSON, one export every 7 days by default, after a step-up, delivered through the board and
  never emailed; staff notes are left out. The Sysop exports everything the board holds about
  one user, the Sysop note included, to answer a GDPR subject-access request. Depends on:
  accounts and login, private messages, message bases, file bases, step-up re-authentication.
- **Notifications**: an inbox with read state on the terminal and the web: mentions, replies,
  moderation actions on your content and system notices, with an unread count at login and in
  the prompt. Each area has a level, watching, tracking, normal or muted, default normal;
  following an area sets watching, and muted is the same as muting the area, not a second
  switch. A digest email, daily or weekly, opt-in, with a one-click unsubscribe (RFC 8058).
  Notices coalesce ("3 new replies in X"). Quiet hours, in the user's time zone. Web push, off
  unless the user turns it on, with a minimal payload. Security notices (login alerts, email
  changes, second-factor resets) always go straight through: never coalesced, put in a digest,
  held by quiet hours or muted. Depends on: accounts and login, SMTP client, blocking and
  muting.
- **Mentions and reply links**: an `@mention`, written with the handle's mailbox name
  (`@Dark.Lord`, so a handle with spaces is unambiguous), notifies the user, but only if they
  can read the post; a mention of a user the poster cannot see stays plain text; blocks apply.
  Mentions become links and notifications here, when shown; a message exported to a network
  goes exactly as written, its `@` never stripped, and a mention of a user on another board
  stays text. A message shows "N replies", and a reply links to what it quoted; in network
  areas the links come from the network's own reply references. Depends on: message bases,
  notifications, blocking and muting.
- **Bookmarks**: anyone who can read a message can bookmark it, with an optional reminder date
  delivered as a notification, the same on every front end. Access is checked when a bookmark
  is opened, so a message the user can no longer read shows "no longer available". Bookmarks
  are personal data, exported and deleted with the account. Depends on: message bases,
  notifications.
- **Link previews**, for later: off by default; the title and description of a posted link,
  shown as text on the terminal. The fetcher takes http and https only; checks the address
  after DNS resolution and again on every redirect, refusing private, loopback, link-local and
  cloud-metadata ranges; has a small size cap, a short timeout and few redirects; fetches once,
  when the link is posted, and caches the result, never fetching on view; and treats what it
  fetches as untrusted, stripping escape sequences. The same fetcher serves any later check
  that a BBS list entry is alive. Depends on: message bases.
- **Feed areas**: a read-only message area filled from an RSS or Atom feed the sysop adds, such
  as tech news or a club's blog, fetched on a schedule by the link previews' fetcher and under
  its rules; the feed's text is untrusted, only what the feed itself provides is carried, and
  each post links to its source. Depends on: message bases, link previews, event scheduler.
- **Social media features**: ready for an early brainstorm. Following an area is new-scan
  participation (force on, default on or default off per area), so a new user's feed is not
  empty; users follow other users; each profile has a microblog, extending one-liners; reactions
  decide the order in which each user sees things. Old-school and new-school parity: one store,
  two renderers, the web feed being new-scan with another sort; chronological by default,
  ranking a toggle that never filters below what new-scan would show; direct messages are
  private mail; a boost is a cross-post to an area you moderate, a quote post is quoting;
  hashtags are tags beside the area tree, listed in the terminal as virtual areas, as are saved
  searches; sharing is the permalink shown by the message number; presence is who's online with
  a status; avatars have an ANSI variant, treated as untrusted like DIZ text; follow requests
  for locked accounts from day one, and the brainstorm defines locked against private. Not
  carried over: infinite scroll, video, live streams, stories. Ranking is a Lua script the sysop
  can swap. A banned or suspended user's social content is hidden while the restriction lasts
  and restored when it is lifted. Depends on: message bases, private messages, who's online,
  search, notifications, reactions.
- **Events calendar**: a calendar of the board's events (game nights, network meetups, sysop
  chat hours, a door tournament), shown in each user's time zone; reminders come as
  notifications, and a scheduled post can announce an event. Creating events is a permission,
  held by Sysop and Co-Sysop by default. Depends on: notifications, scheduled posts,
  role-based access control.
- **SMTP server (receiving email)**: the board receives email for its users. Strict anti-relay
  rules: accept only email for local users and local domains. Port binding and listening
  addresses configurable. Maximum simultaneous connections configurable, default 100, shared
  across the SMTP, POP3 and IMAP servers. The SMTP server and each transport mode can be enabled
  and disabled individually in configuration, and all are off by default. The normal internet
  ports by default: TCP/25 receives from other mail servers, with STARTTLS offered and plain
  text accepted from a server that does not use it, for legacy network compatibility; TCP/587
  (STARTTLS) and TCP/465 (implicit TLS, SMTPS) are the submission ports for users' email
  clients, a later feature. Per-user address format: `handle@domain`, `first.last@domain` or a
  user-chosen alias, default `handle@domain`. Per-user address aliases; a catch-all or
  postmaster destination. The mailbox quota is the one private messages defines. Maximum
  accepted message size and maximum attachment size, default 25 MB. The board's private mail and
  external email share one store. Depends on: private messages, certificates, user profile and
  new-user questions.
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
  A day for the "today" counters is a day in the board's time zone. Also messages read, time
  online, and likes given and received. A "your stats" page, drawn by the theme, shows messages
  read, posts, time online, likes, files up and down, and member since; another user's stats
  honour a private profile. Depends on: accounts and login, message bases, private messages,
  file bases, time zones and daylight saving, reactions.
- **BBS statistics**: board-wide counters: logons, online time, netmail and email sent,
  feedback sent, new users, posts, uploads and upload bytes, downloads and download bytes
  today, and the maximum concurrent connections, in total and per connection type. Every
  counter is recorded per node and BBS-wide, and the console can view either. All-time totals
  sit alongside today's counters; the daily rollover is owned by daily maintenance. Statistics
  export as CSV or JSON from the Admin API and the console. A histogram of the busiest hours
  and days, and the peak concurrent sessions with the time they occurred. Depends on: user
  statistics, Waiting-for-Caller console, event scheduler.
- **Login and logoff sequence**: the shipped themes' behaviour, not an engine-level sequence
  editor: pre-login banner, ANSI detection, login menu, welcome, news, mail check and new-scan
  prompt, in an order easy to change inside the theme; a pre-login menu (apply, callers
  online, system info, log off), where callers online is the board-wide count only; "press any
  key" with configurable text, abortable and skipped in expert mode; a logoff screen with a
  random tagline and today's statistics, and a feedback prompt on the first logoff. The engine
  provides system news with a per-user last-read marker, so news shows when it has changed, a
  first-logoff flag and today's statistics, through `bbs.*`. Depends on: theme packs, user
  statistics, BBS statistics.
- **User preferences**: each user sets, with its default: language and time zone (the board's);
  short date format such as MM/DD/YYYY, and time format, 12 or 24 hour (the board's); theme (the
  default theme set in `hadv-config` and `hadv-config-gui`); terminal type: auto-detect,
  extended ASCII, ANSI or RIP (auto-detect); colour: auto-detect, yes or no (auto-detect);
  screen length and width: auto-detect or a number (auto-detect); expert mode, menus hidden
  unless `?` is pressed (no); pause at the end of each screen (yes); forward all netmail and
  email to the user's forwarding destination (no), with the forwarding format, the full message
  or a notification only (notification only); clear screen between messages (no); ask for a new
  message scan (no); remember the current message area (no) and file area (no); default download
  protocol, from the protocols the system defines (ZModem); hang up after a file transfer (no);
  editor: full-screen or line, on classic connections only (full-screen); message reading order:
  forward, reverse or threaded (forward); show signature on posts (yes); private profile (yes,
  as accounts and login describes); menu style, lightbar, classic hotkey or numbered, offered
  only where the user's theme draws it (the theme's); hotkeys, a single key without Enter (yes);
  quote style and prefix (`> ` with initials); messages and files per screen (screen length
  minus 2); available for chat or do not disturb (available), which blocks chat requests and
  pages from users but not the Sysop's break-in, and is separate from quiet hours. The
  forwarding destination is a network and an address: the user picks from every network the
  board supports, the Internet included, and types the address, which that network's own rules
  check and which holds everything the network needs to reach them (for FTN a name and a node,
  checked against the nodelist; for WWIV a number or a name at a node). An internet forwarding
  address is confirmed before any mail goes to it; there is one destination per user; forwarding
  over a BBS network warns once that netmail passes through hubs as plain text. Some of these
  may be better stored in a separate table linked to the user. Depends on: language choice, time
  zones and daylight saving, theme packs, message bases, private messages, file transfer on
  classic connections, SMTP client, full-screen text editor, basic line text editor, terminal
  capabilities; forwarding to a network address on mail networks.
- **Accessibility**: the BBS is as accessible as possible, to the level of WCAG 2.2 AA. On the
  web side, WCAG 2.2 AA itself; on legacy connections and in the TUI and GUI tools, WCAG2ICT
  (the W3C's guidance on applying WCAG to software that is not web) and EN 301 549, adapted
  where a terminal needs it. A screen-reader mode for terminal callers: linear text with no
  cursor positioning, numbered menus, the line editor, no art (its SAUCE title and description
  instead, where there is one), and nothing conveyed by colour alone. Time limits and idle
  timeouts can be extended or warned about; blinking, animation and baud-rate emulation can be
  turned off. The shipped themes meet it; theme packs declare whether they do. Research the
  existing standards before designing anything of our own. Depends on: user preferences,
  theme packs, terminal negotiation, classic text-mode interface.
- **Birthdays**: a birthday list, and a greeting at login on the user's own birthday. The list
  shows month and day only, never the year or an age; appearing in it is the user's choice,
  off by default even with a public profile, and a private profile never appears. The engine
  answers whose birthday it is among those who opted in, through `bbs.*`, and the themes draw
  it. Depends on: user profile and new-user questions, user preferences.
- **Signatures and taglines**: an automatic signature and rotating taglines per user. A
  signature has a line limit, classically 4, which the sysop sets. Both are user content,
  checked against watched words, with untrusted escape sequences stripped; their colour codes
  are converted or stripped per network on export, as the attribute codes entry does for
  bodies, and taglines follow the network's convention. Per area, a setting strips signatures
  on network export. Depends on: message bases, user preferences, attribute codes.
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
  FTP and FTPS are the FTP and FTPS server's listeners. `hadv-config` and `hadv-config-gui` have
  a subscriptions screen for each network: it reads the network's lists of subs, echoes and file
  areas, shows what the board subscribes to and what it hosts, and subscribes and unsubscribes
  in bulk, mapped to existing areas or new ones, sending the requests through the tossers with
  the per-area prompts message bases already has. Depends on: remote administration, message
  bases, private messages, cross-server task ownership.
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
  and bytes in and out, dupes rejected, last successful session. Later: packets from inter-BBS
  league games (BRE, Usurper and the like), handed over by a Helios Doors instance as opaque
  files, go to and from the league's hub as netmail or file attachments, carried without being
  understood, so a new game needs no engine change; the hand-off is a contract with
  HeliosDoors. Depends on: mail networks, file bases, external archivers, doors.
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
  packets and handles stale pointers. Each role has a ceiling on packet size and message
  count, and each user sets their own within it, never above. Depends on: message bases,
  private messages, file transfer on classic connections, external archivers.
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
  users. A user numbered above 65,535 is addressed by name, never by a truncated number. Heart
  codes translated on import and export (see attribute codes). Depends on: mail networks,
  attribute codes.
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
- **Registration gates**: whether new users may join: yes, no, a password, invite (invite links
  with a quota per role, and an invite tree the sysop can see) or approve (a questionnaire
  whose answers go to the moderation queue); default yes. Verification by email, by sysop
  approval or both; default email when the board can send it, otherwise sysop approval; email
  verification cannot be chosen while the email question is set to No. An account that never
  verifies is deleted when a short window passes. Terms of service, written by the sysop, are
  shown and required at registration; the version each user accepted is kept, and a changed
  version is accepted again. A self-hosted proof-of-work challenge, never a third-party
  CAPTCHA, guards web registration, on by default. New-user feedback to the sysop: no,
  optional or required with a minimum length; default no. Depends on: accounts and login,
  user profile and new-user questions, SMTP client, content moderation.
- **Sign in with an identity provider**, for later: an OIDC or OAuth2 client that links an
  account to an outside identity, such as an organisation's, never bypassing registration
  gates, the terms of service or the New User sandbox. An outside login replaces the password,
  not the second factor, whose per-role requirement still applies. The terminal uses the
  device flow (RFC 8628), so it is not web-only. Off by default, with each provider added by the
  Sysop. Depends on: accounts and login, registration gates, second factor.
- **Private mail privacy**: a stated policy, disclosed in the terms of service at
  registration: the board offers no way to read a user's mail except a break-glass read by
  account #1 alone, not the Sysop role, always audited. The policy is honest that whoever runs
  the server can technically read the database, and that encryption at rest guards against a
  stolen disk or backup, not against the holder of the keys. A private message its recipient
  reports reaches the moderation queue by their choice and needs no break-glass. A sysop
  cannot widen the policy. Depends on: private messages, registration gates.
- **Advisory signals**: at registration the address is checked against the Tor exit list and
  abuse feeds, downloaded as lists and checked on the board, never looked up one user at a
  time with a third party; a match is a flag for the sysop, never a block. An account sharing
  an IP address with another gets an advisory, skipping the exempt-source list. No
  geolocation. Depends on: registration gates.
- **Automatic promotion and demotion**: the Sysop writes rules in the configuration tools that
  move users between roles on metrics, with AND and OR conditions; the metrics include read
  activity (messages read, days visited, likes received) and count reports received against
  the user. There can be many rules, and users never see them. One promotion rule ships,
  moving users out of New User after at least 3 calls on at least 2 different days and at
  least 20 minutes online in total; the sysop can delete it. No demotion rule ships. A rule
  never moves a user into a role that holds administrative or moderation permissions, and a
  demotion rule sends its proposal to the moderation queue for a person to confirm. New User
  ships as a sandbox until promoted: no links in posts, no attachments, no private mail to
  users who do not follow them, no doors. Depends on: RBAC, user statistics, content
  moderation; the follower rule on social media features.
- **Achievements**: badges from rules the Sysop defines, like the promotion and demotion rules
  and with the same mechanism, AND and OR over the same metrics, awarding a badge instead of
  moving a role. The themes draw the badges, in ANSI on the terminal. The shipped rules lean on
  milestones (first post, one-year member, ten-year member) rather than volume. Depends on:
  user statistics, automatic promotion and demotion.
- **One-liners and friends**: the engine keeps them, shared across servers, and exposes them
  through `bbs.*`; the themes show them. One-liners in a fixed ring; rumors, anonymous
  one-liners, optionally per area; Auto-Message, one login message replaced by the next
  writer; Quote of the Day, written by the sysop, one at random on login; last callers, where
  a private user does not appear and only what a profile makes public is shown, the console
  keeping the full detail. All of it is user content: length limits, watched words,
  reportable. A rumor is anonymous to users, not to staff. Depends on: scripting layer, who's
  online, content moderation.
- **BBS list**: a directory of other systems (Telnet, SSH, web) that users keep, exported as
  JSON and RSS, with the compiled network nodelists and BBS lists browsable and searchable
  from the same screen. A new entry goes to the moderation queue, and its submitter can edit
  it afterwards. The board never connects to a listed host to check it; an entry shows when a
  user last confirmed it. Depends on: content moderation, FTN networks, VirtualNET networks,
  WWIV networks.
- **Spam filtering**: inbound and outbound email is checked by an external spam checker, such
  as rspamd or SpamAssassin, the way virus scanning uses ClamAV, with thresholds set in
  `hadv-config` and `hadv-config-gui`. High-confidence spam is rejected during the SMTP
  conversation, never accepted and then deleted; low-confidence spam goes to the user's junk
  folder, and optionally to the review queue. A burst of outbound mail from one account raises
  an alert to content moderation, beside the rate limits. Depends on: SMTP server, SMTP
  client, content moderation, rate limits.
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
  archivers, event scheduler.
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
  approval, feedback received, an appeal filed and a scheduled event that failed (with the tail
  of its output), in the inbox and optionally by email. Depends on: bans, suspensions and
  appeals, SMTP client, event scheduler.

## Chat

- **Multi-user chat**: users chat with other online users in an IRC-style chat, supported by
  the content moderation system, honouring blocks and private profiles as who's online does.
  Depends on: who's online, content moderation.
- **Inter-BBS chat**, for later: multi-user chat joins rooms shared with other boards. Research
  MRC (Multi Relay Chat) compatibility first, rather than inventing a network: its protocol and
  hub model, TLS, and whether it is specified openly enough to implement from our own notes; the
  research may say no. Remote chat passes through the same moderation as local chat, and users
  can block remote chatters. Depends on: multi-user chat, blocking and muting.
- **Sysop break-in chat**: the Sysop can break in on a caller with a two-way split-screen chat
  from the WFC consoles (`hadv-console`, `hadv-console-gui`). Sysop only by default; the Sysop
  can grant the permission to other roles. A caller without ANSI gets line-by-line chat.
  Depends on: Waiting-for-Caller console, terminal negotiation.
- **Sysop page**: a caller pages the sysop. Page hours and an available flag are configurable;
  outside them, a page falls through to feedback mail. A page arrives as an alert in both
  consoles, with the classic sound, and is answered with break-in chat, under its permission.
  One page per caller per N minutes. Paging is a permission every role holds by default except
  Guest. Depends on: sysop break-in chat, private messages, rate limits.

## Not yet described

Storage (one storage registry shared by file areas, message attachments and more), feedback to
the sysop (counted in BBS statistics, notified by sysop notification triggers), and everything
else the developer adds as it comes up.

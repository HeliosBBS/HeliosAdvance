# ADV-002 Remote administration

Status: approved. Brainstorm record: to be linked (HeliosDesign Discussion "ADV-002 brainstorm").

## Purpose

The board's servers may be hosted at a cloud provider, and the sysop configures and monitors
the BBS from their home computer as if it were local; a Co-Sysop the sysop chooses to admit
does their own administration the same way. Every administration tool reaches the board
through one Admin API on the network, never the database. Sign-in takes a second factor,
tokens are scoped and limited in lifetime, an allow list keeps everyone else out before they
can try a password, and every entry in the audit log names the credential that acted. Nothing
is open remotely until the sysop opens it.

## Behaviour

### Reaching the Admin API

- When an administration tool connects to the Admin API on any server of the board, the
  system shall serve it the same board, with the same sessions and tokens, whichever server
  it reached.
- When a connection arrives from the server's own host, the system shall admit it to sign-in.
- When a connection arrives from any other address, the system shall admit it to sign-in only
  if an allow-list entry matches that address.
- If a connection's address matches no allow-list entry, then the system shall close it
  before any sign-in is attempted, and count and log the refusal within a limit.
- When the allow list is empty, as it is on a fresh install, the system shall admit only the
  server's own host.
- When an allow-list entry is a hostname, the system shall resolve it to its IPv4 and IPv6
  addresses, cache the result for the record's time-to-live clamped between a fixed floor
  and ceiling, and verify the answer's signature where the record is signed.
- If a hostname entry cannot be resolved, or a signed answer fails verification, then the
  system shall treat that entry as matching nothing.
- When the board sits behind a proxy or load balancer, the system shall take a connection's
  address from a PROXY protocol header only when the connection comes from an address on the
  trusted proxy list; it shall not take the address from HTTP forwarding headers on the
  Admin API.
- If a connection from an address not on the trusted proxy list begins with a PROXY protocol
  header, then the system shall close it.
- When a tool connects to a board for the first time and the certificate is trusted by a
  public certificate authority and matches the hostname, the tool shall accept it.
- When a tool connects to a board for the first time and the certificate is not publicly
  trusted, the tool shall show the board signing key's fingerprint and send no credential
  until the sysop confirms it matches the one `hadv-config` shows on the host; on
  confirmation, the tool shall pin the board's signing key.
- While a tool holds a pinned board key, when a server presents a certificate signed by that
  key, the tool shall accept it, including from a server added after the pin.
- If a server presents a certificate not signed by the pinned key, then the tool shall stop
  with a loud warning and send nothing until the sysop re-checks the fingerprint and
  confirms.
- If a load balancer decrypts Admin API traffic, then the tool shall treat the balancer's
  certificate like any certificate not signed by the pinned key and stop with the loud
  warning; the sysop guide shall describe passthrough with a PROXY protocol header as the
  supported setup.

### Sign-in

- When a connection admitted by the allow list names an account, the system shall refuse it
  before checking the password unless the matching entry admits that account or its role; a
  connection from the server's own host admits every account.
- When an admitted account signs in, the system shall require its password, and its second
  factor whenever the account's role requires one.
- When an account signs in to a tool, the system shall grant the tool only if the account
  holds that tool's permission: `hadv-config` requires the Sysop role, fixed, and no one can
  grant it to another role; each other tool names its own permission.
- If an account signs in without the permission for the tool it is using, then the system
  shall refuse the sign-in and record the refusal.
- When a sign-in fails, the system shall apply the board-wide lockout and source slowdown
  owned by accounts and login, so that the Admin API and every other surface share one count.
- If failures from the server's own host pass the refusal threshold, then the system shall
  keep slowing that host but never refuse it.
- When a sign-in succeeds, the system shall show how many failed attempts on that account
  there were since its last successful sign-in, and from which addresses.
- When `hadv-config` signs in interactively, the system shall hold the session in the running
  tool's memory only, never on disk, and end it when the tool closes, after the idle timeout,
  or at the absolute timeout, whichever comes first.
- When an interactive `hadv-config` session ends while changes are waiting to be applied, the
  tool shall keep them, ask for sign-in again, and let the sysop apply them after signing in
  as the same account.
- When the CLI signs in interactively, it shall read the password and second factor from the
  terminal, never from its arguments.
- When a sysop turns off the second-factor requirement on a role whose accounts are admitted
  by any allow-list entry other than the host, the system shall show a loud warning naming
  those entries and change nothing until the sysop confirms.
- When a sysop adds an allow-list entry that admits an account whose role has no
  second-factor requirement, the system shall show a loud warning naming that role and
  change nothing until the sysop confirms.

### Tokens

Console tokens:

- When `hadv-console` signs in with the console token lifetime above 0, the console shall
  generate a key pair on that device, and the system shall issue a console token bound to its
  public half.
- When the console stores its private key, it shall use the device's hardware key store
  where one is reachable, so the key cannot be exported, and otherwise the operating system's
  protected store; the console shall tell the sysop which tier it got.
- If a request carries a console token without a valid signature from the device key it is
  bound to, then the system shall refuse it.
- While a console token is valid, the system shall allow it console actions only (watching,
  kicking a caller, restarting a node and the other console actions), and shall refuse it any
  change to settings, tokens, accounts, roles or second-factor requirements.
- When the console launches the user editor, the user editor shall ask for its own sign-in,
  and its session shall end on the same timeouts as `hadv-config`'s.
- When a console token's lifetime has passed since sign-in, or it has gone unused for 24
  hours, the system shall end it; using the token shall not extend its lifetime.
- When the console token lifetime is 0, the system shall issue no console token, and the
  console shall ask for sign-in at every launch.
- When a new console device is issued a token, the system shall record it in the audit log
  and flag it at the next sign-in of every Sysop-role account.

Automation tokens:

- When a signed-in Sysop creates an automation token in `hadv-config`, the system shall
  require a name, the settings groups it may read, the settings groups it may change, and a
  lifetime within the floor and ceiling.
- When an automation token is created, the system shall show its secret once and keep only a
  value it can check the secret against, never the secret itself.
- If a request asks an automation token to create or revoke tokens, change a role's
  second-factor requirement, change token lifetimes, or change accounts or roles, then the
  system shall refuse it, whatever its scope.
- When a sysop creates an automation token that may change a group containing a setting that
  loosens security, the system shall show a loud warning naming those settings and create
  nothing until the sysop confirms.
- If an automation token asks to change a setting outside the groups it may change, or read
  one outside the groups it may read, then the system shall refuse it.
- When the CLI uses an automation token, it shall read the secret from an environment
  variable or a file, never from its arguments.
- If a CLI command would loosen security and lacks the explicit acknowledgement flag, then it
  shall fail, changing nothing.

Both:

- When a Sysop-role account views tokens in `hadv-config`, the system shall list every
  console token and automation token with its account, name or device, when it was created,
  when it was last used and from which address, and shall let the sysop revoke any one
  immediately.

### The allow list

- When a Sysop-role account edits the allow list in `hadv-config` or its CLI, the system
  shall accept entries that are an address, an address range, or a hostname, each naming the
  accounts or roles it admits.
- If an entry names no account and no role, then the system shall refuse it.
- When an entry is added, or an existing one widened to more addresses or more accounts, the
  system shall show a loud warning of what it opens and change nothing until the sysop
  confirms; the CLI shall require the acknowledgement flag.
- When an entry is a range wider than a single household usually needs, the warning shall
  say so and mention shared addresses such as carrier-grade NAT.
- When an entry admits the Sysop role as a whole rather than named accounts, the warning
  shall say that every present and future Sysop-role account is admitted from there.
- When the allow list changes, the system shall apply it on every server without a restart.
- When an entry is removed or narrowed, or a hostname entry's address changes, the system
  shall refuse the next request from any connection the list no longer admits, including one
  already signed in.
- When the sysop views the allow list, the system shall show the server's own host as always
  admitted, and shall offer no way to remove it.

### Revocation

- When an account's password changes, or its second factor is enrolled, removed or reset,
  the system shall revoke every console token, automation token and open session of that
  account.
- When an account loses the role that granted a tool's permission, is permanently locked, or
  is deleted, the system shall revoke every console token, automation token and open session
  of that account.
- When a token or session is revoked, the system shall refuse its next request on every
  server.
- While an account is only temporarily locked, the system shall leave its existing tokens
  and sessions in place.

### Audit

- When any action passes through the Admin API, the system shall record in the audit entry
  the account, the credential that acted (interactive sign-in, the named console device, or
  the named automation token), the address it came from, and the server it reached.
- When a sign-in succeeds or fails, a token is created or revoked, a console device is added,
  or the allow list changes, the system shall record an audit entry.
- When a sysop confirms a loud warning, the system shall record the confirmation in the audit
  entry of the change it allowed.

### Across servers and on failure

- When a tool asks for an action on a server other than the one it reached, the system shall
  carry it out on that server; if that server is not live, then the system shall report the
  action as not done.
- If the database is unreachable from the server a tool reached, then the Admin API on that
  server shall refuse every request, sign-in included.
- If any check on the path (allow list, sign-in, permission, token signature, token scope)
  cannot complete, then the system shall refuse the request.

## Security decisions

1. **The Admin API facing the internet.** Attacker: anyone on the internet. Abuse: password
   guessing, scanning, attacking code that runs before sign-in. Decision: a fresh install
   admits only the host itself; remote access exists only through allow-list entries the
   sysop adds in `hadv-config`, and a connection from any other address is closed before
   sign-in. Why: nothing is open remotely until the sysop opens it. Fails closed: no matching
   entry, no connection.
2. **The database is never reachable from the tools.** Attacker: anyone who reaches a tool's
   path to the board. Abuse: attacking PostgreSQL directly from a home network. Decision:
   every administration tool goes through the Admin API; only the engine touches the
   database. Why: the database never has to be exposed beyond the servers, and the graphical
   tools no longer need their own second implementation of database access and the
   permission check. Fails closed: there is no path to the database from a tool.
3. **One entry, one set of people.** Attacker: someone on a Co-Sysop's home network. Abuse:
   trying the Sysop's password from an address allowed for someone else. Decision: each entry
   names the accounts or roles it admits, and the name is checked before the password. Why:
   admitting a Co-Sysop never exposes the Sysop's account. Fails closed: an account not named
   is refused.
4. **Dynamic DNS entries.** Attacker: whoever controls the dynamic DNS account, or can forge
   the board's DNS answers. Abuse: pointing a hostname entry at their own address. Decision:
   the allow list is a layer on top of sign-in, never a replacement for it; signed records
   are verified; cache times are clamped; the sysop guide says plainly that most dynamic DNS
   providers do not sign their records. Why: the DNS account becomes part of the trust chain,
   so it must never be the only guard. Fails closed: an entry that cannot be resolved or
   fails verification matches nothing.
5. **A forged source address.** Attacker: anyone who connects directly. Abuse: claiming an
   allowed address. Decision: a caller's address is taken from a PROXY protocol header only
   when the connection comes from a trusted proxy; HTTP forwarding headers are ignored on the
   Admin API; an untrusted connection that sends a PROXY header is closed. Fails closed:
   close.
6. **A machine in the middle at first contact.** Attacker: anyone between the sysop's PC and
   the board. Abuse: collecting the password and second factor. Decision: publicly trusted
   certificates are accepted as HTTPS normally is; a self-signed board is checked once by
   fingerprint against what `hadv-config` shows on the host, and the tool then pins the
   board's signing key, which covers every server, including ones added later; load
   balancers pass traffic through without decrypting it. Fails closed: no credential is sent
   before confirmation, and a certificate not signed by the pinned key stops the tool.
7. **Guessing passwords, and lockouts as a weapon.** Attacker: anyone admitted to sign-in.
   Abuse: guessing passwords, or failing on purpose to lock staff out. Decision: one
   board-wide lockout and source-slowdown policy, owned by accounts and login and shared by
   every surface; account #1 is never locked, so the owner can always get in and unlock
   everyone else; the host is slowed but never refused. Fails closed: past the threshold, the
   address is refused.
8. **The second factor turned off.** Decision: a sysop may turn off a role's second-factor
   requirement, but only after a loud warning of what it means for remote sign-in, shown both
   when turning it off while remote entries exist and when adding a remote entry for a role
   without it; the sysop guide carries the same warning. Why: the sysop may choose it, as
   long as they understand the risks. Fails closed: nothing changes until they confirm.
9. **A stolen console token.** Attacker: whoever takes the token from, or compromises, the
   sysop's PC. Abuse: running the console as the sysop. Decision: the token is tied to a key
   held on the device, in the hardware key store where one is reachable; it is limited to
   console actions; it lasts 1 day by default, 7 days at most, counted from sign-in; it ends
   after 24 hours unused; it is listed and can be revoked; a new device is flagged to every
   Sysop; the user editor asks for its own sign-in. Why: the console acts freely, while a
   stolen token is worth little. Accepted risk: malware running live on the PC can drive an
   open console; the token's narrow scope limits what that achieves. Fails closed: a request
   without a valid device signature is refused.
10. **A leaked automation token.** Attacker: whoever reads a script, a CI secret or a log.
    Abuse: changing the board. Decision: the token is scoped by settings group for reading
    and changing separately; some actions no token can ever do (managing tokens, accounts or
    roles, second-factor requirements, token lifetimes); the board keeps only a value to
    check it against; it lasts 365 days at most, with no "never expires"; the CLI reads it
    only from an environment variable or a file; a scope that can loosen security needs a
    confirmed warning. Fails closed: anything outside its scope is refused.
11. **Who may administer.** Decision: `hadv-config` requires the Sysop role, fixed, and no one
    can grant it to another role; each other tool checks its own permission; a Co-Sysop
    reaches the Admin API only through an entry that names them. Fails closed: no permission,
    no sign-in.
12. **Credentials that change.** Decision: a changed password or second factor, a lost role, a
    permanent lock or a deleted account revokes every token and session of that account, on
    every server, from the next request; a temporary lock revokes nothing. Why: otherwise
    anyone could knock the sysop's console off by mistyping the password.
13. **Loosening, in general.** Decision: any change that loosens security shows a loud warning
    of what it opens and takes effect only after the sysop confirms; the confirmation is
    recorded in the audit entry; the CLI requires an explicit acknowledgement flag; the sysop
    guide carries the same warning.
14. **Audit.** Every action through the Admin API records the account, the credential that
    acted, the source address and the server it reached; sign-ins, token creation and
    revocation, new console devices and allow-list changes each write their own entry.
15. **Failure.** Decision: a database that cannot be reached, or any check that cannot
    complete, means the request is refused. Fails closed: refuse.

## Limits

| Limit | Kind | Default | Key |
|---|---|---|---|
| Admin API listener | sysop tunable | TCP/8443, all addresses | `admin_api.listen` |
| Allow list | sysop tunable | empty: the host only | `admin_api.allow_list` |
| Interactive sign-in idle timeout | sysop tunable, between a fixed 5 and 60 minutes | 15 minutes | `admin_api.session_idle_minutes` |
| Interactive sign-in absolute timeout | sysop tunable, between a fixed 1 and 12 hours | 8 hours | `admin_api.session_max_hours` |
| Console token lifetime, from sign-in | sysop tunable, between a fixed 0 and 7 days | 1 day | `admin_api.console_token_hours` |
| Console token unused expiry | fixed policy backstop | 24 hours | none |
| Automation token lifetime | chosen per token at creation, between a fixed 1 and 365 days | 90 days | none (set on each token) |
| Hostname cache time | the record's time-to-live, clamped by a fixed policy backstop | between 30 seconds and 5 minutes | none |
| Logging of refused connections | calibration target | enough to diagnose; a flood cannot fill the log | none |
| Failed sign-in lockout and source slowdown | owned by accounts and login | as that feature sets them | theirs |

## Non-goals

- The look and screens of the tools: the classic text-mode interface, `hadv-config`'s
  dialogs and apply behaviour, `hadv-setup`, and the console's screens and taskbar
  behaviour are their own features.
- The lockout and slowdown policy itself, which belongs to accounts and login, and throttling
  callers by connection rate, which belongs to the caller features; this feature uses both.
- Which second-factor methods exist; the second-factor feature decides them, and this
  feature requires whatever the role requires.
- Obtaining certificates; `hadv-cert` and an external ACME client do that.
- A VPN or tunnel built into the board; the sysop guide may recommend one for a sysop who
  travels.
- Tying tokens to one IP address; home addresses change, and the allow list with hostnames
  does that job.
- HTTP/3 on the Admin API.
- Letting another role sign in to `hadv-config`.
- Single sign-on through an outside identity provider.
- Third-party clients: the Admin API serves the estate's own tools; it is not the public
  JSON API, and nothing outside this repository depends on its shape.

## Repositories and contracts affected

- HeliosAdvance only. Introduces the Admin API, a contract owned by this repository and
  consumed by its own tools (`hadv-config`, `hadv-console`, `hadv-useredit`, `hadv-strings`
  and their graphical counterparts); registered in the contracts register, versioned, when
  the design fixes its shape.
- Changes the derived architecture: the runtime configuration tools no longer run on a
  server's host with that server's database login; they reach the board through the Admin
  API from anywhere the allow list admits, and the graphical configuration tool's second
  implementations of database access and the permission check go away. The design amends
  the architecture, access-control and stack documents; ADV-001's brief is unchanged.
- Consumes accounts and login (sign-in, lockout, source slowdown, the exempt-source list),
  role-based access control, the second factor, certificates and the join feature's board
  signing key, and the trusted proxy list.
- Nothing in the Door Kit, HeliosDoors, the Portal, the SIP gateway or the load tester; the
  SIP gateway and the load tester appear only through the exempt-source list, which accounts
  and login owns.

## Open questions

None.

# Sessions
Serves: ADV-002

## Purpose
Serves: ADV-002
The engine's one home for session handling, holding the one record of signed-in credentials: what a presented credential is, whose it is, for how
long, and how it ends, on every server alike. It holds the operator credentials (interactive
sessions, console tokens, automation tokens), their console devices and the sign-in attempts
waiting for a second factor. It does not check passwords or second factors, decide permissions, or
see the network: accounts v1, second-factor v1, access-control and admin-api do.

## Terms
Serves: ADV-002
As the glossary defines them: credential, interactive session, console token, automation token,
console device, sign-in attempt, operator account, settings group, loosening finding,
confirmation; access-control defines the credential ceiling, and admin-api the source class
and the sign-in principal. This document introduces:

- **presented form**: how a bearer credential or an attempt handle travels: the identifier in
  decimal, a full stop, and the secret in unpadded base64url (RFC 4648 section 5).
- **attempt handle**: a sign-in attempt's identifier and secret.
- **credential view**: what a verification answers: identifier, kind, account, tool, read and
  change groups (automation), device key fingerprint (console), created at, effective expiry.
- **effective expiry** and **idle limit**: Data model states them.
- **issuing server**: the server whose database login the operation that issued a credential ran
  under.

## Contracts
Serves: ADV-002
Provided, **sessions.operator v1**, to admin-api, to cluster's removal, and to the features that
owe the revocation obligation (accounts v1, rbac v1, second-factor v1, as admin-api states them):

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| startAttempt | account, tool, the pending console key (public key, device name, reported tier) or none, source address, source class (`host` or `remote`), server | the attempt handle, in its presented form, returned once | Unavailable |
| checkAttempt | the attempt handle, the source address presenting it | whether the secret matches (compared in constant time), the address is the bound one, and the attempt is `awaiting` and unexpired, and on a match the attempt's account and tool; an expired attempt is expired as check-then-act 6 states; writes nothing else | Unavailable |
| readAttempt | inside the caller's transaction, after the account's rows and the source's count row are held: the attempt identifier | `awaiting`, `not awaiting`, or `expired` (having run check-then-act 6 in that transaction) | whatever the transaction reports |
| consumeAttempt | inside the caller's transaction: the attempt handle, the source address presenting it | the attempt's account, tool and pending console key | Denied (unknown identifier, wrong secret, another source address, expired, already consumed), Unavailable |
| issue | inside the caller's transaction: actor, account, kind, tool, source address, server, the lifetime (hours for `interactive` and `console`, days for `automation`) and for `interactive` the idle minutes, as the caller's snapshot holds them, bounded in the database by the fixed backstops; for `console`, the device (public key, device name, reported tier); for `automation`, a name, the read groups, the change groups, a lifetime in days, a request identifier and the confirmation | the credential identifier; the secret for `interactive` and `automation`, in the presented form, returned once; for `console`, whether the device is new | Invalid, Denied (`automation` without `credentials.manage`), Refused (a change group the automation ceiling refuses; confirmation required, with the findings), Conflict (an active automation token has the name; the request identifier was used by this creator, with that token's identifier), Unavailable |
| verifyBearer | a presented identifier and secret; the current lifetime and idle values | the credential view; writes nothing but the end of a credential found expired or idle | Denied (unknown identifier, wrong secret, a console token, not active, or ended by this verification), Unavailable |
| verifyConsole | a presented identifier, the signed message, the signature; the current lifetime and idle values | as `verifyBearer` | Denied (unknown identifier, not a console token, signature invalid, not active, or ended by this verification), Unavailable |
| touch | a verified credential identifier, source address, server | none; last use written when last used at is older than the coarsening, where the credential is still `active` | Unavailable |
| end | the calling credential | none; idempotent | Denied (an automation token, which only `revoke` ends), Unavailable |
| list | actor | every active credential: identifier, kind, account, tool, name (automation) or device name and key fingerprint (console), issuing server, created at, effective expiry, last used at, from which address and on which server | Denied, Unavailable |
| revoke | actor, credential identifier | the state after: `ended`, whether this call ended it or it had already ended | Denied, NotFound, Unavailable |
| revokeForAccount | inside the caller's transaction, which has taken the account's rows before any row the hold order places later: actor, account, cause | the identifiers revoked; idempotent | whatever the transaction reports |
| revokeForServer | inside the caller's transaction: actor, server, cause (`server removed` or `server secret reset`) | the identifiers revoked: every active credential whose issuing server is that server; idempotent | whatever the transaction reports |
| previewIssue | as `issue` for an automation token, less the confirmation | the findings and the confirmation; writes nothing | Invalid, Denied, Refused (a change group the ceiling refuses), Unavailable |
| devicesToShow | an account, and the credential its current sign-in issued | every console device holding an active console token, and every device first seen since the earlier of that account's previous Admin API sign-in (the latest credential issued to it at sign-in other than the one given, within the retention; none means every device) and now less the listing window: account, device name, key fingerprint, first seen at, from which address, whether it holds an active token, whether it is new since that sign-in | Unavailable |

Gates, through access-control v1, any error from the check being Denied: `list` and `revoke`
require `credentials.manage`; `issue` of an automation token requires `credentials.manage`, and
refuses each change group for which `authorize` would deny `settings.change` to the token being
created, so the credential ceiling alone decides which groups an automation token may change;
the other operations are the sign-in and the verification themselves, take no gate, and are
reached only in the order admin-api's sign-in and request pipeline state. `issue` of an
automation token applies configuration v1's confirmation rule over one finding for each setting
in a change group whose declaration carries a loosening rule.

`verifyConsole` checks the signature against the device's stored public key as ECDSA over P-256
with SHA-256 (FIPS 186-5); the message is admin-api's.

Consumed: database-access v1; access-control v1; audit v1; configuration v1 (`get` for the
lifetime settings below, the confirmation rule, the settings groups and their declarations);
accounts v1 `recordFailure`, as admin-api states it, for an attempt that expires.

## Data model
Serves: ADV-002
Every time is the database clock. Every identifier is an increasing identifier. Every secret is
256 bits from the host's cryptographic random source, generated by the engine; only its SHA-256
digest (FIPS 180-4), the verifier, is stored, and a presented secret is compared with it in
constant time.

**Credential**:

| Field | Meaning |
|---|---|
| credential ID | the key |
| kind | `interactive`, `console` or `automation` |
| account | the account it belongs to |
| tool | a tool name; `config` for every automation token, `console` for every console token |
| verifier | for `interactive` and `automation`; empty for `console` |
| device | for `console`: the console device; empty otherwise |
| name | for `automation`: 1 to 64 printable characters; empty otherwise |
| read groups, change groups | for `automation`: sets of settings group names, the change groups within the read groups; empty otherwise |
| issuing server | stamped by the database from the calling login, as audit's origin server is |
| created at | stamped by the database |
| expires at | created at plus the lifetime in force at issue: `admin_api.session_max_hours` for `interactive`, `admin_api.console_token_hours` for `console`, the chosen days for `automation` |
| idle minutes | for `interactive`: `admin_api.session_idle_minutes` in force at issue; for `console`: 1,440; empty for `automation` |
| last used at, last used address, last used server | set at issue to created at and the sign-in's address and server; then written by `touch` |
| state | `active` or `ended` |
| ended at, end cause | `expired`, `idle`, `signed out`, `revoked by sysop`, `password changed`, `second factor changed`, `role lost`, `permanently locked`, `account deleted`, `server removed`, `server secret reset` |
| created by, request identifier | for `automation`: the creating credential and the client's request identifier |

Constraints, enforced by the database: the fields each kind requires are set and the fields it
does not use are empty; expires at is at most created at plus 12 hours for `interactive`, 7
days for `console`, and between 1 and 365 days for `automation`; idle minutes lies between 5 and
60 for `interactive`; a name is unique among `active` automation tokens; (created by, request
identifier) is unique where set.

**Console device**, one row per account and public key, kept after its tokens end so that the
same device signing in again is not new:

| Field | Meaning |
|---|---|
| device ID | the key |
| account | |
| public key | the SubjectPublicKeyInfo (RFC 5280) of an ECDSA P-256 key |
| key fingerprint | SHA-256 of the public key |
| device name | 1 to 64 printable characters, as the console reports it |
| reported tier | `hardware` or `os_protected`; as the console reports it, never verified and never a basis for a decision |
| first seen at, first address, first server | |

Constraint: (account, key fingerprint) is unique.

**Sign-in attempt**, the span between a verified password and the second factor:

| Field | Meaning |
|---|---|
| attempt ID | the key |
| verifier | SHA-256 of the attempt secret |
| account, tool | |
| pending console key | public key, device name, reported tier; or empty |
| source address, source class, server | the attempt is bound to the source address, and for a host connection also to the server it began on; its failures are counted with that server |
| created at, expires at | expires at is created at plus the attempt lifetime |
| state | `awaiting`, `consumed`, `expired` |

**Effective expiry**, applied at every verification: for `interactive`, the earlier of expires
at and created at plus the current `admin_api.session_max_hours`; for `console`, the earlier of
expires at and created at plus the current `admin_api.console_token_hours`; for `automation`,
expires at. **Idle limit**: last used at plus the smaller of the stored idle minutes and, for
`interactive`, what configuration v1 `get` answers for `admin_api.session_idle_minutes`; none
for `automation`. The lifetime likewise takes the smaller of the credential's own value and
what `get` answers, so a value `get` cannot give as set, even the default, never lengthens a
credential. A lowered setting shortens credentials already issued; a raised one never lengthens
them.

Check-then-act operations, each one transaction, taking holds in the architecture's hold order:

1. **Verify** (`verifyBearer`, `verifyConsole`), in the engine's transaction: an exclusive hold
   on the credential row found by identifier (a hold is not a write, and a server login may read
   the row); for a bearer, the verifier compared; for a console token, the device's public key
   read and the signature checked; nothing is written on a failed comparison or signature, so an
   identifier alone can neither extend a credential nor move its last use. Then, when the
   effective expiry or the idle limit has passed on the database clock, the database-side
   operation `endExpired` ends the row by compare-and-set, cause `expired` or `idle`, and the
   answer is Denied; the current values it is given are bounded inside it by the fixed
   backstops. Otherwise nothing is written.
   **Touch**, the database-side operation admin-api calls only after the request has passed
   its admission and permission checks: last used at, address and server written when last
   used at is older than the coarsening and the row is still `active`. The coarsening can only
   make an idle end come early, the closed direction, and a refused request never moves it.
2. **Consume an attempt**: compare-and-set `awaiting` to `consumed` where the source address is
   the bound one and expires at is later than the database clock, in the caller's transaction,
   which then issues the credential or records the failed response. A second consumption finds
`consumed` and is Denied.
3. **Issue**: insert the credential; for `console`, find the device by (account, key
   fingerprint) or insert it; for `automation`, in the same transaction: end by compare-and-set
   any `active` automation token of the same name past its expiry, then insert; the uniqueness
   constraints turn a concurrent duplicate into Conflict.
4. **Revoke** and **end**: compare-and-set `active` to `ended` with the cause, with the audit
   entry in the same transaction.
5. **revokeForAccount** and **revokeForServer**: for an account, its `awaiting` attempts set
   `expired` first, then the same compare-and-set over every matching `active` credential,
   following the hold order, inside the caller's transaction, one audit entry per credential ended and one `sign_in_attempt.expire`
   per attempt expired (with the revocation's cause, and no failure count).
6. **Expire an attempt** (at consumption or by the sweep): the attempt's account read without a
   hold, the account's rows and the bound source's count row held first (the holds
   `recordFailure` needs), then compare-and-set
   `awaiting` to `expired` where expires at has passed, and in the same transaction accounts v1
   `recordFailure` against the attempt's account (reason `second factor not completed`), with the attempt's own server as the reached server, whichever server runs it, and the
   entry `sign_in_attempt.expire`; exactly one of the two expiry paths wins, so the failure is
   counted once.

Every write above is a database-side operation (the architecture's login tiers): a server
login's direct write to a credential, console device or sign-in attempt row is refused by the
database.

## Behaviour
Serves: ADV-002
Credential states, for every kind:

| State | Input | Transition |
|---|---|---|
| active | a verification with the right secret or a valid signature, before the effective expiry and the idle limit | active; nothing written until `touch` |
| active | a verification after the effective expiry | ended (`expired`); Denied |
| active | a verification after the idle limit | ended (`idle`); Denied |
| active | an unknown identifier, a wrong secret or an invalid signature | Denied; nothing written |
| active | `end`, for an interactive session or a console token | ended (`signed out`) |
| active | `end`, for an automation token | Denied; still active |
| active | `revoke` | ended (`revoked by sysop`) |
| active | `revokeForAccount`, `revokeForServer` | ended (the cause given) |
| active | revoked from another session or another server while a request is verifying | the two serialise on the row's hold; the next verification after the revocation, on any server, is Denied |
| active | two verifications at once, on this or another server | they serialise on the row; both succeed; at most one writes last use |
| ended | any input | Denied; ended is terminal |
| any | the connection lost during a verification | Unavailable; the request is not served |
| any | a verification passing its deadline | Unavailable; the request is not served |

An interactive session's idle limit moves with each `touch`; its expires at never moves. A
console token's expires at never moves; only its idle limit moves. An automation token has no
idle limit.

Sign-in attempt states:

| State | Input | Transition |
|---|---|---|
| awaiting | `consumeAttempt` with the right secret from the bound address before expires at | consumed |
| awaiting | `consumeAttempt` after expires at | expired, the failure counted and its entry written (check-then-act 6); Denied |
| awaiting | `consumeAttempt` with a wrong secret, or from another address | awaiting; Denied |
| awaiting | the connection that started it closes | awaiting until it expires; it may be consumed from another connection or server at the bound address |
| consumed | `consumeAttempt` again | Denied |
| expired | any | Denied |
| awaiting | `revokeForAccount` | expired |

Issue, for an automation token:

| Input | Outcome |
|---|---|
| a lifetime outside 1 to 365 days, change groups not within read groups, an unknown group, or a name outside its bounds | Invalid |
| a change group the automation ceiling refuses | Refused, naming the group |
| findings and no matching confirmation | Refused (confirmation required), with the findings; nothing created |
| findings and a matching confirmation | created; the entry records the confirmed findings |
| the same request identifier again from the same creator | Conflict, with the existing token's identifier; the secret is not shown again |
| two creations with one name at once | one created, one Conflict |
| the answer lost after commit | the token exists; a retry with the same request identifier answers Conflict with its identifier |

## Failure directions
Serves: ADV-002
| Failure | Direction |
|---|---|
| the database unreachable or past the deadline during a verification | Unavailable; the request is refused |
| a lifetime or idle setting stored invalid, so `get` answers the default | the smaller of the credential's own value and that answer; never beyond the fixed ceilings |
| access control errors on `list`, `revoke` or an automation `issue` | Denied |
| audit fails | the operation rolls back; nothing issued, ended or revoked |
| the caller's transaction fails after `revokeForAccount` or `revokeForServer` | nothing revoked, as nothing else in that transaction happened |

## Multi-node invariants
Serves: ADV-002
Credentials, console devices and sign-in attempts live only in the database. Nothing is cached:
every request is verified against the row, so a credential ended or revoked on one server is
refused at its next request on every server, with no dependence on the inter-server bus.

One scheduled job, the sweep, runs on every server at the sweep interval: it expires `awaiting`
attempts past their expiry, as check-then-act 6 states; it ends, by compare-and-set, `active` credentials past
their effective expiry or idle limit, with the cause; it deletes attempts, and `ended`
credentials, after the retention. Every step is a compare-and-set or a deletion whose predicate
is on the database clock, so any number of servers running it at once, or one server running it
twice, write the same result. A credential's end by the sweep is not an operator action and
records no entry; the next verification would have ended it the same way. An attempt's expiry
records its entry, because it is the only trace of a password that verified without a second
factor.

Counters: none that gate anything; lockout and slowdown counts are accounts v1's.

## Audit
Serves: ADV-002
Every entry carries the credential, source address and reached server fields audit v1 defines.

| Action | When | Before | After |
|---|---|---|---|
| `credential.issue` | every issue | none | kind, tool, account, issuing server, expires at; for `console`, the device identifier and key fingerprint; for `automation`, the name, read and change groups, lifetime and the confirmed findings |
| `console_device.add` | a console device inserted by an issue | none | device identifier, account, device name, key fingerprint, reported tier |
| `credential.end` | `end` | active | ended, `signed out` |
| `credential.revoke` | `revoke`, and each credential `revokeForAccount` or `revokeForServer` ends | active | ended, the cause, and for a sysop's revocation the revoking credential |
| `sign_in_attempt.expire` | an attempt expired without its second factor, or expired by `revokeForAccount` | awaiting | expired; the account, the tool, the bound source address, the cause |

No entry holds a secret, a verifier, an attempt handle or a signature.

## Configuration
Serves: ADV-002
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| `admin_api.session_idle_minutes` | 15 | sysop tunable; 5 to 60 (fixed backstops); settings group `credential lifetimes`, which this document declares closed to automation tokens; an increase is a loosening | board | live | runtime configuration tools |
| `admin_api.session_max_hours` | 8 | sysop tunable; 1 to 12 (fixed backstops); group `credential lifetimes`; an increase is a loosening | board | live | runtime configuration tools |
| `admin_api.console_token_hours` | 24 | sysop tunable; 0 to 168 (fixed backstops); 0 means no console token is issued; group `credential lifetimes`; an increase is a loosening | board | live | runtime configuration tools |
| console token idle limit | 24 hours | fixed policy backstop | fixed | n/a | not exposed |
| automation token lifetime | 1 to 365 days, chosen per token | fixed policy backstop | fixed | n/a | not exposed; chosen at creation |
| automation token lifetime offered by the tools | 90 days | calibration target | fixed | n/a | not exposed |
| secret length | 256 bits | fixed policy backstop | fixed | n/a | not exposed |
| name and device name | 1 to 64 printable characters | fixed policy backstop | fixed | n/a | not exposed |
| sign-in attempt lifetime | two minutes | fixed policy backstop | fixed | n/a | not exposed |
| last-use write coarsening | 60 seconds | fixed policy backstop | fixed | n/a | not exposed |
| sweep interval | 60 seconds | calibration target | fixed | n/a | not exposed |
| retention of ended credentials and attempts | 30 days | fixed policy backstop | fixed | n/a | not exposed |

## Security considerations
Serves: ADV-002
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| a bearer secret | a reader of the database, a backup or a log | use a credential | only the verifier is stored; secrets are never logged or audited; the comparison is constant-time | a wrong secret is Denied |
| a console token | whoever copies the console's files, or captures a request | replay it | the token has no bearer secret; every request is signed by the device key over its connection, which the database never holds | no valid signature, Denied |
| a presented identifier alone | anyone | keep a credential alive, or learn its use | nothing is written before the secret or signature verifies | Denied |
| a stolen credential after the account changes | whoever held it | keep access after a password or factor reset, a role loss, a permanent lock or a deletion | the owning features call `revokeForAccount` inside their own transaction; every request is verified against the row | the next request is Denied on every server |
| the issue operation | whoever holds a server's bootstrap record, trusted as a server | mint a credential with no sign-in that outlives the server or its secret | accepted as part of the trust a server login carries, as every database-side operation is; the credential records its issuing server, the entry names it, and removing the server or resetting its secret revokes every credential it issued | removal or reset revokes |
| a lifetime setting | a sysop by mistake | stretch every credential | lowering shortens issued credentials at once; raising is a loosening that needs confirmation and never lengthens issued ones; the fixed ceilings hold in the database whatever the setting; a setting stored invalid is read as the default, and the smaller of that and the credential's own value applies | the stored bound refuses the insert |
| an automation token | a reader of a script or CI secret | change the board | the credential ceiling, the groups fixed at creation, at most 365 days, never the `credential lifetimes` group | outside its ceiling or groups, Denied |
| sign-in attempts | a guesser of second-factor codes | many tries on one attempt, or from many addresses | one consumption per attempt, bound to its source address; each failure counted by accounts v1; two minutes | Denied |

## Negative tests
Serves: ADV-002
- `verifyBearer` with a wrong secret → Denied; last used at unchanged.
- `verifyConsole` with a signature from another key, over another message, or absent → Denied;
  last used at unchanged.
- `verifyBearer` presented with a console token's identifier → Denied.
- An interactive session used continuously → ended at created at plus `admin_api.session_max_hours`.
- An interactive session unused for its idle minutes → Denied, cause `idle`; a new session
  verified at once → active (last used at is set at issue).
- `admin_api.session_idle_minutes` stored invalid after a session was issued at 5 → the session
  still ends after 5 idle minutes, not 15.
- `end` called with an automation token → Denied; the token still active.
- `checkAttempt` with a wrong secret → false; nothing written.
- A console token used continuously → ended at created at plus `admin_api.console_token_hours`.
- A console token unused for 24 hours → Denied.
- `admin_api.console_token_hours` lowered to 0 → every console token Denied at its next request.
- `admin_api.session_max_hours` raised → credentials already issued keep their expiry.
- `issue`, the database-side operation, given an interactive lifetime of 13 hours, idle minutes
  of 61, a console lifetime of 169 hours, or an automation lifetime of 366 days → rejected by
  the database.
- A verification followed by a refused request → last used at unchanged; `touch` after a passed
  request → written.
- An attempt left to expire, with the sweep on two servers and a late consumption at once → one
  failure counted against the account and one `sign_in_attempt.expire` entry.
- A server's secret reset → every credential issued under it ended with cause `server secret
  reset`.
- `revokeForAccount` with an attempt awaiting → the attempt `expired` with one
  `sign_in_attempt.expire` naming the cause and no failure counted.
- A direct write of a credential, device or attempt row under a server login → rejected by the
  database.
- A credential revoked on server A → Denied at its next request on server B, with the bus
  disabled.
- `revokeForAccount` inside a transaction that then fails → every credential still active.
- `revokeForAccount` run twice → the second revokes nothing and writes no entry.
- A server removed → every credential whose issuing server it is Denied at its next request;
  credentials issued under other servers unaffected.
- `consumeAttempt` twice → the second Denied; from another address → Denied, the attempt still
  awaiting; after two minutes → Denied, state `expired`.
- `list` or `revoke` by an actor without `credentials.manage`, or with access control forced to
  error → Denied.
- `issue` of an automation token with access control forced to error → Denied; nothing created.
- `issue` of an automation token with `credential lifetimes` among its change groups → Refused;
  nothing created.
- `issue` of an automation token whose change groups hold a setting with a loosening rule, without
  a matching confirmation → Refused with the findings; nothing created.
- `issue` twice with one request identifier → one token; the second Conflict naming its
  identifier, with no secret.
- `issue` with audit forced to fail → nothing created.
- A scan of every credential, attempt and audit row, and every log line, after a test run → no
  secret, verifier, attempt handle or signature appears in any log line or entry, and no secret
  appears in any row.

## Revision history
- 2026-09-23: created for ADV-002.

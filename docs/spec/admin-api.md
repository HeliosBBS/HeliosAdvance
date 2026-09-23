# Admin API
Serves: ADV-002

## Purpose
Serves: ADV-002
The board's one network interface for administration: every administration tool reaches any
server of the board through it, and it decides who may try to sign in, from where, and where an
action runs. It owns the allow list, connection admission, the sign-in sequence, the per-request
pipeline, the remote-administration exposure and the relay of an action to another server. It is
not the public JSON API, owns no account, role, second-factor, lockout or credential state, and
never lets a tool reach the database.

## Terms
Serves: ADV-002
As the glossary defines them: Admin API, allow list, account #1, second factor, host
connection, local endpoint, source address, operator account, credential, settings group,
loosening finding, confirmation, relayed action, board signing key, board identifier, trusted
proxy list; access-control defines the credential ceiling. This document introduces:

- **admin listener**: the server's TCP listener for the Admin API (http v1's `admin`).
- **channel binding value**: 32 bytes unique to one connection: on the admin listener, the keying
  material exported per RFC 8446 section 7.5 with the label `EXPORTER-hadv-admin-v1`, an empty
  context and length 32; on the local endpoint, 32 bytes from the host's cryptographic random
  source, drawn when the connection opens and sent in every answer's `Hadv-Channel-Binding`
  header.
- **tool**: the administration program a credential is issued for, named by a lower-case word
  (`config`, `console`, or one a later feature declares); each tool has one permission,
  `tool.<tool>`, in access-control.
- **source class**: `host` for a host connection, `remote` for every other; a host connection's
  source address is the literal text `local`, which every field that stores a source address
  accepts.
- **action kind**: the name of an action a subsystem declares through `declareAction`.
- **sign-in principal**: the actor of a sign-in before any credential exists: the resolved
  account (or `unknown-account`), the tool, the source address, the source class and this
  server as the reached server.
- **remote exposure**: the set of pairs (account, entry) such that the entry admits the account,
  directly or through one of its roles, and second-factor v1 `requiredFor` answers no for the
  account.
- **remote-administration policy**: one row whose exclusive hold serialises every change that can
  alter the allow list's admissions or the remote exposure.
- **board mode**: whether the admin listener presents a chain signed by the board signing key
  (`board-signed`) or a publicly trusted chain (`public`); one mode for the whole board, as
  certificates v1 answers.

## Contracts
Serves: ADV-002
Provided, **admin-api v1**, external, to the administration tools (`hadv-config`,
`hadv-console` and the tools later features add, and their graphical counterparts).

**Transport.** HTTP/1.1 (RFC 9112) over TLS 1.3 (RFC 8446) on the admin listener, as http v1
states it; the same messages over HTTP/1.1 without TLS on the local endpoint; never HTTP/2
or HTTP/3. Every operation is `POST /v1/<operation>` with a JSON body (RFC 8259) of media type
`application/json`, answered with status 200 and a JSON object on success. A request whose
`Content-Type` is not exactly `application/json`, or that carries an `Origin` header or a
`Sec-Fetch-Site` header other than `none`, is `invalid` before anything else is read, so a web
page in a sysop's browser cannot send one; the tools send none of these. A body larger than
1 MiB is closed without an answer. `Forwarded`, `X-Forwarded-For` and `X-Real-IP` are never
read.

**Encodings.** Member names are lower-case with underscores. Identifiers (accounts, roles,
servers, credentials, entries, actions, devices) are strings of decimal digits. Times are RFC
3339 strings in UTC. Binary values are base64url without padding (RFC 4648 section 5). A public
key is the DER of its SubjectPublicKeyInfo (RFC 5280); a signature is the DER of the ECDSA
signature value (RFC 3279 section 2.2.3). A fingerprint is the SHA-256 (FIPS 180-4) of a DER
SubjectPublicKeyInfo, shown as 16 groups of 4 lower-case hexadecimal digits separated by
spaces. A message to be signed is the concatenation of its fields, each preceded by its length
in bytes as a 32-bit unsigned integer in network byte order; text fields are UTF-8. Revisions,
counts, sizes, days and page sizes are JSON integers. A setting's `value` is the JSON form of
its kind: an integer, a string, a boolean, or an array of these; an address, range or listen
address is a string in the notation its declaration names. The board identifier is a version 4
UUID (RFC 9562), written in lower case.

**Credentials on the wire.** A credential travels only in the `Authorization` header:
`HadvSession <presented form>`, `HadvAutomation <presented form>` (sessions.operator v1 states
the presented form), or `HadvConsole <credential identifier>` together with a `Hadv-Signature`
header holding the signature over the console request message (Behaviour D). A credential
anywhere else, or two, is Invalid, and its value is never logged.

**Errors.** Every error answers a JSON object `{"error", "reason", "message", "parameters",
"findings"}`:
`error` is one of `invalid` (status 400), `denied` (401 when the credential is absent or fails
verification, 403 otherwise), `not_found` (404), `conflict` (409), `refused` (422) or
`unavailable` (503); `reason` is a short code; `message` is text for a person; `findings` is a
list of findings, present with `refused` for `confirmation_required`, else empty; `parameters`
is an object of strings, empty unless a reason below names one. A finding is
`{"code", "subject", "parameters"}`, with `parameters` an object of strings. Every sign-in
failure, whatever its cause (unknown name, not admitted, wrong password, locked, source refused,
failed second factor, expired attempt, no tool permission), is `denied` with status 401 and
reason `sign_in_failed`; the audit entry holds the cause.

| Reason | Error | Meaning |
|---|---|---|
| `malformed` | `invalid` | the body, a member or a header fails its form or bounds; `parameters` names the member |
| `bad_request_origin` | `invalid` | the media type, `Origin` or `Sec-Fetch-Site` rule above |
| `credential_placement` | `invalid` | a credential outside `Authorization`, or two |
| `owner_set` | `invalid` | a key only its owner's operation writes; `parameters` names that operation |
| `sign_in_failed` | `denied` | any sign-in failure |
| `credential_rejected` | `denied` (401) | the credential failed verification |
| `not_permitted` | `denied` (403) | the permission, tool or ceiling refuses it |
| `not_admitted` | `refused` | the allow list no longer admits this account from this address |
| `confirmation_required` | `refused` | findings need a matching confirmation |
| `group_closed` | `refused` | an automation token's change group is closed to automation tokens; `parameters` names it |
| `revision_moved` | `conflict` | an expected revision is no longer the stored one |
| `name_in_use` | `conflict` | an active automation token has the name |
| `request_reused` | `conflict` | the request identifier was used; `parameters` holds `credential_id` or `action_id` |
| `no_such` | `not_found` | the named entity, key, group or action kind does not exist |
| `unavailable` | `unavailable` | the database or a consumed contract could not answer in time |

Operations. "Permission" is what Behaviour D asks access-control v1 for, with its target; the
credential kinds each operation can serve follow from the credential ceiling there and are not
a second check, except for `sign_out` and `action_status`, whose rules sessions and the relay
state. The members are the JSON body's; every member is required unless marked
optional.

| Operation | Permission (target) | Request members | Answer members |
|---|---|---|---|
| `identity` | none; served without a credential | none | `board_id`; `api_version` (the integer 1); `board_mode`; on the local endpoint only, `board_key_fingerprint` |
| `sign_in_begin` | none; served without a credential | `account_name` (1 to 64 characters); `tool`; `password` (1 to 1,024 bytes); `console_key` (optional: `public_key`, `device_name` 1 to 64 printable characters, `reported_tier` `hardware` or `os_protected`, `proof`, the signature over the message `hadv-console-issue-v1`, the channel binding value, the account name, the public key) | `result` `second_factor_required` with `attempt` (the presented form of the attempt handle), `method` (a lower-case word) and `challenge` (an object of strings, as second-factor v1 gives it; empty for a method that needs none); or `result` `granted` with the Granted members |
| `sign_in_complete` | none; served without a credential | `attempt`; `response` (1 to 1,024 bytes) | `result` `granted` with the Granted members |
| `sign_out` | none; sessions.operator v1 `end` decides which credentials may end themselves | none | none |
| `settings_list` | configuration v1 `list`'s gate | `group` (optional); `server` (optional) | `settings`: for each key configuration v1 `list` answers, `key`, `kind`, `scope`, `group`, `apply`, `default`, `value` (absent for a secret), `revision`, `invalid`, `secret`, `has_loosening_rule` |
| `settings_preview` | configuration v1 `preview`'s gate | `key`; `server` (optional); `value` | `findings`; `confirmation` |
| `settings_set` | configuration v1 `set`'s gate | `key`; `server` (optional); `value`; `expected_revision` (optional); `confirmation` (optional) | `value`; `revision` |
| `allow_list_get` | `settings.read` (`remote administration`) | none | `revision`; `host` (the text "this server's own host, through the local endpoint: every account, always admitted"); `entries`: each `id`, `match` (`kind`, one of `address`, `range`, `hostname`, and `value`, its text), `accounts` and `roles` (each an array of `id` and `name`), `label`, and for a hostname `resolved` (an array of address strings, empty when unresolved) |
| `allow_list_preview` | `settings.change` (`remote administration`) | `entries`: the whole new list, each `id` (absent for a new entry), `match`, `accounts` and `roles` (arrays of names), `label` | `findings`; `confirmation` |
| `allow_list_set` | `settings.change` (`remote administration`) | as `allow_list_preview`; `expected_revision`; `confirmation` (optional) | `revision` |
| `servers_list`, `servers_set_node_count`, `layout_preview`, `layout_apply`, `servers_remove` | `board.administer` | cluster.registry v1's inputs of listServers, setNodeCount, previewReplan, applyReplan, removeServer, less the actor, each in lower case with underscores | that operation's outputs, named the same way |
| `audit_list` | `audit.read` | `action`, `server`, `from`, `to`, `page_size`, `cursor`, each optional | `entries` (every field audit v1 defines, named the same way); `cursor` |
| `credentials_list` | `credentials.manage` | none | `credentials`: sessions.operator v1 `list`'s fields |
| `credentials_revoke` | `credentials.manage` | `credential_id` | `state` (`ended`) |
| `automation_preview` | `credentials.manage` | `name`; `read_groups`; `change_groups`; `lifetime_days` | `findings`; `confirmation` |
| `automation_create` | `credentials.manage` | as `automation_preview`; `request_id` (1 to 64 printable characters); `confirmation` (optional) | `credential_id`; `presented` (shown once); on Conflict for a reused request identifier, the error's `parameters` hold the existing `credential_id` |
| `action` | the action kind's declared permission | `server`; `kind`; `parameters` (an object whose encoding is at most 4 KiB); `request_id` | `action_id`; `result` `done` with `output` (an object the action kind declares, at most 4 KiB), `not_done` with `reason` (`server_not_live`, `timed_out`, `refused_by_target`, `failed`), or `outcome_unknown` |
| `action_status` | none; served only to the credential that requested it, else `not_found` | `action_id` | `state` (`pending`, `running`, `done`, `failed`, `abandoned`); `output` (when `done`); `failure_reason` (when `failed`: `refused_by_target`, `failed`, or `outcome_unknown` for both `outcome unknown` and `no outcome recorded`) |
| an operation a later feature declares | as declared | as declared | as declared |

The Granted members: `credential` (`kind`, `id`, `presented` for an interactive session,
`expires_at`, and `idle_minutes` for an interactive session); `account` (`id`, `display_name`);
`failures_since_last_sign_in` (`count`, and `addresses`, the most recent distinct ones, at most
20); `console_devices`, present when the account holds the Sysop role: sessions.operator v1
`devicesToShow` for this account and the credential this sign-in just issued, which is every console device holding an active console
token, and every device first seen since the earlier of this account's previous Admin API
sign-in and the start of the listing window, so no device whose token is alive, and no device
new since this account last looked, can be left out by any later sign-in; each `account_id`,
`device_name`, `key_fingerprint`, `first_seen_at`, `first_address`, `has_active_token`, and
`new_since_last_sign_in`.

**Tool obligations**, which the tools' negative tests hold them to:

- **First contact, `board-signed`.** The chain the admin listener presents is the server's leaf
  and the board signing key's certificate. The tool computes the fingerprint itself from the
  public key of the certificate that signed the leaf, shows that value, and sends no credential
  until the sysop confirms it equals the `board_key_fingerprint` that `hadv-config` shows from
  `identity` over the local endpoint on a server of the board. On confirmation it pins that key
  and the board identifier the leaf carries. It never shows a fingerprint a server sent over
  the network.
- **First contact, `public`.** The tool accepts the chain when it validates to a root the
  tool's platform trusts (RFC 5280) and names the address the sysop gave (RFC 9525), and
  records the board as `public` for that address.
- **Every later connection.** For a `board-signed` pin: the leaf must be signed by the pinned
  key, carry the pinned board identifier, be within its validity period and carry the
  server-authentication usage. For a `public` record: the chain must validate and name the
  address. Anything else, including a board that has changed mode, stops the tool with a loud
  warning; it sends nothing, and goes back to first contact only when the sysop chooses to.
- **Secrets.** The tool keeps an interactive session only in memory, never on disk, and calls
  `sign_out` when it closes. The command-line form reads a password and a second-factor response
  from the terminal, and an automation token from an environment variable or a file; given any
  of them as an argument it refuses to run.
- **Console key.** `hadv-console` generates its ECDSA P-256 key in the device's hardware key store
  where one is reachable, with the private key not exportable, else in the operating system's
  protected store, and reports which as the tier; where neither is available it sends no
  console key, and signs in at every launch. On the local endpoint it calls `identity` first,
  and takes the channel binding value from that answer's `Hadv-Channel-Binding` header before it
  signs its proof.
- **Pending changes.** A tool holding changes not yet applied when its session ends keeps them,
  signs in again, and applies them only when the new session's account identifier equals the
  old; otherwise it discards them and says so.
- **Loosening.** Before a change it asks for the preview; with findings it shows them as a loud
  warning and applies only after the sysop confirms, passing the confirmation. The command-line
  form fails, changing nothing, unless given `--acknowledge-loosening`, with which it prints the
  findings and applies.
- **Console devices.** At every Sysop sign-in a tool shows every device in `console_devices`,
  marking those new since the last sign-in and those holding an active token, before anything
  else.
- **The local endpoint.** Before sending anything on it, a tool checks with the operating
  system that the endpoint is served by the engine's service account, and refuses it otherwise,
  so a local program that took the endpoint's place first gets no password and shows no
  fingerprint.
- **The host line.** The allow list is shown with the host line first, marked as always admitted
  and offering no way to remove it.
- **An unknown outcome.** A tool shows `outcome_unknown` as unknown, never as not done, and
  offers `action_status` rather than a retry with a new request identifier.
- **A lost creation.** When `automation_create` answers Conflict for a reused request
  identifier, the tool says the earlier token's secret cannot be shown again and offers to
  revoke it and create another.
- **The user editor from the console.** Launched from `hadv-console`, it signs in on its own.

Provided to other subsystems:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| declareAction | at start-up only: action kind, permission name, whether the permission lies in the console ceiling, the handler (given the parameters and its deadline, it names the state it expects and returns a before and an after for the audit entry; then, checking the deadline immediately before acting, it acts or does not; then it returns a bounded output and one result: `done`; `state moved`; `failed`, meaning it did not act or acted with no effect; or `outcome unknown`, when it cannot know whether its effect happened) | none | Invalid (duplicate kind: a start-up defect; Fatal) |
| declareOperation | at start-up only: operation name, permission and how its target is taken from the request, whether the permission lies in the console ceiling, the request and answer members, the handler | none; an operation added this way is an addition within admin-api v1 | Invalid (duplicate name: Fatal) |
| withRemotePolicy | inside the caller's transaction, after the settings state and before any row the hold order places later: the change to make | the change made, with the remote exposure computed before and after it inside the hold, and the findings (every pair in the after set not in the before set, as `no_second_factor`, naming the account and the entry's match); when there are findings, configuration v1's confirmation rule applies to them, and a refused change rolls back; in its preview form the change is made, the findings and confirmation computed, and the transaction rolled back, so nothing is written | Refused (confirmation required), whatever the transaction reports |

Consumed: http v1 (`admission`, `certificate`, `channelBinding`, the admin listener and the local
endpoint); cluster.registry v1 and `leaseOf`; configuration v1 (`lockWithin`, `read`,
`setWithin`, the confirmation rule); access-control v1; audit v1; sessions.operator v1;
database-access v1; and these, stated here as the contract until the features that provide them
publish them:

| Contract | Operation | Inputs | Outputs | Errors |
|---|---|---|---|---|
| accounts v1 | resolve | account name | account, or none | Unavailable |
| accounts v1 | slowdown | source address (an IPv6 source keyed by its /64 prefix, here and in every source count; a host connection's count kept per server, keyed by `local` and the reached server), source class, reached server, surface `admin`; the exempt-source list never applies to the surface `admin`, so every source is slowed there | how long to wait before the next attempt from that source; or refused, with whether this is the first refusal of that source in the report window, decided by a compare-and-set on the database clock so one server reports it; for source class `host`, a wait never beyond the host-wait cap and never a refusal; for a remote source, a wait that would pass the sign-in wait bound is answered as refused | Unavailable |
| accounts v1 | accountWait | account, source class | reads only, writes nothing: the account wait, for account #1 only and for a remote source only, grown by failures from remote sources on any surface, never beyond the account-wait cap; none otherwise | Unavailable |
| accounts v1 | authenticate | inside the caller's transaction, whose first hold is the account's rows: account, password, source address, source class, reached server, surface `admin` | `Verified`, `Failed`, or `Refused` (locked, or source refused), always after the full password verification, so the time taken does not tell them apart; the board-wide lockout and source counts, one per account and one per source shared with every surface, updated in that transaction by a failure; `Verified` changes no count, only `recordSuccess` does; account #1 never locked, and slowed only as `accountWait` states; for source class `host`, never refused | Unavailable |
| accounts v1 | dummyVerify | a password | none; the same work `authenticate` does for a password, against no account | none |
| accounts v1 | recordFailure | inside the caller's transaction: account or none, source address, source class, reached server, reason | none; a failure with an account counts against the account and the source, without one against the source alone; the caller has already taken the account's rows and the source's count row, which accounts v1 names as its rows in the hold order | whatever the transaction reports |
| accounts v1 | recordSuccess | inside the caller's transaction: account, source address | the previous successful sign-in's time, and the failures since it (count, up to 20 distinct addresses) | whatever the transaction reports |
| accounts v1 | obligation | | every operation that changes an account's password, locks it permanently or deletes it takes the account's rows before any row the hold order places later, and calls sessions.operator v1 `revokeForAccount` inside that transaction; the rows accounts v1 owns take their holds after login rows and before relayed action rows | |
| rbac v1 | rolesOf | account | its roles | Unavailable |
| rbac v1 | membersOf | role | its accounts | Unavailable |
| rbac v1 | grants | role, permission | whether the role grants it; role 1, the Sysop role, grants every permission access-control lists for it | Unavailable |
| rbac v1 | obligation | | role 1 is fixed; no grant reaches `tool.config` for any other role; removing a role from an account takes the account's rows before any row the hold order places later, and calls `revokeForAccount` in the same transaction when the account no longer holds a `tool.<tool>` permission it held; every change to a role's members or to a role's second-factor requirement runs inside `withRemotePolicy`; its rows take their holds with accounts v1's | |
| second-factor v1 | requiredFor | account | yes or no | Unavailable |
| second-factor v1 | challenge | account, attempt | method (a lower-case word) and challenge (an object of strings; empty for a method that needs none) | Unavailable |
| second-factor v1 | verify | inside the caller's transaction: account, attempt, response | `Verified` or `Failed` | whatever the transaction reports |
| second-factor v1 | obligation | | enrolling, removing or resetting an account's second factor takes the account's rows before any row the hold order places later, calls `revokeForAccount` in the same transaction, and runs inside `withRemotePolicy`; second-factor v1 `verify` reads the factor under the account's hold its caller took, so it never judges against a factor being changed | |
| certificates v1 | boardIdentity | none | board identifier, board signing public key, board mode | Unavailable |
| certificates v1 | version | none | a number increased by every change to the board key, the board mode or any server's chain; admin-api compares it at each lease renewal and re-reads on a change | Unavailable |
| certificates v1 | adminChain | server | in `board-signed` mode, the server's leaf (its addresses and names, the URI subject alternative name `urn:uuid:` followed by the board identifier, which a tool compares byte for byte with the pinned value, the server-authentication usage, a validity of at most the leaf validity) and the board signing key's certificate; in `public` mode, the publicly trusted chain the sysop installed | NotFound, Unavailable |
| certificates v1 | obligation | | a removed server is never issued another leaf, so a removed server's leaf is honoured by pinned tools for at most the rest of its validity | |
| join v1 | obligation | | a pairing code is created only through an operation join v1 declares with `declareOperation`, permission `board.administer`, outside the console ceiling; the code records the creating account, and when the join completes addServer's gate judges that account as an interactive `config` operator account at that moment, so an account that has lost the Sysop role since cannot complete it | |

## Data model
Serves: ADV-002
**The allow list**, the value of the setting `admin_api.allow_list`, changed only through
`allow_list_set`: a list of entries, each with an entry identifier unique within the list (from
the list's own counter), exactly one match (an IPv4 or IPv6 address literal; an address range in
prefix notation, RFC 4632 or RFC 4291; or a hostname, RFC 1123, at most 253 characters, no
wildcard, not an address literal), the accounts and the roles it admits (at least one between
them), and a label. Accounts and roles are held by identifier, resolved from names when the entry
is saved. Addresses are compared as `cluster.trusted_proxies` states for an IPv4-mapped IPv6
address. A loopback address or range is allowed, and is the way to admit a tunnel that ends on
the server. The host line is not an entry.

**Remote-administration policy**, exactly one row, enforced by a uniqueness constraint on a
fixed key: a revision, increased by every change made under its hold.

**Relayed action**:

| Field | Meaning |
|---|---|
| action ID | increasing identifier, the key |
| target server, target generation | the server, and its lease generation read when the action was requested |
| action kind, parameters | as declared |
| requested by (credential), request identifier | unique together |
| requesting server, source address | |
| requested at, deadline | database clock; the deadline is requested at plus the action deadline |
| state | `pending`, `running`, `done`, `failed`, `abandoned` |
| output, failure reason, finished at | the failure reason: `state moved` when the handler found the state it named had moved; `failed` when it did not act, or acted with no effect; `outcome unknown` when it cannot know whether its effect happened (Unavailable, or its deadline passing mid-effect); `no outcome recorded` for the sweep's |

Check-then-act operations, each one transaction taking holds in the architecture's hold order:

1. **`allow_list_set`**: configuration v1 `lockWithin` (the settings state), then
   `withRemotePolicy`, inside which: the stored revision compared with `expected_revision`
   (Conflict when it moved); the findings of Behaviour E computed; configuration v1
   `setWithin`; the policy revision increased. The entry is configuration's `setting.change`,
   with the confirmed findings.
2. **A change to a role's members or second-factor requirement, or to an account's second
   factor**: the owning feature's operation inside `withRemotePolicy`, as its obligation states.
   Every change that can alter the remote exposure takes the one hold, so none is judged against
   a state another is changing.
3. **Request an action**: insert a `pending` row with the target's current generation, unless
   (credential, request identifier) exists, in which case the existing row is the answer; also
   when the target is the requesting server. Two identical first requests race on the
   uniqueness constraint; the loser's Conflict re-reads the existing row and answers as a retry
   does.
4. **Claim an action** (target server): compare-and-set `pending` to `running` where the database
   clock is before the deadline and the target generation equals the claiming server's current
   generation, and the audit entry `admin.action.started` with the handler's before and intended
   after, in one transaction that commits before the handler acts.
5. **Finish an action** (target server, after the handler): compare-and-set `running` to `done`
   or `failed` with the output, and the entry `admin.action.finished`, in one transaction.
6. **Abandon an action** (the requesting server at the deadline, or the sweep past it): compare-and-set `pending` to
   `abandoned`. Exactly one of claim and abandon wins.

Every one of these writes is a database-side operation; a server login's direct write to a
relayed action or the policy row is refused by the database.

## Behaviour
Serves: ADV-002
**A. Admission of a connection**, before any TLS byte is parsed, through http v1 `admission`:

| State | Input | Transition |
|---|---|---|
| accepted, local endpoint | the engine's check of the connecting account finds the service's account or an administrator | host connection; channel binding value drawn |
| accepted, local endpoint | any other account, or the check cannot complete | close |
| accepted, local endpoint | first bytes a PROXY protocol signature | close |
| accepted, admin listener, peer outside the trusted proxy list | the peer address, before any byte is read | the source address is the peer; → source known |
| accepted, admin listener, peer inside the trusted proxy list | a PROXY header (version 1: `PROXY ` then at most 107 bytes in all; version 2: the 12-byte signature `0D 0A 0D 0A 00 0D 0A 51 55 49 54 0A`, at most 512 bytes in all) with a TCP over IPv4 or IPv6 source, within the header deadline | source address from the header |
| accepted, admin listener, peer inside the trusted proxy list | no header, a malformed or oversized one, an `UNKNOWN` or `LOCAL` command, a family mismatch, or the header deadline passes | close |
| source known | the source (an IPv6 source counted by its /64 prefix) already holds the per-source connection limit on this server | close with nothing read; counted as refused |
| source known | no entry's addresses contain the source address (this server's snapshot and resolved hostnames), whoever the entry admits | close with nothing read; the refused-connection counter increases; one log line, through the limiter |
| admitted | first bytes a PROXY signature, or anything but a TLS handshake record | close; counted as refused |
| admitted | a TLS 1.3 handshake with the chain certificates v1 `adminChain` gives this server, as http v1 states it | serving |
| admitted | the handshake fails, or passes its deadline | close |
| any | the peer disconnects | nothing to undo; nothing was issued |
| any | the allow list changes on this or another server | the next connection uses the reloaded snapshot; requests on open connections are re-checked in D |
| any | two connections from one source at once with one place left under its limit | one admitted, one closed |

Only the local endpoint makes a host connection; a loopback TCP peer is an ordinary source
address. No byte is read from a peer outside the trusted proxy list until its address is
admitted.

**B. Sign-in**. The actor of every step is the sign-in principal; audit v1 `record` takes the
source address and reached server from it, access-control v1 answers its tool-permission check
with no credential ceiling, and sessions.operator v1 `issue` records it as the actor. `sign_in_begin` and `sign_in_complete`
first reload the snapshot when the allow
list's stored revision differs from it, as D step 4.

| State | Input | Transition |
|---|---|---|
| start | `sign_in_begin` | accounts v1 `slowdown` for the source class and address: refused: `denied` (`sign_in_failed`), counted and logged through the limiter, and the entry `admin.sign_in.source_refused` only when `slowdown` reports it as the first for that source in the report window; a wait: waited out, outside any transaction; a remote source whose wait would pass the sign-in wait bound is refused by `slowdown` itself, as above, with its report-window entry |
| waited | the name | resolve it; accounts v1 `accountWait` for the account (account #1's, from a remote source, capped) waited out outside any transaction; on a host connection the account is admitted; otherwise it is admitted only if an entry whose addresses contain the source address admits the account or one of its roles (rbac v1 `rolesOf`) |
| waited | no such account, or not admitted | `dummyVerify` of the password; in one transaction, holding this source's count row, `recordFailure` against the source alone and the entry `admin.sign_in.refused` (reason `not admitted`); `denied` (`sign_in_failed`) |
| admitted | the password | one transaction, whose first holds are the account's rows and this source's count row, and which runs on through the tool check and to `startAttempt` or to granting: accounts v1 `authenticate`; on `Failed` or `Refused` the entry `admin.sign_in.failed` or `admin.sign_in.refused` with the cause, committed, and `denied` (`sign_in_failed`) |
| verified | access-control v1 `authorize(account, tool.<tool>)` | Denied (`not held`): in that transaction `recordFailure` (reason `no tool permission`, against the source alone) and `admin.sign_in.refused`, committed; `denied` (`sign_in_failed`). Denied (`could not complete`): rolled back; `unavailable`, with no count and no entry |
| permitted | a console key present | the proof verified over this connection's channel binding value; invalid: in the begin transaction, which holds the account's rows and this source's count row, `recordFailure` against the account and `admin.sign_in.failed`, committed; `denied` (`sign_in_failed`) |
| permitted | second-factor v1 `requiredFor` is yes | sessions.operator v1 `startAttempt`, bound to this source address and, for a host connection, to this server; the challenge answered; → awaiting second factor |
| permitted | `requiredFor` is no | → granting |
| awaiting second factor | `sign_in_complete` | sessions.operator v1 `checkAttempt`, without a hold on the attempt (an expiry it finds takes check-then-act 6's holds): the handle's secret compared in constant time, the bound address, the state and the expiry; a wrong secret, another address or another state: `denied` (`sign_in_failed`) with no second-factor work, no count and no entry, the attempt unchanged; expired: the expiry path below |
| awaiting second factor | the handle checked | the admission of the account `checkAttempt` answered re-run for this source; then one transaction, holds in the architecture's order: the account's rows and this source's count row, then sessions.operator v1 `readAttempt` (every writer of an attempt holds its account first, so the read is stable); no longer `awaiting`: `denied` with no second-factor work and no count; now expired: `readAttempt` has run the expiry path alone; still `awaiting`: second-factor v1 `verify`, then `consumeAttempt`; `Failed`: `recordFailure` against the account, `admin.sign_in.failed`, the attempt consumed (one response per attempt), committed, then `denied`; `Verified`: → granting in the same transaction; a `consumeAttempt` that fails rolls back everything, `verify`'s writes included |
| awaiting second factor | the attempt expired, found by `checkAttempt`, at consumption or by sessions' sweep | the expiry's own transaction records the failure against the account and its entry, once per attempt, as sessions states, and commits even though the answer is `denied` |
| granting | | in the same transaction, holds continuing in the architecture's order (the account's rows, then the attempt, then the console device, then the credential): `recordSuccess`; sessions.operator v1 `issue`, a console token when the tool is `console`, a console key is present and `admin_api.console_token_hours` is above 0, else an interactive session, with the lifetime and idle minutes this server's snapshot holds; the entry `admin.sign_in.succeeded`; the Granted members answered |
| any | concurrent sign-ins for one account from other connections or servers | independent; the counts are accounts v1's, in the database |
| any | the database, or a consumed contract, unavailable or past its deadline | `unavailable`; no credential issued |
| any | the client disconnects before the answer | whatever committed stands; an issued credential it never received ends at its idle limit |

A console signing in with `admin_api.console_token_hours` at 0, or without a console key,
receives an interactive session for the tool `console`, which it keeps only in memory.

**C. Hostname entries**, on each server:

| Input | Outcome |
|---|---|
| the snapshot loaded, or an entry's cache at the refresh point | resolve A and AAAA as a validating stub resolver (RFC 4033, 4034, 4035) from the root trust anchors shipped with the engine, through the host's configured resolvers with the DNSSEC-OK bit; each query has its deadline |
| a secure answer, or a provably insecure (unsigned) one | the addresses are used; cache time is the smallest TTL in the answer, clamped |
| a bogus or indeterminate answer, a timeout, a server failure, a name that does not exist, or no addresses | the entry matches nothing until a later resolution succeeds |
| the cache time passes without a successful refresh | the entry matches nothing |
| a connection arriving while an entry is unresolved | the entry matches nothing; admission never waits for a resolution |
| the answer changes | the next request from an address no longer contained is refused in D |
| two refreshes of one entry at once on one server | one runs; the other waits for its result |
| a refresh finishing after a newer snapshot replaced its entry | its result is discarded |
| the same entry refreshed on two servers | independent; each server judges its own connections |

The refresh is a background task of the admin-api service on each server, owned by it,
stopped when the process drains, and writing nothing to the database.

**D. Every request carrying a credential**:

| Step | Input | Outcome |
|---|---|---|
| 1 | the connection | the source address and whether it is a host connection, fixed at admission |
| 2 | the request | parsed within its bounds; else `invalid`, or closed past the body bound |
| 3 | `HadvSession`, `HadvAutomation` | sessions.operator v1 `verifyBearer`, which writes nothing but the end of an expired or idle credential; failure: `denied` (`credential_rejected`) |
| 3 | `HadvConsole` | sessions.operator v1 `verifyConsole` over the message `hadv-console-request-v1`, the credential identifier, the channel binding value, the method, the request target and the SHA-256 of the body, likewise; failure: `denied` (`credential_rejected`) |
| 4 | the allow list's stored revision differs from this server's snapshot's | the snapshot reloaded, and its hostnames resolved as C states, before going on |
| 5 | not a host connection | an entry whose addresses contain the source address must admit the credential's account or one of its current roles; else `refused` (`not_admitted`), one log line through the limiter, and the credential's last use untouched |
| 6 | | access-control v1 `authorize` for the operation's permission and target, with the operator account (its account and credential) as the actor; the tool permission and the credential ceiling are applied inside the check |
| 7 | | sessions.operator v1 `touch`, then the operation, whose own transaction writes its audit entry; the actor carries the credential, the source address and this server as the reached server, which audit v1 `record` takes from it |
| any | a step cannot complete (Unavailable, a deadline passed, no answer) | the request refused |
| any | the credential revoked on another server while this request runs | the verification and the revocation serialise on the credential's row; a request verified first completes; the next is `denied` |
| any | the client disconnects mid-request | the operation's transaction completes or rolls back on its own; nothing else changes |
| any | the same request sent twice | as the operation states: a change with an expected revision is `conflict` (`revision_moved`) the second time; an automation token's creation is `conflict` (`request_reused`); an action is answered as F states |

A request without a credential is served only for `identity`, `sign_in_begin` and
`sign_in_complete`.

**E. Findings of an allow-list change**, computed inside `withRemotePolicy` from the list before
and after, for entries added and for the added part of entries widened (a narrowing, a removal or
a change of label alone has none):

| Change | Finding |
|---|---|
| an account or role admitted from an address it was not admitted from before (addresses and ranges compared exactly; hostname entries by name) | `admits`, naming the account or role and the match |
| such an entry's range: an IPv4 prefix shorter than /29 or an IPv6 prefix shorter than /48 | `wide_range`, whose text names shared addresses and carrier-grade NAT; a range overlapping 100.64.0.0/10 adds `shared_address_space` |
| such an entry admitting role 1 | `every_sysop`, whose text says every present and future Sysop-role account is admitted from the match |
| such an entry's match a loopback address or range | `loopback`, whose text says any process on the server that can open a TCP connection may try to sign in |
| the remote exposure grown | `no_second_factor`, as `withRemotePolicy` gives it |

**F. A relayed action**:

| Where | Input | Transition |
|---|---|---|
| requesting server | the action authorised in D | an existing row for (credential, request identifier): with the same kind, server and parameters, its outcome (waiting as the first request did while it is `pending` or `running`, then `outcome_unknown` with its identifier); with any of them different, `conflict` (`request_reused`, `action_id`). No row: cluster `leaseOf(target)`: not live → `not_done` (`server_not_live`), entry `admin.action.not_done`, and no row, so a later request with that identifier is new; live → Data model 3, a notification to the target, a wait until the deadline |
| target server | a notification, or its poll | Data model 4 for each `pending` row addressed to it; a claim lost does nothing |
| target server | a claim committed | the handler runs under a deadline ending the handler margin before the row's deadline plus the further wait, guarded by the state it named: when that state has moved it does nothing and fails with `state moved`; when its deadline has passed before it acts, it does not act and the finish records `failed`; then Data model 5 |
| target server | Data model 5 fails (audit or database) | the row stays `running`; the sweep sets it `failed` with an entry once the deadline and the further wait have passed |
| requesting server | a terminal state before the deadline or during the further wait | `done` with the output; `not_done` with `refused_by_target` for the failure reason `state moved`, or `failed` for `failed`; `outcome_unknown` for `outcome unknown` or `no outcome recorded` |
| requesting server | the deadline, row still `pending` | Data model 6; won: `not_done` (`timed_out`), entry `admin.action.not_done`; the target can never claim it |
| requesting server | the deadline, row `running` | a further wait for a terminal state; then `outcome_unknown` with the action identifier, which `action_status` answers later |
| target server | restarted since the request (a new generation) | its claim fails; the requester's abandon wins |
| target server | its lease lost while `running` | the sweep sets the row `failed` with an entry once the target's lease is not live |
| requesting server | the tool disconnects while waiting | nothing changes; the row completes, or the sweep abandons it at its deadline |
| any | the same request identifier again from the same credential | as the first row of this table; the action runs at most once |
| requesting server | the target is itself | the row is inserted and claimed by this server at once; the same steps |

The sweep, on each server at the poll interval, abandons `pending` rows past their deadline,
writing `admin.action.not_done` (reason `timed_out`, with the requesting credential and source
from the row), sets
`running` rows whose target's lease is not live or whose deadline and further wait have passed
to `failed` with the entry `admin.action.finished` (state `failed`, "no outcome recorded"), and
deletes finished rows after the retention; each step is a compare-and-set on the database clock.

## Failure directions
Serves: ADV-002
| Failure | Direction |
|---|---|
| the database unreachable or past the deadline | every request on this server, sign-in included, is `unavailable`; admission of connections continues from the snapshot, so only admitted addresses see the refusal |
| accounts v1, rbac v1, second-factor v1 unavailable | sign-in `unavailable`, no credential issued; a request needing `rolesOf` refused; an unknown second-factor requirement is never taken as "not required" |
| the local endpoint's check of the connecting account fails | close |
| the local endpoint's name already held by another program when the engine starts | the local endpoint does not open and the log names the holder; the admin listener is unaffected |
| DNS, or DNSSEC validation | that entry matches nothing; other entries unaffected |
| the trusted proxy list unreadable | treated as empty: a proxy's connections, carrying a header, are closed |
| certificates v1 without a chain for this server, or an expired one | the admin listener does not start and the log says why; the local endpoint still serves the host |
| audit fails | the operation rolls back; for a relayed action, a failed claim means no execution |
| the inter-server bus | nothing here depends on it; the relay's notification only shortens the wait before the poll |
| the target of a relayed action not live or too slow | `not_done` or `outcome_unknown`; never reported done without a `done` row |
| the refusal log limiter saturated | lines dropped and counted, with one summary line a minute; the counter still increases |

## Multi-node invariants
Serves: ADV-002
The allow list and its revision, the policy row and every relayed action live only in the
database, as do credentials (sessions). Every request re-checks its credential and its admission
against the database's current revision, so a change made on one server is enforced at the next
request on every server.

| Cache or counter | Where | Invalidation |
|---|---|---|
| allow-list snapshot, with its revision | per server | reloaded at the settings-version check of each lease renewal, and on any request or sign-in that finds a newer stored revision |
| hostname resolution cache | per server | Behaviour C; past its cache time the entry matches nothing |
| trusted proxy list | per server | configuration's snapshot rule |
| certificate chain, board key and board mode | per server | reloaded at start and whenever certificates v1 `version` has moved at a lease renewal |
| channel binding value | per connection | ends with the connection |
| connections per source | per server | counted on accept, released on close; bounds this server's sockets, not a board-wide gate |
| refused-connection counter | per server, from process start | never reset while running; a measurement, not a gate |
| refusal log limiter | per server | a one-minute window |

Jobs: the relay sweep (Behaviour F), idempotent because each step is a compare-and-set or a
deletion on the database clock; the hostname refresh, local to each server and writing nothing.

## Audit
Serves: ADV-002
Every entry an Admin API request causes carries the source address and the reached server audit
v1 defines, and the credential when one was verified; a sign-in's entries take them from the
sign-in principal, and an expired attempt's from the attempt's bound address. A name typed at sign-in that resolves to no account is never
recorded; the actor is then `unknown-account`. No entry, and no log line, holds a password, a
second-factor response, a secret, an attempt handle or a signature, and request bodies are never
logged.

| Action | When | Before | After |
|---|---|---|---|
| `admin.sign_in.succeeded` | a credential issued at sign-in | none | tool, credential kind and identifier, second-factor method or none |
| `admin.sign_in.failed` | a wrong password, a failed second factor, an invalid console proof | none | tool, reason |
| `admin.sign_in.refused` | not admitted, locked, no tool permission | none | tool, reason |
| `admin.sign_in.source_refused` | the first sign-in from a refused source in a report window | none | the source address |
| `admin.action.started` | the claim, before the handler acts | the state the handler expects | the action kind, parameters and the handler's intended after |
| `admin.action.finished` | the finish, or the sweep's failing of a `running` row | the state the handler expected | the state after, or the failure reason |
| `admin.action.not_done` | the requesting server finds the target not live, or it or the sweep abandons a `pending` row | none | action kind, target server, reason |

A change to the allow list is configuration's `setting.change`, carrying the confirmed findings.
Refused connections are counted and logged within the limit, not audited.

## Configuration
Serves: ADV-002
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| `admin_api.allow_list` | empty: the host only | sysop tunable; the entry rules in Data model; settings group `remote administration`, which this document declares and an automation token may change; owner-set, changed only through `allow_list_set`; its loosening rule is Behaviour E, so an automation token that may change the group is warned about it at creation | board | live | runtime configuration tools |
| action deadline, and the further wait for a running action | 10 seconds each | calibration target | fixed | n/a | not exposed |
| handler margin: how long before the sweep's cut-off a handler's deadline ends | 5 seconds | fixed policy backstop | fixed | n/a | not exposed |
| relay poll and sweep interval | one second | calibration target | fixed | n/a | not exposed |
| relayed action retention | 30 days | fixed policy backstop | fixed | n/a | not exposed |
| action parameters and output | at most 4 KiB each | fixed policy backstop | fixed | n/a | not exposed |
| hostname query deadline | 2 seconds | fixed policy backstop | fixed | n/a | not exposed |
| hostname cache time | the answer's smallest TTL, clamped to 30 to 300 seconds | fixed policy backstop | fixed | n/a | not exposed |
| hostname refresh point | 80 % of the cache time | calibration target | fixed | n/a | not exposed |
| allow-list bounds | 256 entries, 32 hostname entries, 32 accounts and roles per entry, labels of at most 64 printable characters | fixed policy backstop | fixed | n/a | not exposed |
| wide-range thresholds | IPv4 shorter than /29, IPv6 shorter than /48 | fixed policy backstop | fixed | n/a | not exposed |
| request and answer body bound | 1 MiB | fixed policy backstop | fixed | n/a | not exposed |
| PROXY header bounds | 107 bytes (version 1), 512 bytes (version 2) | fixed policy backstop | fixed | n/a | not exposed |
| connections per source on the admin listener | 8, an IPv6 source counted by its /64 prefix | fixed policy backstop | fixed | n/a | not exposed |
| admin leaf validity (certificates v1's obligation) | at most 30 days | fixed policy backstop | fixed | n/a | not exposed |
| sign-in wait bound | 10 seconds | fixed policy backstop | fixed | n/a | not exposed |
| account #1's account-wait cap, and the host-wait cap | 5 seconds each, well below the header and idle deadlines | fixed policy backstop | fixed | n/a | not exposed |
| console-device listing window | 7 days, the console token ceiling | fixed policy backstop | fixed | n/a | not exposed |
| source-refused report window | 15 minutes: at most one `admin.sign_in.source_refused` entry per source | fixed policy backstop | fixed | n/a | not exposed |
| channel binding value | 32 bytes | fixed policy backstop | fixed | n/a | not exposed |
| addresses reported with the failures since the last sign-in | at most 20 | fixed policy backstop | fixed | n/a | not exposed |
| name and response bounds at sign-in | account name 1 to 64 characters; password and second-factor response 1 to 1,024 bytes; device name 1 to 64 printable characters; request identifier 1 to 64 printable characters | fixed policy backstop | fixed | n/a | not exposed |
| refused-connection logging | 10 lines a minute and one summary line, per server | calibration target | fixed | n/a | not exposed |

`admin_api.listen` is http's; the session and token lifetimes are sessions'.

## Security considerations
Serves: ADV-002
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| the admin listener, facing the internet | anyone | scanning, password guessing, attacking code before sign-in | the address stage runs before any TLS byte is parsed; the allow list is empty by default, so only the local endpoint is admitted | no entry contains the address: close |
| the admin listener's connections | anyone at an admitted address, a shared one included | hold every connection and shut the sysop out | at most 8 connections per source on each server, an IPv6 source counted by its /64, beside http's per-listener limit | past the limit: close |
| the source address | a direct connector | claim an allowed address | a PROXY header believed only from the trusted proxy list, and required from it; forwarding headers never read; a PROXY header from anyone else closes the connection | close |
| the local endpoint | a local account that is not the service's or an administrator's, a program tricked into connecting to loopback, a remote client, or a local program that takes the endpoint's place first | act as the host, which admits every account and is never refused; or collect a sysop's password | host status comes only from the local endpoint, which the operating system restricts to the host and to the service and administrators, never reachable over a network and never shared by name; the engine checks the connecting account, and a tool checks the endpoint's serving account before it sends anything; loopback TCP is an ordinary address, admitted only by an entry with its own warning | close |
| account admission, and the sign-in answers | someone at an address allowed for another account | try that account's password, or learn which accounts exist, are admitted or are locked | the account is checked against the matching entries before the password; every failure that reaches the name answers the same, after the same work and the same wait, except account #1's capped account wait, and a refused source is answered at once; the tool permission is checked before the second factor | refused before the password |
| a sign-in attempt | someone who has the password | guess second-factor codes from many addresses, or under the host's never-refused class, or stop at the second factor unseen | an attempt is bound to its source address; one response per attempt; each failure, and each attempt left to expire, counted against the account and audited | `denied` |
| hostname entries | whoever controls the DNS or its path | point a name at their own address | DNSSEC validated where signed; bogus or indeterminate answers match nothing; cache times clamped; sign-in still required | the entry matches nothing |
| first contact | anyone between the tool and the board | take the password and second factor | public chain with a name match; or the fingerprint computed by the tool from the key that signed the leaf, compared with the host's, and the key pinned; no credential sent before | the tool stops and sends nothing |
| a leaf certificate | whoever takes a server's leaf key, or holds a removed server's | impersonate every server to pinned tools | the leaf must be within its validity, at most 30 days, and a removed server is never issued another | past its validity, the tool stops |
| a decrypting balancer | its operator, or anyone who owns it | read or alter administration | its certificate is not signed by the pinned key | the tool stops |
| TLS early data | anyone on the path | replay a bearer request | http v1's admin listener closes a connection that offers early data | close |
| a web page in the sysop's browser | its author | send sign-ins from the sysop's admitted address to lock the sysop or a co-sysop out | only `application/json` without `Origin`, and without a `Sec-Fetch-Site` other than `none`, is read | `invalid` |
| unadmitted connections | anyone on the internet | hold the admin listener's connections | an unadmitted peer is closed with nothing read; each source, IPv6 by /64, holds at most 8 | close |
| password guessing, lockout as a weapon | anyone admitted | guess, or lock staff out | accounts v1's board-wide policy with one count; the host slowed, never refused; account #1 never locked but slowed by its own count; exempt sources get no exemption here; a not-admitted name counts against the source only | refused past the threshold |
| a console token | whoever copies the PC's files, or captures a request | replay | every request signed over its connection's channel binding value; the key not exportable where the hardware allows | `denied` |
| live malware on the sysop's PC | a local attacker | drive an open console | accepted: the credential ceiling limits a console token to console actions | n/a |
| loosening changes | a sysop by mistake | open access without seeing it | findings computed by the engine under the policy hold, bound into the confirmation, recorded in the entry; the command line needs its flag; a tool that confirms on its own is exposed by the entry, not stopped | nothing changes without a matching confirmation |
| the remote exposure | a sysop changing a role or an account's second factor | leave an admitted account without a second factor unseen | every change that can grow the exposure runs under the policy hold and needs its confirmation | nothing changes without it |
| a relayed action | a slow or dead target | a late, phantom or unaudited execution | claimed only before the deadline and with the requested generation, its entry committed before the handler acts; abandoned can never run | `not_done` |
| the database | anyone on a tool's path | reach the database | no tool holds a database login; only the engine does | no path |

## Negative tests
Serves: ADV-002
Admission:
- A TCP connection from an address no entry contains → closed before any TLS byte is read; the
  counter increases; past ten in a minute, no further line but the summary.
- With an empty allow list → a remote connection and a loopback TCP connection closed; a
  local-endpoint connection by an administrator reaches sign-in.
- A local-endpoint connection by an account that is neither the service's nor an
  administrator's → closed; the check forced to error → closed.
- A connection to the local endpoint from another host → refused; a second endpoint instance of
  the same name created by another account → refused by the operating system.
- A tool pointed at a local endpoint served by an account other than the engine's service
  account → sends nothing.
- Another account creating the local endpoint before the engine starts → the engine's local
  endpoint does not open and the log names it.
- A Sysop sign-in with a console device new since the last one → the tool shows it, marked new,
  before anything else.
- A peer outside the trusted proxy list sending a PROXY version 1 header, or a version 2 header,
  from an admitted address → closed.
- A trusted proxy's connection with no header, an `UNKNOWN` or `LOCAL` header, a family mismatch,
  an oversized header, or a header late past its deadline → closed.
- `X-Forwarded-For`, `X-Real-IP` and `Forwarded` naming an allowed address, from an address no
  entry contains → the connection never reaches HTTP.
- The trusted proxy list forced unreadable → a proxy's connection with a header closed.
- Nine connections from one admitted source → the ninth closed; a connection from another
  admitted source still admitted.
- 64 silent connections from addresses no entry contains → each closed with nothing read; an
  admitted source still connects.
- Nine connections from nine addresses in one IPv6 /64 admitted by an entry → the ninth closed.

Hostname entries:
- The resolver timing out; a bogus signed answer; an indeterminate answer; NXDOMAIN → the entry
  matches nothing.
- A cache past its time with its refresh failing → the entry matches nothing.
- A connection arriving before a new hostname entry resolves → closed at once, not held.
- A hostname entry's address changed → the next request from the old address, on a session
  already signed in, `refused`.

Sign-in:
- An account not admitted by the entry containing the address → `denied`, the accounts v1 test
  double observes no `authenticate` call and one `dummyVerify`, and the answer's time is within
  the same bound as a wrong password's.
- An unknown name, a locked account, a wrong password → the same `denied` answer, each within the
  same time bound as a wrong password's; the typed unknown name in no entry or log line.
- A refused source sending 1,000 sign-ins in a minute → one `admin.sign_in.source_refused`
  entry for the window, the rest counted and logged within the limiter, no other entry.
- Repeated right passwords with wrong second-factor codes for a co-sysop → the account locks as
  accounts v1 sets; for account #1, slowed and never locked.
- A sign-in stopped at `second_factor_required` → when the attempt expires, one failure against
  the account and its entry.
- An account with a second factor and without `tool.config`, signing in for `config` with its
  right password → `denied` before any second-factor step; no challenge answered.
- accounts v1 `authenticate` forced unavailable → `unavailable`; nothing issued.
- second-factor v1 `requiredFor` forced unavailable → `unavailable`; never treated as not
  required.
- rbac v1 `rolesOf` forced unavailable → a sign-in `unavailable`, a request with a credential
  refused.
- `sign_in_complete` twice for one attempt → the second `denied`.
- `sign_in_complete` with a right identifier and a wrong secret, and any response → `denied`;
  the second-factor `verify` test double never called; no count moved; the attempt still
  `awaiting`.
- Failures against account #1 from 100 addresses in one IPv6 /64, and from 100 unrelated
  addresses → the /64 refused past the source threshold as any source; each unrelated address
  slowed by account #1's capped account wait; account #1 never locked; a sign-in from a fresh
  admitted address with the right password succeeds within the cap.
- Failures from an address on the exempt-source list → slowed on the Admin API as any other
  source.
- 10,000 failures against account #1 over Telnet, then its sign-in through the local endpoint and
  from an admitted remote address with the right password → each succeeds within the cap.
- A console device added, then two further sign-ins of that account, then another Sysop's
  sign-in → the device is listed.
- With the fake clock: a device first seen on day 0 and re-issued a token on day 6, then a Sysop
  sign-in on day 10 → listed; a device unused for 20 days that signs in again → listed while its
  token lives.
- Failures past the threshold at server A's local endpoint → server B's host sign-in unslowed;
  10,000 host failures on one server, then a host sign-in there → succeeds within the cap.
- The sweep expiring an attempt while `sign_in_complete` for the same account runs → no abort;
  one failure counted.
- Two concurrent completions of one right handle → one granted; no failure counted.
- A password change held open between a begin's `authenticate` and its attempt, then released →
  no credential of the account active afterwards.
- A second-factor reset and a `sign_in_complete` for one account, each held until the other is
  observed waiting → no credential issued on the old factor active afterwards.
- A password change while an attempt awaits → the attempt `expired`, one `sign_in_attempt.expire`
  with the cause, no failure counted; the later completion `denied`.
- rbac v1 forced unavailable at the tool check on a host connection → `unavailable`; no count, no
  entry.
- A remote source whose wait would exceed the sign-in wait bound → refused at once, with one
  `admin.sign_in.source_refused` entry for the window.
- Two identical first `action` requests at once → one row, one execution, both answered its
  outcome.
- `sign_in_complete` from an address other than the one the attempt began from → `denied`; the
  attempt unchanged.
- An allow-list entry removed on server A, then `sign_in_begin` on server B from that address
  before B's next lease renewal → `denied` as not admitted, B having compared the stored
  revision.
- Host failures past the source threshold → slowed, never refused; a remote source past it →
  `denied`.
- A console key proof over another connection's channel binding value → `denied`; nothing
  issued.
- A sign-in forced down every failure path, then a scan of every log line and audit entry → no
  password and no second-factor response appears.
- `authenticate` answering `Failed` with the audit insert forced to fail → neither the failure
  count nor the entry is written.

Requests:
- A console request signed over another connection's channel binding value, or over another
  body → `denied`.
- A request with `Content-Type: text/plain`, or with an `Origin` header, or with
  `Sec-Fetch-Site: cross-site` → `invalid`; no count or entry moves.
- A stolen session presented from an address not admitting its account → `refused`; last used
  at and last used address unchanged.
- An automation token calling `sign_out` → `denied`; the token still active.
- A console token asking `servers_list`, whose operation permission `board.administer` the
  Sysop role holds but the console ceiling excludes → `denied`.
- An automation token asking `credentials_list`, `automation_create`, `audit_list` or
  `servers_remove` → `denied`.
- An automation token calling `allow_list_set` with `remote administration` among its change
  groups → applied after its confirmation; without that group → `denied`.
- A credential in the query string, or two credentials → `invalid`; the value in no log line.
- The database forced unreachable → sign-in and every request `unavailable` on that server.
- Each step of D forced to error in turn → the request refused.

Findings and the hold:
- An allow-list entry with no accounts and no roles → `invalid`.
- An entry added, or a range widened, without a matching confirmation → `refused` with the
  findings; nothing written.
- A label changed alone → no finding.
- A confirmation taken before a concurrent allow-list change → `refused` or `conflict`; nothing
  written.
- An entry admitting role 1 → the `every_sysop` finding.
- A loopback entry → the `loopback` finding.
- An entry admitting an account without a second factor → the `no_second_factor` finding.
- A role's second-factor requirement turned off, an account moved into a role without one, or an
  account's second factor removed (test doubles for rbac v1 and second-factor v1) while an entry
  admits it → the `no_second_factor` finding; without confirmation nothing changes.
- An allow-list change holding the policy while a role change waits on it (the test holds the
  first transaction open until the second is observed waiting) → the second, once it runs, sees
  the first's result in its findings.
- The command-line tool without `--acknowledge-loosening` on a change with findings → exits with
  failure; nothing changed.

Relayed actions (a test-only action kind the harness declares):
- The target not live → `not_done`; the handler never runs, later or at all.
- A row abandoned at its deadline → never claimed.
- The target restarted after the request → the handler does not run.
- The same request identifier twice, to another server or to the requesting server itself → one
  execution; the second after the target has stopped → the first outcome, not `not_done`.
- The claim's audit entry forced to fail → the handler never acts.
- The finish's audit entry forced to fail → the row stays `running`, then the sweep sets it
  `failed` with its entry; `action_status` never answers `done`.
- A test-only handler that finds its deadline passed before acting → does not act; the row
  `failed`.
- The target's lease forced to lapse mid-handler → the tool is answered `outcome_unknown`, never
  `not_done`.
- A retry with the same request identifier and different parameters → `conflict`
  (`request_reused`) naming the first action; after a `server_not_live` answer, a retry is a new
  request.
- A handler finding its expected state moved → `not_done` (`refused_by_target`).

Tools (against the tool binaries):
- A server presenting a leaf signed by another key with the real board's `identity` relayed →
  the fingerprint the tool shows is the other key's; after the sysop declines, nothing sent.
- A chain not signed by the pinned key, carrying another board identifier, expired, or without
  the server-authentication usage → the tool stops and sends no credential.
- A publicly trusted chain presented where a key is pinned, or a board-signed one where the board
  was recorded `public` → the tool stops.
- An interactive session → never found on disk after the tool runs; `sign_out` observed when the
  tool closes.
- A password or token passed as an argument → the tool refuses to run.
- Pending changes after a session ends and a different account signs in → discarded; nothing
  applied.
- The allow-list screen and listing → the host line first, with no remove action.

## Revision history
- 2026-09-23: created for ADV-002.

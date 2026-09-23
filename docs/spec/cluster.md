# Cluster
Serves: ADV-001

## Purpose
Serves: ADV-001
One board on many servers: what a server is, how it proves it is alive, how node numbers are
laid out across servers and taken by callers, what every server sees of every other, and
what a server does when it cannot reach the database. Membership, liveness and capacity are
one consistency domain, so they have one owner. It is not the caller surfaces, not session
handling, and not the tools: it gives them contracts.

## Terms
Serves: ADV-001
As the glossary defines them: lease, generation, layout, layout position, high-water mark,
re-plan, occupancy rule, screen boundary, local lease deadline, reconcile, trusted proxy
list, management listener, public listener, node handle, caller reference, applied change,
data-model change.

## Contracts
Serves: ADV-001
Provided:

**cluster.nodes v1**, to the caller surfaces (Telnet, SSH, web):

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| admitting | none | whether the server accepts callers (true only in Serving) | none |
| freeNodesCached | none | free nodes on this server as of the last read-back, or `unknown` before the first | none |
| callersOnlineCached | none | callers online across the board as of the last read-back, or `unknown`; for a theme's pre-login display | none |
| claim | a session identifier from sessions v1, the surface | a node handle | Refused (not admitting; the lease is not live; sessions v1 does not vouch for the session as logged in, or cannot answer), Exhausted (no free node; a Refused with that reason), Unavailable |
| handle.checkpoint | at every screen boundary | `continue`, or `end` with the message to show | none |
| handle.release | none; idempotent | none | Unavailable (queued; retried after every successful renewal) |
| releaseSession | a session identifier | none; idempotent; matches on the identifier alone | Unavailable (queued as above) |

The surface's obligations: call `admitting` on accept and, if false, show the theme's
"not accepting callers" screen and close; consult `freeNodesCached` on accept and, if it is
zero (not `unknown`), show the busy screen and close without a database read; call `claim`
at login and on Exhausted show the busy screen and close; on Unavailable from `claim` show
the "not accepting callers" screen, close, and call `releaseSession` with the same identifier
so a claim that committed without a reply is cleared; call `checkpoint` at every screen
boundary; call `release` when the session ends, as sessions v1 defines a session's end for
each surface. `claim` itself confirms through sessions v1 that the session is logged in and
takes the caller reference from that answer, so no surface can take a node before login;
per-account limits on concurrent sessions are sessions v1's and are applied before a claim.

**cluster.whosOnline v1**, to menus and tools: `list(viewer)` → rows of node number, server
ID, server display name, caller display name (resolved through sessions v1 from the caller
reference; a node whose name cannot be resolved is listed without one), surface, claimed at;
ordered by node number; the nodes occupied under the occupancy rule, read from the database
on every call. Gate: `whos_online.view` through access-control v1. Errors: Denied,
Unavailable (the menu shows "who's online is not available"). The viewer is an input of the
contract.

**cluster.registry v1**, to the setup tool, the runtime configuration tools and join v1. Each
operation is gated through access-control v1 as its row says; each state-changing operation
records its audit entry through audit v1.

| Operation | Gate | Inputs | Outputs | Errors |
|---|---|---|---|---|
| createBoard | `board.create`, on the connection `openWith` opened with the administrator credential | board name, first server's display name, node count, HTTP connection limit (default 256), transport, address, trust-anchor fingerprint, the key-encryption key identifier | server ID, range, the first server's login name and secret (returned once, to be written into the record) | Denied, Invalid, Refused (a board exists), Conflict (a concurrent first run), Unavailable |
| addServer | `board.administer`, on behalf of join v1 | display name, node count, HTTP connection limit (default 256), transport, address and trust-anchor fingerprint the new record will hold | server ID, range, the login name and secret join v1 created | Denied, Invalid, Conflict (name taken), Refused (node numbers exhausted), Unavailable |
| listServers | `board.administer` | none | per server: ID, name, status, lease live, engine version, host facts, transport and address as stored at last admission, range, node count, nodes in use, HTTP in use and limit, restart needed | Denied, Unavailable |
| setNodeCount | `board.administer` | server, count, expected layout version | range | Denied, Invalid, NotFound, Conflict (layout changed), Refused (nodes in use; re-plan needed; node numbers exhausted), Unavailable |
| previewReplan | `board.administer` | none | proposed ranges, affected nodes, the occupied ones among them, layout version | Denied, Unavailable |
| applyReplan | `board.administer` | expected layout version | ranges | Denied, Conflict, Refused (nodes in use), Unavailable |
| removeServer | `board.administer` | server, the server ID typed again | none | Denied, Invalid (mismatch), NotFound, Refused (already removed; the last active server; the server whose login carries this operation), Unavailable |
| markStarted | none: not an operator action; the engine calls it once per process | the settings version of the first snapshot | none | Unavailable |

createBoard recovers a first run whose record write failed: when a board exists whose first
server has never acquired a lease, and the caller presents the same key identifier, address
and transport that were stored, it returns the same server ID with a new secret (through
join v1 `resetSecret`) and records `board.recover`; any other input while a board exists is
Refused. Starting and stopping a server are the host's service manager's operations, run by
the local operator directly or through the setup tool; no board operation stops a server.
`cluster.node_count` is not a registry setting: the Server detail screen reads it from
listServers and changes it through setNodeCount.

**cluster.health v1**, external, over HTTP/1.1 (RFC 9112), body encoded as JSON (RFC 8259):
`GET /health` on the management listener returns the detailed form when the connection's own
peer address is inside an entry of the trusted proxy list, else the minimal form; the same
path on the public listener returns the minimal form always. Only the peer address is used
(http v1 reports nothing else); no database is read.

| Form | Body | HTTP status |
|---|---|---|
| minimal | `status` (string): `up` or `down` | 200 for `up`; 503 for `down` |
| detailed | `status` (string): `up`, `full` or `down`; `server_id` (integer); `engine_version` (string, `major.minor.patch` in decimal); `lease_live` (boolean); `nodes_in_use`, `node_count`, `free_nodes` (integers, absent before the first read-back); `http_in_use`, `http_limit` (integers, the public listener); `as_of_seconds` (integer, absent before the first read-back) | 200 for `up` and `full`; 503 for `down` |

`status` is `up` in Serving with a free node, `full` in Serving with none (the minimal form
says `up`), `down` in every other state. `lease_live` is true in Serving, in Degraded before
the local lease deadline, and in Draining. Counts are as of the last read-back (acquisition
or renewal); `as_of_seconds` is the server's own clock since it.

Consumed: database-access v1; access-control v1; configuration v1 (`read` inside acquisition,
`initWithin` and `setWithin` inside createBoard and addServer, `get` for the trusted proxy
list and the timeout); audit v1; http v1; sessions v1 (as access-control states it); theme
v1 and join v1, whose operations this document states as the contract until their providing
features publish them:

| Contract | Operation | Inputs | Outputs | Errors |
|---|---|---|---|---|
| theme v1 | busyScreen | the surface | the screen to show | NotFound, Invalid |
| theme v1 | notAcceptingScreen | the surface | the screen to show | NotFound, Invalid |
| join v1 | createLogin | inside a caller's transaction: server ID | a login name bound to that server ID, and its secret | Conflict, Unavailable |
| join v1 | disableLogin | inside a caller's transaction: server ID | none | NotFound, Unavailable |
| join v1 | revokeLogin | server ID | none; ends the login's open connections and removes it; idempotent | Unavailable |
| join v1 | resetSecret | inside a caller's transaction: server ID | a new secret | NotFound, Unavailable |
| join v1 | listLogins | none | every login created through join v1 with its server ID | Unavailable |
| join v1 | property | | the key-encryption key and the new server's record travel to a joining host only over the paired channel join v1 owns, never through the database | |

When a theme screen fails, a fixed built-in line ("All nodes are busy. Please call again
later." or "This server is not accepting callers.") is shown and the connection still ends.

## Data model
Serves: ADV-001
**Board**, exactly one row, enforced by a uniqueness constraint on a fixed key; its exclusive
hold is the cluster mutex.

| Field | Meaning |
|---|---|
| key | the one fixed value |
| name | the board's name |
| minimum engine version | major and minor; the oldest engine version the data model admits (see Behaviour, version rule) |
| layout version | increased by every layout change |
| high-water mark | the highest node number ever assigned; 0 on an empty board |
| next layout position | the board's counter, taken under the mutex at a server's first range assignment; the only source of layout positions |
| key identifier | the key-encryption key's identifier, stored at creation; join v1 and createBoard's recovery compare against it, and an acquisition whose record carries another identifier is Refused ("wrong board key") |

**Server**, never deleted; the row lease renewal writes.

| Field | Meaning |
|---|---|
| server ID | increasing identifier, the key; never reused because rows are never deleted |
| display name | 1 to 32 code points (fixed backstop), no control characters |
| normalised name | the display name in Unicode canonical composed form with default case folding (the Unicode Standard, version 15.1); set while active, empty when removed; a uniqueness constraint where set makes names unique among active servers |
| status | `active`, `removing` (removed, revocation pending), or `removed`; `removed` is terminal |
| lease generation | increased at each acquisition |
| lease expires at | database clock, or empty |
| lease timeout used | the timeout written at the last renewal |
| engine version | written by acquisition; read by admission's version check |
| operating system, processor architecture | informational, written at acquisition; never branch behaviour |
| transport, database address, trust-anchor fingerprint, login name, record version | as the record held them at the last admission, or as createBoard and addServer stored them; compared at acquisition |
| started settings version | written once per process by `markStarted` |
| HTTP in use reported, reported at | written by each renewal, for the tools |
| removed at, removed by | set once |

**Layout**, one row per server that has ever been assigned a range; the row layout
operations hold.

| Field | Meaning |
|---|---|
| server ID | the key |
| node count | 0 up to the node-number backstop |
| range start, range end | the start is anchored at assignment and kept through every count change; when the count is 0 the range is empty and the end equals start − 1 |
| layout position | unique; the order re-plan packs in; assigned at creation |

**Node**, one row per assigned node number; a shrink deletes the rows it drops.

| Field | Meaning |
|---|---|
| node number | the key; at most the node-number backstop |
| owner | the server |
| occupant session, occupant caller, occupant surface | set together or empty together |
| claim generation | the owner's lease generation at claim time |
| claimed at | database clock |

Constraints: a node number lies within its owner's range (the layout operations are the
only writers of owner and ranges); a uniqueness constraint on the occupant session where it
is set, so one session identifier occupies at most one node.

**Applied change**, one row per data-model change applied to the database: change ID
(increasing identifier), the engine version that shipped it, applied at.

Check-then-act operations, each one transaction taking holds in the global order (board,
settings state, server rows by ID, layout rows by server ID, setting rows, node rows by
number):

1. **Acquire lease** (Admitting, and every renewal interval in Fenced): shared hold on the
   board row, then exclusive hold on the own server row; Refused if the record's key
   identifier differs from the board's; the version check (Behaviour, version rule) runs here,
   against the other active servers' live leases as read under the hold, and a refusal is
   Refused; succeed only if active and the lease is empty or expired; compare the record's
   transport, address, trust-anchor fingerprint, login name and record version (from
   `recordFields`) with the stored values, and if any differs write `server.record.change`
   (actor: the local operator of this server; before and after; a secret change is named,
   never valued) before overwriting them; if this is the first acquisition of a process,
   write `server.start`; read the lease timeout through configuration v1 `read` (the default
   if unset); read the own layout row; increase the generation; write expiry = now + timeout,
   the engine version and the informational fields; clear the occupant fields of every own
   node row, in ascending order; read back what renewal reads back. A live lease held by
   anyone makes it Conflict. If an audit write fails, the acquisition fails.
2. **Renew lease** (every renewal interval in Serving, Degraded and Draining): compare-and-set
   on the own server row matching own ID, own generation, active, and expiry later than now;
   write expiry = now + timeout and the reported HTTP fields (the public listener). In the same
   transaction read back: the minimum engine version, the settings version, own status, own
   count and range from the layout row, own occupied count under the occupancy rule, the
   board's occupied count, the lowest and highest engine versions among other active servers
   with live leases, the IDs of servers in `removing`, and the logins join v1 lists that match
   no active or removing server. When no rows matched, read back own status all the same, and
   "own status not active" takes precedence over "renewal matches nothing". A Conflict from
   contention is retried within the interval; Unavailable at the deadline is the "database
   Unavailable" input. Renewal never waits on a layout operation: it holds only the server
   row and reads the layout row without holding it. The operation is bound to the bootstrap
   record's identity, and the database refuses a write naming another server's ID. After
   every successful renewal the process retries its queued releases, runs reconcile, completes
   any pending removal it read back (operation 7's second step, one transaction per target,
   holding that target's server row only, with its own operation deadline), and revokes,
   through join v1, any login that matches no active or removing server, recording
   `login.revoke` for each.
3. **Claim node**: shared hold on the own server row to confirm the lease is live at the own
   generation (else Refused, and the process takes the "renewal matches nothing" input);
   choose the lowest own node number that is free under the occupancy rule; compare-and-set
   its occupant fields and claim generation with the predicate "owned by this server and
   free under the rule"; on a Conflict, choose the next; after as many attempts as the
   server's node count, Exhausted. A claim waits on a row a layout operation holds, bounded by
   the operation deadline. The claim names no node number, so a claim outside the own range
   cannot be expressed, and the predicate refuses any row another server owns.
4. **Release**: compare-and-set clearing the occupant fields where the session identifier
   matches (and, for a handle, the node number too); zero rows is success.
5. **Layout operations** (createBoard, addServer, setNodeCount, applyReplan, removeServer):
   the cluster mutex; then, for createBoard and addServer, the settings state row; then, for
   createBoard, addServer and removeServer, the server row created or removed; then the
   layout rows involved in ascending server ID; then the affected node rows in ascending
   number; never the server row of a server that keeps running. Each re-reads state after
   taking the mutex; occupancy is read under the exclusive holds on the affected node rows,
   so a claim that lands between the mutex and those holds is seen; each clears the occupant
   fields of every node row whose owner changes, increases the layout version, and records
   its audit entry. setNodeCount and applyReplan refuse when an affected node is occupied and
   compare the expected layout version, failing with Conflict if it moved; removeServer
   records the occupied nodes and does not refuse on them. createBoard creates the settings
   state row through configuration v1 `initWithin`; createBoard and addServer create the
   server's login through join v1 `createLogin`, store its name, and write the server's
   `http.connection_limit` through configuration v1 `setWithin` (one `setting.change`
   entry).
6. **Drain** (a host stop, and any Fatal while a lease is held and the database is
   reachable): compare-and-set on the own server row matching own ID and own generation:
   expiry = now; then clear own node rows whose claim generation is the own generation;
   record `server.stop` with its cause: `host stop` (actor: the local operator of this
   server) or the Fatal's reason (actor kind `engine`). Zero rows on the first step means a
   successor holds the lease; do nothing further. A Fatal runs this at once and goes to
   Refused without entering Draining.
7. **Remove server**, in two steps. First, operation 5 with: Refused if the target is the last
   active server, or is the server whose login carries this transaction; status `removing`;
   the node rows deleted; the lease cleared; the normalised name cleared; every login join v1
   lists for that server disabled through `disableLogin` in the same transaction; the audit
   entry. Second, in its own transaction after any server's renewal reads back the target in
   `removing`: `revokeLogin` for each of its logins, then status `removed`; retried until it
   succeeds. `listServers` shows `removing` until it is done.

Layout rules:

- **Create board / add**: range start = high-water mark + 1; the mark advances to the new
  range end; the layout position comes from the board's counter. Refused with "node numbers
  exhausted" if the new end would exceed the node-number backstop.
- **Set node count, shrink**: drop the tail of the own range and delete the dropped node rows,
  down to an empty range at count 0; the range start and the position are kept; the mark
  does not move; the freed numbers are not reassigned until a re-plan.
- **Set node count, grow**: only if the range's end equals the high-water mark (an empty
  range whose start − 1 equals the mark included); then extend in place and advance the
  mark. Otherwise Refused with "re-plan needed": a range is never moved except by a re-plan.
- **Re-plan**: pack every active server's range from node 1 upward in layout-position order
  with its configured count; the mark becomes the last assigned number. A node number is
  affected if its owner differs before and after or it ceases to exist; refused, listing the
  occupied affected nodes, if any is occupied. Unaffected rows are not touched. A re-plan
  that changes nothing writes nothing and records no entry.
- **Remove**: the range is retired: its numbers stay unassigned until a re-plan.

## Behaviour
Serves: ADV-001
**Version rule.** Versions are ordered by major then minor; a server's version is "one step
above" another's when it is the next minor of the same major or the first minor of the next
major. A server is admitted when its version is at least the board's minimum engine version
and within one step, above or below, of every other active server holding a live lease,
checked inside the acquisition transaction (operation 1) at every acquisition (with no other
such server, any version at or above the minimum is admitted). A data-model change that
older engines cannot use raises the minimum to at most the lowest version among active
servers with live leases at the moment it runs, or to the running server's own version when
it is alone; a server whose version is below the minimum is refused and told the version
required; a running server that finds the minimum raised above its version drains.
Data-model changes run after the version check, by an admitted server, under the cluster
mutex, each recorded as an applied change and never applied twice. Rolling upgrades therefore
walk the board forward one step at a time.

**Process states**, after database-access has opened the connection:

| State | Accepting callers | Meaning |
|---|---|---|
| Admitting | no | version checked, changes applied, lease acquired, snapshot loaded, listeners opened (once per process) |
| Serving | yes | lease live, database reachable |
| Degraded | no | database unreachable; sessions end at their next screen boundary; health `down` |
| Fenced | no | the local lease deadline passed or the lease was found lost; every session has been ended; acquisition is attempted each renewal interval |
| Draining | no | ordered to stop; sessions end at their next screen boundary, bounded by one lease timeout |
| Stopped | no | terminal; exits with the code the service manager does not restart |
| Refused | no | terminal; exits with the code the service manager does not restart, naming the reason; any Fatal (database-access, http, configuration) maps here, running operation 6 first when a lease is held and the database is reachable |

A crash exits with any other code, which the service manager restarts.

**Host stop**: the host's service manager asks the process to stop, directly or through the
setup tool. No board operation stops a server; the drain records the stop.

| State \ input | renewal or acquisition succeeds | renewal matches nothing | database Unavailable | Conflict on renewal or acquisition | host stop | own status found not active | minimum raised above own version | duplicate process with this identity | invalid: a Fatal from any subsystem | concurrent from another session on this server (an operator action) |
|---|---|---|---|---|---|---|---|---|---|---|
| Admitting | own status not active → Refused; version outside window → Refused; acquired → Serving | n/a | stay; retry each renewal interval | a live lease held → wait one renewal interval and retry; still held after the duplicate-process wait → Refused ("already running elsewhere") | Stopped | Refused | Refused | as Conflict | Refused | none possible before admission |
| Serving | refresh settings if the version moved; update cached counts; stay | end every session now → Fenced | → Degraded | retry within the interval; at the deadline treat as Unavailable | → Draining | end every session now → Refused ("removed") | → Draining | cannot acquire or renew; never disturbs this one | operation 6 → Refused | a setting, count or layout change: applied at the next renewal's read-back |
| Degraded | reconcile; → Serving | as Serving | at the local lease deadline: end every remaining session → Fenced; else keep retrying | as Serving | → Draining | as Serving | → Draining | as Serving | → Refused (no drain possible) | observed on recovery |
| Fenced | → refresh settings, update counts → Serving (listeners stay open) | n/a | keep retrying each renewal interval | acquisition finds a live lease → keep retrying; after the wait → Refused | Stopped | Refused | Refused | as Conflict | Refused | observed on re-acquisition |
| Draining | every session ended, or one lease timeout elapsed → drain (operation 6) → Stopped | end every session now → Stopped | at the local deadline end every session → Stopped without writing | retry within the interval | ignored | end every session now → Refused ("removed") | continue draining | as Serving | → Refused without writing | observed at the next renewal |

Renewal keeps running in Serving, Degraded and Draining; acquisition is attempted in Fenced.
A removed server whose connection is still open reads its status as not active at its next
renewal and reaches Refused ("removed"); one whose connection was lost first is rejected at
login and reaches Refused through database-access's Fatal. Both are the same terminal state.

**Suspend**: a server whose clock shows a gap longer than the lease timeout since its last
successful renewal or acquisition treats its lease as lost at its next checkpoint or renewal
(the "renewal matches nothing" input), because a paused host may have been declared expired
while it slept.

**Sessions ending after their current screen**: the next `checkpoint` returns `end` with the
message; a session waiting for input ends at the local lease deadline if no input arrives
first; a web session ends at its next request or at its end as sessions v1 defines it.

**Node states**, under the occupancy rule:

| State | Input | Transition |
|---|---|---|
| unassigned (no row) | a layout operation assigns it | → free |
| free | a claim by its owner's session | → occupied |
| free | a claim from another server | impossible: the predicate refuses it |
| free | a layout operation removes or reassigns it | → unassigned, or free under the new owner |
| occupied | release with the matching session | → free |
| occupied | release with another session | unchanged; zero rows |
| occupied | the owner's lease expires | → free at once, everywhere |
| occupied | the owner is removed | row deleted |
| occupied | a layout operation would move it | the operation is refused (setNodeCount, applyReplan) |
| occupied | the owner's next acquisition | → free (occupant cleared) |
| stale (occupant set, free under the rule) | the owner's next acquisition or claim | cleared or overwritten |
| any | a claim that times out after committing | the surface's `releaseSession` clears it at the next renewal |

**Reconcile** (on Degraded → Serving, and after every successful renewal): clear the occupant
fields of every own node row whose session identifier is not in this process's live handles,
with the predicate "owned by this server, that session identifier, this generation"; retry
every queued release. A second run finds nothing to do.

## Failure directions
Serves: ADV-001
| Dependency | Failure | Direction |
|---|---|---|
| database, on a renewal or acquisition | Unavailable, or the connection lost | Degraded: refuse callers; sessions end at their next screen boundary; at the local deadline all end; resume on the first successful renewal or acquisition with no operator action |
| database, on any other operation | Unavailable | returned to that caller; the process state does not change |
| lease | lost or expired | closed toward freeing capacity: sessions end, nodes are free under the rule, acquisition gets a new generation |
| access control | error | Denied |
| trusted proxy list | unparseable at `set` | Invalid; a stored list that cannot be parsed is treated as empty |
| theme screens | missing or fail | the built-in line; the connection still ends |
| audit | fails | the operator action, or the acquisition writing `server.record.change`, rolls back |
| join v1 | disabling the login fails | the removal is Refused; revoking fails after commit → retried at every server's renewal until it succeeds |
| sessions v1 | cannot resolve a display name | the node is listed without one |
| own clock | a gap longer than the timeout | the lease is treated as lost |

## Multi-node invariants
Serves: ADV-001
Only in the database: servers, status, leases, layout, occupancy, the minimum version, applied
changes. Process-local, never truth: live session handles (added before a claim is attempted,
removed after release or after an Unavailable claim); queued releases; the local lease
deadline; the cached counts.

| Cache | Invalidation |
|---|---|
| own count, range, occupied count, free count, board callers online, lowest other version | replaced by every read-back (acquisition and renewal); `unknown` before the first; `as_of_seconds` exposes the age |
| the minimum engine version | replaced by every read-back |
| who's-online | none: read on every call |

Jobs: renewal and acquisition (a compare-and-set or a guarded acquire; a duplicate tick
extends to the same or a later time, or finds the lease live); reconcile and queued releases
(clear to the same empty state); pending revocations (a second server finds the login already
revoked); data-model changes (recorded, never applied twice). There is no reaper: an expired
server's nodes are free under the occupancy rule at the instant of expiry.

## Audit
Serves: ADV-001
| Action | When | Before | After |
|---|---|---|---|
| `board.create` | createBoard | empty | board name, first server's name, count, range, HTTP limit, transport, address |
| `server.add` | addServer | empty | name, count, range, HTTP limit, transport, address |
| `server.remove` | removeServer, first step | name, `active`, range, occupied node numbers | `removing` |
| `server.node_count.change` | setNodeCount | count, range | count, range |
| `layout.replan` | applyReplan that changes anything | every active range | every active range |
| `server.stop` | the drain that follows a host stop or a Fatal | lease state | drained; the cause |
| `server.start` | the first acquisition of a process (actor: the local operator) | empty | engine version |
| `server.record.change` | acquisition finding the record's transport, address, trust-anchor fingerprint, login name or record version changed | those fields (a secret change named, never valued) | those fields |
| `board.recover` | createBoard returning an existing first server | server ID | new secret issued |
| `login.revoke` | a renewal revoking a login that matches no active or removing server | login name | revoked |

The HTTP connection limit is a setting and its changes are audited by configuration as
`setting.change`. Refused operations change nothing and write no entry.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| `cluster.node_count` (a Layout field, not a registry key; changed only by setNodeCount) | 4 | sysop tunable; 0 up to the node-number backstop | server | live | runtime configuration tools; setup tool at first run and join |
| `cluster.lease_timeout_renewals` | 3 | sysop tunable; 2 to 10 (fixed backstops: below 2 one late write drops a healthy server, above 10 a dead server's callers stay listed too long); applied at the next renewal | board | live | runtime configuration tools |
| `cluster.trusted_proxies` | empty | sysop tunable; a list of address ranges in prefix notation (RFC 4632 for IPv4, RFC 4291 for IPv6), no names; an IPv4 peer arriving as an IPv4-mapped IPv6 address (RFC 4291 section 2.5.5.2) is compared as IPv4 | board | live | runtime configuration tools |
| lease renewal interval | five seconds | calibration target | fixed | n/a | not exposed |
| node-number backstop | 2,147,483,647 | fixed policy backstop | fixed | n/a | not exposed |
| draining bound | one lease timeout | fixed policy backstop | fixed | n/a | not exposed |
| version skew window | one step above or below every other active server | fixed policy backstop | fixed | n/a | not exposed |
| duplicate-process wait | one lease timeout plus one renewal interval | calibration target | fixed | n/a | not exposed |

Tool screens: Servers (listServers, restart-needed flags); Server detail (count with the
resulting range or refusal, HTTP limit, transport and address as stored, remove with typed
confirmation); Layout (previewReplan; apply disabled while any affected node is occupied,
listing them); Board (lease timeout in renewals with the resulting seconds, trusted proxy
list). The setup tool's offering is access-control's.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| node claims and leases | a misconfigured server, or a duplicate process | exhaust numbers, keep a lease it should not | ranges assigned only by layout operations under the mutex, from configured counts, bounded by the backstop; a claim names no number; renewal and drain are compare-and-sets on own identity and generation; a duplicate cannot acquire a live lease | out-of-range or stale-generation claim Refused; zero-row renewal ends sessions; zero-row drain does nothing |
| listeners | an anonymous flooder | take every node | a claim is Refused unless sessions v1 vouches for the session as logged in; a connection while the cached free count is zero is turned away without a database read; per-account concurrent sessions are bounded by sessions v1 before a claim | at the limit, refuse |
| health | an anonymous mapper | learn fullness and timing | detail only on the management listener from a peer inside the trusted proxy list; the public listener says up or down; only the peer address is consulted; no database read | empty or unparseable list means minimal |
| who's-online | an anonymous caller | count per-server fullness | gated on `whos_online.view` | Denied on any error |
| registry | a caller without the permission | change the board | every state-changing operation gated through access-control v1 | error means Denied |
| first run | anyone who can run the setup tool against an empty database | create a board and its first login | `board.create` for the local operator; the administrator credential is supplied once and never stored or logged; a board whose first server has acquired a lease cannot be created again; the board row's fixed key makes two concurrent first runs one Conflict | Refused or Conflict |
| removal | whoever holds a removed server's disk | act as a server, or open sealed values with the key-encryption key still on that disk | removal disables every login recorded for the server in the transaction and revokes them after; a server login cannot create logins, and a login matching no server is revoked at the next renewal that sees it; the key on the disk is an accepted residual risk | disabling failure refuses the removal; a pending revocation is retried by every server |
| a lying server | a program holding server A's login | renew server B's lease, claim B's nodes, write B's rows | the database binds A's login to A's ID and refuses the write | the database rejects it |
| lease timing | anyone who can delay database writes | drop a healthy server's callers, or leave ghosts | timeout in renewals, bounded 2 to 10, on the database clock; the local deadline never falls after the database's; a suspended host treats its lease as lost; expired nodes are free at once; queued releases retried every renewal | expired means gone |
| a re-plan or count change | a slow layout operation | stall every server's renewal | layout operations hold layout and node rows, and only the server row of a server being created or removed | renewal never waits on layout |

## Negative tests
Serves: ADV-001
The gate tests cover each state-changing registry operation by name (createBoard, addServer,
setNodeCount, applyReplan, removeServer) and the reads (listServers, previewReplan) and
whosOnline.list. Database failures and clock movement are injected through the harness the
architecture's negative tests describe.

1. Re-plan with a caller on an affected node → Refused listing exactly the occupied affected nodes; no row changed; no audit entry.
2. Shrink that would drop an occupied node → Refused listing it; range unchanged.
3. Grow of a server whose range end is below the high-water mark → Refused "re-plan needed"; no range changed.
4. Grow of the server whose range end equals the mark → extended in place; every other range unchanged; the mark advanced.
5. Add or grow whose end would pass the node-number backstop → Refused "node numbers exhausted"; nothing written.
6. Remove server 3 of 1–8, 9–16, 17–24, then add a server → it gets 25 onward, not 17.
7. applyReplan with a stale expected layout version → Conflict; nothing written.
8. A re-plan that moves a stale occupied row to another owner → its occupant fields are cleared; the new owner can claim it.
9. Login with every node occupied → Exhausted; the busy screen; connection closed; no row written.
10. Busy screen fails to render → the built-in line; connection still closed.
11. Connect while the cached free count is zero → busy screen before login; the test observes no database query. Connect while it is `unknown` → login proceeds.
12. Unauthenticated web requests in any number → no occupied row.
13. Two logins race for the last free node → one succeeds, the other is Exhausted.
14. Claim at a generation older than the server's current → Refused; nothing written.
15. Under server A's login through the harness, a renewal naming server B's ID and generation, and a claim's compare-and-set on a node B owns → rejected by the database; B's rows unchanged.
16. Renewal at a stale generation → zero rows; the process ends every session and goes Fenced.
17. Server A's writes delayed past the timeout → A ends every session no later than the database expiry; who's-online on B stops listing A's callers at expiry; A's nodes count as free on B at expiry.
18. An outage longer than the lease timeout, then the database returns → A acquires with a new generation without operator action; its old occupant fields are cleared; callers can log in again.
19. Database unreachable from a Serving server → new logins refused; each session ends at its next screen boundary; an idle session ends at the local deadline; health is 503 `down`.
20. Database restored before the local deadline → Serving again with no operator action; reconcile clears only rows whose sessions are gone.
21. A claim that times out after committing, on a server that never leaves Serving → `releaseSession` is retried after the next renewal and clears the row; no ghost.
22. A long re-plan held past the renewal interval through the harness → no server's renewal stalls; no server goes Degraded.
23. Engine below the minimum → Refused naming the required version.
24. Engine two steps above the lowest other active server, or two steps below the highest → Refused naming the window; one step either way → admitted.
25. A data-model change shipped by version N+1, with the lowest active server on N → the minimum becomes at most N; servers on N keep serving; a server that then starts on N−1 is refused; the change is recorded once and not applied by a second server.
26. A lone server on N restarts as N+2 → admitted (no other active server); two lone servers on N and N+2 acquiring at once → one admitted, the other Refused; a Fenced server on N re-acquiring after the others moved to N+2 → Refused.
27. A second process with the same identity while the first renews → Refused as already running; the first's lease and sessions untouched.
28. Drain from a stale process while a successor holds the lease → zero rows; the successor's lease and occupied nodes untouched.
29. Remove a server → its sessions end within one renewal interval and it reaches Refused ("removed"); its rows are gone; its login is disabled in the transaction; another server's next renewal runs the second step, after which an already-open connection of that login fails its next statement and a new login attempt is rejected; a later add never receives its ID.
30. Remove with disabling the login forced to fail → Refused; the server still active. Remove with the second step's revocation forced to fail → status `removing`; another server's renewal completes it once the fault is lifted.
30a. A login created outside join v1 under a server login → rejected by the database; a login join v1 lists for no active or removing server → revoked at the next renewal, `login.revoke` audited.
31. Remove the last active server → Refused. Remove the server whose login carries the operation → Refused.
32. Remove an already removed server → Refused; one audit entry only.
33. Remove with a mismatched confirmation → Invalid; nothing changed.
34. Each registry operation, listServers, previewReplan and whosOnline.list included, with access control forced to error → Denied; nothing changed; no audit entry.
35. Each registry operation by an actor without the permission → Denied.
36. Each state-changing registry operation with audit forced to fail → rolled back.
37. Health on the public listener → minimal only, from any peer.
38. Health on the management listener from a peer outside the list → minimal; inside → detailed; empty list → minimal; a forwarded-address header naming a trusted address → minimal; a stored list made unparseable outside `set` → minimal to a peer that was in it.
39. Health with the database unreachable → served from cache, 503 `down`, no query; before the first read-back the count fields are absent.
40. whosOnline.list by a viewer not logged in → Denied; with the database unreachable → Unavailable.
41. A board-wide setting changed on A → applied on B within one renewal interval; a restart-mode setting → both tools list the servers needing a restart.
42. `cluster.lease_timeout_renewals` set to 1 or 11 → Invalid.
43. `cluster.trusted_proxies` with a name or an unparseable entry → Invalid; stored list unchanged.
44. A clock gap longer than the timeout (injected) → the lease treated as lost at the next checkpoint.
45. Release twice for one session → both succeed; the node is free once.
46. A host stop → the server drains, `server.stop` is audited with cause `host stop` and the local operator as actor, and the process exits with the no-restart code; a host stop with the database unreachable → the drain writes nothing, the process exits at the local deadline; a process start → `server.start` at its first acquisition.
47. createBoard when a board exists whose first server has acquired a lease → Refused; when its first server never acquired and the same key identifier, address and transport are presented → the same server ID and a new secret, `board.recover` audited; with a different key identifier → Refused; two concurrent first runs against an empty database → one succeeds, one Conflict.
48. The setup tool changes the record's trust anchor, or only the secret, then the engine restarts → `server.record.change` is written at acquisition (the fingerprint before and after, or "secret changed" with no value); with audit forced to fail, the acquisition fails; a first acquisition after createBoard or addServer with an unchanged record writes nothing.
48a. A record whose key identifier is not the board's → acquisition Refused ("wrong board key").
49. Conflict from contention on renewal (injected) → retried within the interval; no session ends.
50. Two servers named "Alpha" and "alpha" → the second addServer is Conflict.
51. A listener bind failure after the lease is held → operation 6 runs (`server.stop` audited with the fault as cause and actor kind `engine`) and the process exits with the no-restart code.
52. A claim with a session sessions v1 reports as not logged in, on any surface → Refused; no row written; with sessions v1 forced to error → Refused.
53. A claim committed on an affected node between a re-plan's mutex and its node holds → the re-plan is Refused listing that node.
54. Shrink to 0 then grow → the range keeps its start when the start − 1 equals the mark; otherwise Refused "re-plan needed".

## Revision history
- 2026-09-23: created for ADV-001.

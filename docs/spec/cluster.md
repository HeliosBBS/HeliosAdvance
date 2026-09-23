# Cluster
Serves: ADV-001

## Purpose
Serves: ADV-001
One board on many servers: what a server is, how it proves it is alive, how node numbers are
laid out across servers and taken by callers, what every server sees of every other, and
what a server does when it cannot reach the database. Membership, liveness and capacity are
one consistency domain, so they have one owner.

## Terms
Serves: ADV-001
As the glossary defines them: lease, generation, layout, high-water mark, re-plan, occupancy
(and the occupancy rule), screen boundary, local lease deadline, reconcile, trusted proxy
list, management listener, public listener.

## Contracts
Serves: ADV-001
Provided:

**cluster.nodes v1**, to the caller surfaces (Telnet, SSH, web):

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| admitting | none | whether the server accepts callers (true only in Serving) | none |
| freeNodesCached | none | free nodes on this server as of the last read-back, or `unknown` before the first | none |
| callersOnlineCached | none | callers online across the board as of the last read-back, or `unknown`; for a theme's pre-login display | none |
| claim | a session identifier from sessions v1, the caller reference, the surface | a node handle: node number, the session identifier | Refused (not admitting, or the lease is not live), Exhausted (no free node; a Refused with that reason), Unavailable |
| handle.checkpoint | at every screen boundary | `continue`, or `end` with the message to show | none |
| handle.release | none; idempotent | none | Unavailable (queued; retried after every successful renewal) |

The surface's obligations: call `admitting` on accept and, if false, show the theme's
"not accepting callers" screen and close; consult `freeNodesCached` on accept and, if it is
zero (not `unknown`), show the busy screen and close without a database read; call `claim`
at login and on Exhausted show the busy screen and close; on Unavailable from `claim` show the
"not accepting callers" screen, close, and call `release` with the same session identifier so
a claim that committed without a reply is cleared; call `checkpoint` at every screen
boundary; call `release` when the session ends for any reason, as sessions v1 defines a
session's end for each surface.

**cluster.whosOnline v1**, to menus and tools: `list(viewer)` → rows of node number, server
ID, server display name, caller display name (resolved through sessions v1 from the caller
reference), surface, claimed at; ordered by node number; read from the database on every
call. Gate: `whos_online.view` through access-control v1; error means Denied. The viewer is
an input so that later filters can attach to it.

**cluster.registry v1**, to the setup tool, the runtime configuration tools and join v1.
Every operation takes an actor and is gated through access-control v1 as the table says;
each writes its audit entry in its own transaction and fails with it.

| Operation | Gate | Inputs | Outputs | Errors |
|---|---|---|---|---|
| createBoard | the local operator, only while no board row exists (first run) | board name, display name, node count, HTTP connection limit | server ID, range | Denied, Invalid, Refused (a board exists), Unavailable |
| addServer | `board.administer`, on behalf of join v1 | display name, node count, HTTP connection limit | server ID, range | Denied, Invalid, Conflict (name taken), Refused (node numbers exhausted), Unavailable |
| listServers | `board.administer` | none | per server: ID, name, status, lease live, engine version, host facts, transport and address (as stored at admission), range, nodes in use, HTTP in use and limit, restart needed, record differs from running | Denied, Unavailable |
| setNodeCount | `board.administer` | server, count, expected layout version | range | Denied, Invalid, NotFound, Conflict (layout changed), Refused (nodes in use; re-plan needed; node numbers exhausted), Unavailable |
| previewReplan | `board.administer` | none | proposed ranges, affected nodes, the occupied ones among them, layout version | Denied, Unavailable |
| applyReplan | `board.administer` | expected layout version | ranges | Denied, Conflict, Refused (nodes in use), Unavailable |
| removeServer | `board.administer` | server, the server ID typed again | none | Denied, Invalid (mismatch), NotFound, Refused (already removed; the last active server; the login could not be revoked), Unavailable |
| stopServer | `server.stop` for that server | server | none | Denied, NotFound, Unavailable |
| markStarted | the engine itself | the settings version of its first snapshot | none | Unavailable |

Starting a server is the host's service manager's operation, run by the local operator; the
setup tool offers it beside stop.

**cluster.health v1**, external, over HTTP, body encoded as JSON (a public standard):
`GET /health` on the management listener returns the detailed form when the connection's own
peer address is inside an entry of the trusted proxy list, else the minimal form; the same
path on the public listener returns the minimal form always. No forwarded-address header is
consulted; no database is read.

| Form | Body | HTTP status |
|---|---|---|
| minimal | `status`: `up` or `down` | 200 for `up`; 503 for `down` |
| detailed | `status`: `up`, `full` or `down`; `server_id`; `engine_version`; `lease_live`; `nodes_in_use`, `node_count`, `free_nodes`; `http_in_use`, `http_limit`; `as_of_seconds` | 200 for `up` and `full`; 503 for `down` |

`status` is `up` in Serving with a free node, `full` in Serving with none (minimal form says
`up`), `down` in every other state. `lease_live` is true in Serving, in Degraded before the
local lease deadline, and in Draining. The node counts are as of the last read-back
(acquisition or renewal) and `as_of_seconds` is the server's own clock since it; before the
first read-back they are absent. The HTTP counts are live from http v1.

Consumed: database-access v1; access-control v1; configuration v1; audit v1; http v1;
sessions v1 (session identifiers, session end per surface, caller display names); theme v1
(the busy and "not accepting callers" screens; when it fails, a fixed built-in line "All
nodes are busy. Please call again later." or "This server is not accepting callers." is shown
and the connection still ends); join v1 (creating and revoking a server's database login).

## Data model
Serves: ADV-001
**Board**, exactly one row; its exclusive hold is the cluster mutex.

| Field | Meaning |
|---|---|
| name | the board's name |
| minimum engine version | major and minor; the oldest engine version the data model admits (see Behaviour, version rule) |
| layout version | increased by every layout change |
| high-water mark | the highest node number ever assigned; 0 on an empty board |
| next layout position | handed to a server at its first range assignment |

**Server**, never deleted; the row lease renewal writes, which no layout operation holds.

| Field | Meaning |
|---|---|
| server ID | increasing identifier, the key; never reused because rows are never deleted |
| display name | 1 to 32 code points (fixed backstop), no control characters, unique among active servers after normalisation to canonical composed form and default case folding as the Unicode Standard defines them |
| status | `active` or `removed`; `removed` is terminal |
| stop requested | set by `stopServer`; cleared at acquisition |
| lease generation | increased at each acquisition |
| lease expires at | database clock, or empty |
| lease timeout used | the timeout written at the last renewal |
| engine version, operating system, processor architecture, transport, database address | informational, written at acquisition; never branch behaviour |
| started settings version | written once per process by `markStarted` |
| HTTP in use reported, reported at | written by each renewal, for the tools |
| removed at, removed by | set once |

**Layout**, one row per server that has ever been assigned a range; the row layout
operations hold.

| Field | Meaning |
|---|---|
| server ID | the key |
| node count | 0 up to the node-number backstop |
| range start, range end | empty when the count is 0; end − start + 1 = count |
| layout position | unique; the order re-plan packs in; assigned at the first range assignment |

**Node**, one row per assigned node number.

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

Check-then-act operations, each one transaction taking holds in the global order:

1. **Acquire lease** (Admitting, and every renewal interval in Fenced): exclusive hold on the
   own server row; succeed only if active and the lease is empty or expired; read the lease
   timeout setting (the default if unset) and the layout row; increase the generation; write
   expiry = now + timeout, the informational fields, clear stop requested; clear the
   occupant fields of every own node row, in ascending order; read back what renewal reads
   back. A live lease held by anyone makes it Conflict. If the record's transport or address
   differs from the server row's stored values, write the audit entry `server.record.change`
   (actor: the local operator of this server; before and after) in the same transaction; if
   that write fails, the acquisition fails.
2. **Renew lease** (every renewal interval in Serving, Degraded and Draining): compare-and-set
   on the own server row matching own ID, own generation, active, and expiry later than now;
   write expiry = now + timeout, the reported HTTP fields. In the same transaction read back:
   the minimum engine version, the settings version, own status, stop requested, own count
   and range from the layout row, own occupied count under the occupancy rule, and the board's
   occupied count. When no rows matched, read back own status and stop requested all the
   same. A Conflict from contention is retried within the interval; Unavailable at the
   deadline is the "database Unavailable" input. Renewal never waits on a layout operation,
   because it holds only the server row and reads the layout row without holding it. The
   operation is bound to the bootstrap record's identity; it cannot name another server.
3. **Claim node**: shared hold on the own server row to confirm the lease is live at the own
   generation (else Refused, and the process takes the "renewal matches nothing" input);
   choose the lowest own node number that is free under the occupancy rule; compare-and-set
   its occupant fields and claim generation with the predicate "owned by this server and
   free under the rule"; on a Conflict, choose the next; after as many attempts as the
   server's node count, Exhausted. A claim waits on a row a layout operation holds, bounded by
   the operation deadline. The claim names no node number, so a claim outside the own range
   cannot be expressed, and the predicate refuses any row another server owns.
4. **Release node**: compare-and-set clearing the occupant fields where the node number and
   the session identifier match; zero rows is success.
5. **Layout operations** (createBoard, addServer, setNodeCount, applyReplan, removeServer):
   the cluster mutex; then the layout rows involved in ascending server ID; then the affected
   node rows in ascending number; never a server row. Each re-reads state after taking the
   mutex, checks occupancy under the rule on the affected rows, clears the occupant fields of
   every node row whose owner changes, increases the layout version, and records its audit
   entry. setNodeCount and applyReplan compare the expected layout version and fail with
   Conflict if it moved.
6. **Drain**: compare-and-set on the own server row matching own ID and own generation:
   expiry = now; then clear own node rows whose claim generation is the own generation. Zero
   rows on the first step means a successor holds the lease; do nothing further.
7. **Remove server**: operation 5, plus: Refused if it is the last active server; status
   `removed`, the node rows deleted, the lease cleared, and the server's database login
   revoked through join v1 inside the same transaction, which ends that login's open
   connections; if the revocation fails, the removal fails.

Layout rules:

- **Create board / add**: range start = high-water mark + 1; the mark advances to the new
  range end; the layout position comes from the board's counter. Refused with "node numbers
  exhausted" if the new end would exceed the node-number backstop.
- **Set node count, shrink**: drop the tail of the own range; the dropped numbers are the
  affected nodes; the mark does not move; the freed numbers are not reassigned until a
  re-plan.
- **Set node count, grow**: only if the range's end equals the high-water mark (no number
  above it has ever been assigned) or the count is 0 (an add-style assignment, with a new
  layout position); then extend in place and advance the mark. Otherwise Refused with
  "re-plan needed": a range is never moved except by a re-plan.
- **Re-plan**: pack every active server's range from node 1 upward in layout-position order
  with its configured count; the mark becomes the last assigned number. A node number is
  affected if its owner differs before and after or it ceases to exist; refused, listing the
  occupied affected nodes, if any is occupied. Unaffected rows are not touched. A re-plan
  that changes nothing writes nothing and records no entry.
- **Remove**: the range is retired: its numbers stay unassigned until a re-plan.

## Behaviour
Serves: ADV-001
**Version rule.** The board's minimum engine version is raised only by a data-model change
that older engines cannot use, and such a change may raise it to at most one minor version
below the engine that ships it. A server is admitted when its version is at least the
minimum and at most one minor version above it, on the same major version. Upgrading one
server to the next minor version admits it and leaves every other server admitted; a server
two minors ahead is refused until the board has moved; a server below the minimum is refused
and told the version required; a running server that finds the minimum raised above its
window drains. Data-model changes run after the version check, by an admitted server, under
the cluster mutex, each recorded as an applied change and never applied twice.

**Process states**, after database-access has opened the connection:

| State | Accepting callers | Meaning |
|---|---|---|
| Admitting | no | version checked, changes applied, lease acquired, snapshot loaded, listeners opened (once per process) |
| Serving | yes | lease live, database reachable |
| Degraded | no | database unreachable; sessions end at their next screen boundary; health `down` |
| Fenced | no | the local lease deadline passed or the lease was found lost; every session has been ended; acquisition is attempted each renewal interval |
| Draining | no | ordered to stop; sessions end at their next screen boundary, bounded by one lease timeout |
| Stopped | no | terminal; exits with the code the service manager does not restart |
| Refused | no | terminal; exits with the code the service manager does not restart, naming the reason; database-access's Fatal maps here |

A crash exits with any other code, which the service manager restarts.

**Operator stop**: `stopServer` sets stop requested, read back by the next renewal; or the
host's service manager asks the process to stop, which the process treats the same way at
once (a host event, not audited: `stopServer` is audited by its own transaction).

| State \ input | renewal or acquisition succeeds | renewal matches nothing | database Unavailable | Conflict on renewal | stop (read back or from the host) | removed (read back) | minimum raised above window | duplicate process |
|---|---|---|---|---|---|---|---|---|
| Admitting | own status `removed` → Refused; version outside window → Refused; acquired → Serving | n/a | stay; retry each renewal interval | retry now | Stopped | Refused | Refused | a live lease held by another → wait one renewal interval and retry; still held after one lease timeout plus one renewal interval → Refused ("already running elsewhere") |
| Serving | refresh settings if the version moved; update cached counts; stay | end every session now; if the read-back says removed → Stopped; else → Fenced | → Degraded | retry within the interval; at the deadline treat as Unavailable | → Draining | end every session now → Stopped | → Draining | cannot acquire or renew; never disturbs this one |
| Degraded | reconcile; → Serving | as Serving | at the local lease deadline: end every remaining session → Fenced; else keep retrying | as Serving | → Draining | as Serving | → Draining | as Serving |
| Fenced | acquisition succeeded → refresh settings, update counts → Serving (listeners stay open) | acquisition finds status `removed` → Refused | keep retrying each renewal interval | retry now | Stopped | Refused | Refused | acquisition finds a live lease → keep retrying; after the wait above → Refused |
| Draining | every session ended, or one lease timeout elapsed → drain (operation 6) → Stopped | end every session now → Stopped | at the local deadline end every session → Stopped without writing | retry within the interval | ignored | end every session now → Stopped | continue draining | as Serving |

Renewal keeps running in Serving, Degraded and Draining; acquisition is attempted in Fenced.

**Suspend**: a server whose clock shows a gap longer than the lease timeout since its last
successful renewal or acquisition treats its lease as lost at its next checkpoint or renewal
(the "renewal matches nothing" input), because a paused host may have been declared expired
while it slept.

**Sessions ending after their current screen**: the next `checkpoint` returns `end` with the
message; a session waiting for input ends at the local lease deadline if no input arrives
first; a web session ends at its next request or at its end as sessions v1 defines it.

**Node states** under the occupancy rule: unassigned (no row) → free (a layout operation
creates it) → occupied (claim) → free (release; the owner's lease expiry, at once, everywhere;
the owner removed, row deleted; the owner changed by a layout operation, occupant cleared).
A stale row (occupant set but free under the rule) is cleared by its owner's next acquisition
and overwritten by its owner's next claim.

**Reconcile** (on Degraded → Serving) and **after every successful renewal**: clear the
occupant fields of every own node row whose session identifier is not in this process's live
handles, with the predicate "owned by this server, that session identifier, this
generation"; retry every queued release. A second run finds nothing to do.

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
| join v1 | revocation fails | the removal is Refused |
| sessions v1 | fails to resolve a display name | who's-online shows the node with no name rather than failing |
| own clock | a gap longer than the timeout | the lease is treated as lost |

## Multi-node invariants
Serves: ADV-001
Only in the database: servers, status, leases, layout, occupancy, the minimum version, applied
changes. Process-local, never truth: live session handles (added before a claim is attempted,
removed after release or after an Unavailable claim); queued releases; the local lease
deadline; the cached counts.

| Cache | Invalidation |
|---|---|
| own count, range, occupied count, free count, board callers online | replaced by every read-back (acquisition and renewal); `unknown` before the first; `as_of_seconds` exposes the age |
| the minimum engine version | replaced by every read-back |
| who's-online | none: read on every call |

Jobs: renewal and acquisition (a compare-and-set or a guarded acquire; a duplicate tick
extends to the same or a later time, or finds the lease live); reconcile (clears to the same
empty state); data-model changes (recorded, never applied twice). There is no reaper: an
expired server's nodes are free under the occupancy rule at the instant of expiry.

## Audit
Serves: ADV-001
| Action | When | Before | After |
|---|---|---|---|
| `board.create` | createBoard | empty | board name, first server's name, count, range, HTTP limit |
| `server.add` | addServer | empty | name, count, range, HTTP limit |
| `server.remove` | removeServer | name, `active`, range, occupied node numbers | `removed` |
| `server.node_count.change` | setNodeCount | count, range | count, range |
| `layout.replan` | applyReplan that changes anything | every active range | every active range |
| `server.stop` | stopServer | lease state | stop requested |
| `server.record.change` | acquisition finding the record's transport or address changed | transport, address | transport, address |

The HTTP connection limit is a setting (`http.connection_limit`) and its change is audited by
configuration as `setting.change`. Refused operations change nothing and write no entry.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| node count (a Layout field, changed only by setNodeCount) | set at join | sysop tunable; 0 up to the node-number backstop | server | live | runtime configuration tools; setup tool at first run and join |
| `cluster.lease_timeout_renewals` | 3 | sysop tunable; 2 to 10 (fixed backstops: below 2 one late write drops a healthy server, above 10 a dead server's callers stay listed too long) | board | live at the next renewal | runtime configuration tools |
| `cluster.trusted_proxies` | empty | sysop tunable; a list of address ranges in prefix notation, no names; IPv4 addresses arriving as IPv6-mapped are compared as IPv4 | board | live | runtime configuration tools |
| lease renewal interval | five seconds | calibration target | fixed | | not exposed |
| node-number backstop | 2,147,483,647 | fixed policy backstop | | | not exposed |
| draining bound | one lease timeout | fixed policy backstop | | | not exposed |
| version skew window | one minor version above the minimum, same major | fixed policy backstop | | | not exposed |
| duplicate-process wait | one lease timeout plus one renewal interval | calibration target | fixed | | not exposed |

Tool screens: Servers (listServers, restart-needed and record-differs flags); Server detail
(count with the resulting range or refusal, HTTP limit, transport and address as reported,
remove with typed confirmation, stop); Layout (previewReplan; apply disabled while any
affected node is occupied, listing them); Board (lease timeout in renewals with the
resulting seconds, trusted proxy list). In the setup tool, for its own server only: the
bootstrap record's address, trust anchor and transport, the listen addresses, stop and
start; the setup tool restarts the engine after writing the record.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| node claims and leases | a misconfigured or lying server, or a duplicate process | exhaust numbers, evict another server's callers, keep a lease it should not | ranges assigned only by layout operations under the mutex, from configured counts, bounded by the backstop; a claim names no number and its predicate refuses rows another server owns; renewal and drain are compare-and-sets on own identity and generation; a duplicate cannot acquire a live lease | out-of-range or stale-generation claim Refused; zero-row renewal ends sessions; zero-row drain does nothing |
| listeners | an anonymous flooder | take every node | nodes are taken only at login; a connection while the cached free count is zero is turned away without a database read; per-source limits are the caller features' | at the limit, refuse |
| health | an anonymous mapper | learn fullness and timing | detail only on the management listener from a peer inside the trusted proxy list; the public listener says up or down; no forwarded header; no database read | empty or unparseable list means minimal |
| who's-online | an anonymous caller | count per-server fullness | gated on `whos_online.view` | Denied on any error |
| registry | a caller without the permission | change the board | every operation gated through access-control v1 | error means Denied |
| removal | whoever holds a removed server's disk | act as a server | removal revokes the login and ends its connections in the same transaction; the last active server cannot be removed | revocation failure refuses the removal |
| lease timing | anyone who can delay database writes | drop a healthy server's callers, or leave ghosts | timeout in renewals, bounded 2 to 10, on the database clock; the local deadline never falls after the database's; a suspended host treats its lease as lost; expired nodes are free at once; queued releases retried every renewal | expired means gone |
| a re-plan or count change | a slow layout operation | stall every server's renewal | layout operations hold layout and node rows only, never the server row renewal writes | renewal never waits on layout |

## Negative tests
Serves: ADV-001
The gate tests cover each registry operation by name (createBoard, addServer, listServers,
setNodeCount, previewReplan, applyReplan, removeServer, stopServer) and whosOnline.list.
Database failures and clock movement are injected through the harness property the
architecture states.

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
15. A claim's compare-and-set issued (through the harness) against a row another server owns → matches nothing; the row unchanged.
16. Renewal at a stale generation → zero rows; the process ends every session and goes Fenced.
17. Server A's writes delayed past the timeout → A ends every session no later than the database expiry; who's-online on B stops listing A's callers at expiry; A's nodes count as free on B at expiry.
18. A outage longer than the lease timeout, then the database returns → A acquires with a new generation without operator action; its old occupant fields are cleared; callers can log in again.
19. Database unreachable from a Serving server → new logins refused; each session ends at its next screen boundary; an idle session ends at the local deadline; health is 503 `down`.
20. Database restored before the local deadline → Serving again with no operator action; reconcile clears only rows whose sessions are gone.
21. A claim that times out after committing, on a server that never leaves Serving → the surface's release is retried after the next renewal and clears the row; no ghost.
22. A long re-plan (held past the renewal interval through the harness) → no server's renewal stalls; no server goes Degraded.
23. Engine below the minimum → Refused naming the required version.
24. Engine two minors above the minimum, or another major → Refused naming the window.
25. A data-model change shipped by version N+1 sets the minimum to N → servers on N keep serving; a server on N−1 drains and stops; the change is recorded once and not applied by a second server.
26. A second process with the same identity while the first renews → Refused as already running; the first's lease and sessions untouched.
27. Drain from a stale process while a successor holds the lease → zero rows; the successor's lease and occupied nodes untouched.
28. Remove a server → its sessions end within one renewal interval; its rows are gone; an already-open connection of its login fails its next statement; restarting it → Refused as removed; a later add never receives its ID.
29. Remove with the revocation forced to fail → Refused; the server still active.
30. Remove the last active server → Refused.
31. Remove an already removed server → Refused; one audit entry only.
32. Remove with a mismatched confirmation → Invalid; nothing changed.
33. Each registry operation with access control forced to error → Denied; nothing changed; no audit entry.
34. Each registry operation by an actor without the permission → Denied.
35. Each registry operation with audit forced to fail → rolled back.
36. Health on the public listener → minimal only, from any peer.
37. Health on the management listener from a peer outside the list → minimal; inside → detailed; empty list → minimal; a forwarded-address header naming a trusted address → minimal; a stored list made unparseable outside `set` → minimal to a peer that was in it.
38. Health with the database unreachable → served from cache, 503 `down`, no query; before the first read-back the count fields are absent.
39. whosOnline.list by a viewer not logged in → Denied.
40. A board-wide setting changed on A → applied on B within one renewal interval; a restart-mode setting → both tools list the servers needing a restart.
41. `cluster.lease_timeout_renewals` set to 1 or 11 → Invalid.
42. `cluster.trusted_proxies` with a name or an unparseable entry → Invalid; stored list unchanged.
43. A clock gap longer than the timeout (injected) → the lease treated as lost at the next checkpoint.
44. Release twice for one session → both succeed; the node is free once.
45. stopServer → `server.stop` audited; the server drains at its next renewal and exits with the no-restart code; a host stop → the same drain, no entry.
46. createBoard when a board exists → Refused; createBoard by a local operator on first run → the board row, the first server, its login and range exist, `board.create` audited.
47. The setup tool changes the record's transport, then the engine restarts → `server.record.change` is written at acquisition with the old and new transport; with audit forced to fail, the acquisition fails.
48. Conflict from contention on renewal (injected) → retried within the interval; no session ends.

## Revision history
- 2026-09-23: created for ADV-001.

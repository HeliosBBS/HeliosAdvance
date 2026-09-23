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
- **Lease**: a server's proof of life in the database, with an expiry on the database clock
  and a **generation** that increases each time the server acquires it.
- **Layout**: the assignment of node-number ranges to servers. **High-water mark**: the
  highest node number ever assigned; numbers below it are never assigned again except by a
  re-plan.
- **Re-plan**: the sysop's explicit operation that packs every active server's range from
  node 1 upward, closing gaps.
- **Occupancy rule**: a node is occupied exactly when its occupant fields are set, its claim
  generation equals its owner's lease generation, its owner is active, and its owner's lease
  expiry is later than the database clock; otherwise it is free. Every count, listing and
  check in this document uses this rule.
- **Screen boundary**: the moment a session has finished sending one screen and is about to
  wait for input, and again when that input arrives; for a web session, the end of each
  request.
- **Local lease deadline**: the server's own clock reading at which its last successful
  renewal was sent plus the lease timeout that renewal wrote. The database stamped the expiry
  no earlier than that send, so the local deadline never falls after the database's.

## Contracts
Serves: ADV-001
Provided:

**cluster.nodes v1**, to the caller surfaces (Telnet, SSH, web):

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| admitting | none | whether the server accepts callers (true only in Serving) | none |
| freeNodesCached | none | free nodes as of the last renewal; a hint, never a decision | none |
| claim | the session identifier the surface minted, the caller reference, the surface | a node handle: node number, the session identifier | Refused (not admitting, or the lease is not live), Exhausted (no free node), Unavailable |
| handle.checkpoint | at every screen boundary | `continue`, or `end` with the message to show | none |
| handle.release | none; idempotent | none | Unavailable (queued and retried by reconcile) |

The surface's obligations: call `admitting` on accept and, if false, show the theme's busy
screen and close; consult `freeNodesCached` on accept and, if zero, show the busy screen and
close without a database read; call `claim` at login and on Exhausted show the busy screen
and close; call `checkpoint` at every screen boundary; call `release` when the session ends
for any reason, and on an Unavailable from `claim` treat the session as not started and
call `release` with the same session identifier. `Exhausted` is a Refused with that reason.

**cluster.whosOnline v1**, to menus and tools: `list(viewer)` → rows of node number, server
ID, server display name, caller reference, surface, claimed at; ordered by node number; read
from the database on every call; only for a viewer that is a logged-in caller or a sysop,
else Denied. The accounts feature adds the viewer-dependent filters (private users, blocked
users) here.

**cluster.registry v1**, to the setup tool, the runtime configuration tools and the join
feature. Every operation takes an actor and is gated through the access-control contract:
the sysop permission, or where noted the local operator of the target server. Each writes
its audit entry in its own transaction and fails with it.

| Operation | Gate | Inputs | Outputs | Errors |
|---|---|---|---|---|
| addServer | sysop (the join feature's sysop, on the existing server) | display name, node count, HTTP connection limit | server ID, range | Denied, Invalid, Conflict (name taken), Refused (node numbers exhausted), Unavailable |
| listServers | sysop | none | per server: ID, name, status, lease live, engine version, host facts, transport, range, nodes in use, HTTP in use and limit, restart needed | Denied, Unavailable |
| setNodeCount | sysop | server, count, expected layout version | range | Denied, Invalid, NotFound, Conflict (layout changed), Refused (nodes in use, or re-plan needed, or exhausted), Unavailable |
| setHttpLimit | sysop | server, limit | limit | Denied, Invalid, NotFound, Unavailable |
| previewReplan | sysop | none | proposed ranges, affected nodes, the occupied ones among them, layout version | Denied, Unavailable |
| applyReplan | sysop | expected layout version | ranges | Denied, Conflict, Refused (nodes in use), Unavailable |
| removeServer | sysop | server, the server ID typed again | none | Denied, Invalid (mismatch), NotFound, Refused (already removed; or the login could not be revoked), Unavailable |
| stopServer | local operator of that server, or sysop | server | none | Denied, NotFound, Unavailable |

**cluster.health v1**, external, over HTTP: `GET /health` on the management listener returns
detail; the same path on the public listener returns the minimal form. Detail on the
management listener is served only when the connection's own peer address is inside an entry
of the trusted proxy list; otherwise the minimal form. Forwarded-address headers are never
consulted.

| Form | Body | HTTP status |
|---|---|---|
| minimal | `status`: `up` (Serving) or `down` (any other state) | 200 for `up`, 503 for `down` |
| detailed | `status` as above plus `full` (Serving with no free node); `server_id`; `lease_live` (Serving, Degraded before the local deadline, or Draining); `nodes_in_use`, `node_count`, `free_nodes` (as of the last renewal; zero and `as_of_seconds` absent before the first); `http_in_use`, `http_limit` (live); `as_of_seconds` (the server's own clock since the last renewal); `engine_version` | 200 for `up` and `full`, 503 otherwise |

Serving health never reads the database.

Consumed: database-access v1; configuration v1; audit v1; http v1; access-control (the
accounts feature's); the theme's busy screen (the theme feature's; when it fails, a fixed
built-in line "All nodes are busy. Please call again later." is shown and the connection
still ends); the join feature's credential contract, for revoking a server's database login
on removal.

## Data model
Serves: ADV-001
**Board**, exactly one row; its exclusive hold is the cluster mutex.

| Field | Meaning |
|---|---|
| minimum engine version | major, minor; the oldest engine version the schema admits (see Behaviour, version rule) |
| layout version | increased by every layout change |
| high-water mark | the highest node number ever assigned; 0 on an empty board |
| next layout position | handed to each server at its first range assignment |
| settings version | see configuration |

**Server**, never deleted.

| Field | Meaning |
|---|---|
| server ID | increasing identifier, the key; never reused because rows are never deleted |
| display name | 1 to 32 characters counted as code points (fixed backstop), no control characters, unique among active servers under simple case folding |
| status | `active` or `removed`; `removed` is terminal |
| node count | 0 up to the board node backstop |
| range start, range end | empty when the count is 0; end − start + 1 = count |
| layout position | unique; the order re-plan packs in |
| HTTP connection limit | at least 1 |
| lease generation | increased at each acquisition |
| lease expires at | database clock, or empty |
| lease timeout used | the timeout written at the last renewal |
| engine version, operating system, processor architecture, transport | informational, written at acquisition; never branch behaviour |
| started settings version | see configuration; written once per process start |
| HTTP in use reported, reported at | written by each renewal, for the tools |
| removed at, removed by | set once |

**Node**, one row per assigned node number.

| Field | Meaning |
|---|---|
| node number | the key; board-wide; at most the node-number backstop |
| owner | the server |
| occupant session, occupant caller, occupant surface | set together or empty together |
| claim generation | the owner's lease generation at claim time |
| claimed at | database clock |

Constraints: a node number lies within its owner's range (the layout operations are the
only writers of the owner and the ranges); at most one live occupancy per session identifier.

Check-then-act operations, each one transaction, with the hold order Board, then Server rows
in ascending server ID, then Node rows in ascending node number, so that no two transactions
wait on each other:

1. **Acquire lease** (Admitting): exclusive hold on the own server row; succeed only if
   active and the lease is empty or expired; read the lease timeout setting inside the same
   transaction (the default if unset); increase the generation; write expiry = now + timeout,
   the informational fields; clear the occupant fields of every own node row in ascending
   order. A live lease makes it Conflict.
2. **Renew lease** (every renewal interval in Serving, Degraded and Draining): compare-and-set
   on the own server row matching own ID, own generation, active, and expiry later than now;
   write expiry = now + timeout and the reported HTTP fields; in the same transaction read
   back the minimum engine version, the settings version, own status, own count and range,
   and own occupied count under the occupancy rule. No rows matched means the lease is lost.
   The operation is bound to the bootstrap record's identity; it cannot name another server.
3. **Claim node**: shared hold on the own server row to confirm the lease is live at the own
   generation (else Refused and the server treats the lease as lost); choose the lowest own
   node number that is free under the rule; compare-and-set its occupant fields and claim
   generation with the predicate "owned by this server and free"; if another claim won the
   row, choose the next; after as many attempts as the server's node count, Exhausted. A
   claim waits for a layout operation holding a row rather than skipping it, bounded by the
   operation deadline. The claim names no node number, so a claim outside the own range
   cannot be expressed, and the predicate refuses any row another server owns.
4. **Release node**: compare-and-set clearing the occupant fields where the node number and
   the session identifier match; zero rows is success.
5. **Layout operations** (add, set node count, re-plan, remove): the cluster mutex first, then
   the server rows involved in ascending ID, then the affected node rows in ascending number;
   each re-reads state after taking the mutex, checks occupancy under the rule on the
   affected rows, increases the layout version, and records its audit entry. Set node count
   and apply re-plan compare the expected layout version and fail with Conflict if it moved.
6. **Drain**: compare-and-set on the own server row matching own ID and own generation:
   expiry = now; clear own nodes whose claim generation is the own generation. Zero rows
   means a successor holds the lease; do nothing.
7. **Remove server**: the layout operation above, plus status `removed`, the node rows
   deleted, the lease cleared, and the server's database login revoked through the join
   feature's credential contract in the same transaction; if the revocation fails, the
   removal fails.

Layout rules:

- **Add**: range start = high-water mark + 1; the mark advances to the new range end; the
  layout position comes from the board's counter. Refused with "node numbers exhausted" if
  the new end would exceed the node-number backstop or the board node backstop.
- **Set node count, shrink**: drop the tail of the own range; the dropped numbers are the
  affected nodes; the mark does not move; the freed numbers are not reassigned until a
  re-plan.
- **Set node count, grow**: only if the numbers directly after the own range are above the
  high-water mark (that is, the server holds the highest range or has count 0); then extend
  in place and advance the mark. Otherwise Refused with "re-plan needed": a range is never
  moved except by a re-plan. A grow from count 0 is an add-style assignment.
- **Re-plan**: pack every active server's range from node 1 upward in layout-position order
  with its configured count; the mark becomes the last assigned number. A node number is
  affected if its owner differs before and after or it ceases to exist; refused, listing the
  occupied affected nodes, if any is occupied. Unaffected rows are not touched. A re-plan
  that changes nothing writes nothing and records no entry.
- **Remove**: the range is retired: its numbers stay unassigned until a re-plan.

## Behaviour
Serves: ADV-001
**Version rule.** The board's minimum engine version is raised only by a schema migration that
makes the schema unusable by older engines, and a migration may raise it to at most one minor
version below the engine that ships it. A server is admitted when its version is at least
the minimum and at most one minor version above it, on the same major version. So upgrading
one server to the next minor version admits it and leaves every other server admitted; a
server two minors ahead is refused until the board has moved; a server below the minimum is
refused and told the version required; a running server that finds the minimum raised above
its window drains. Migrations run at Admitting under the cluster mutex, once, by whichever
server gets there first.

**Process states**, after database-access has opened the connection:

| State | Accepting callers | Meaning |
|---|---|---|
| Admitting | no | own status and version checked, lease acquired, snapshot loaded, listeners opened (once per process) |
| Serving | yes | lease live, database reachable |
| Degraded | no | database unreachable or a renewal lost; sessions end at their next screen boundary; health `down` |
| Fenced | no | the local lease deadline passed; every session has been ended |
| Draining | no | ordered to stop; sessions end at their next screen boundary, bounded by one lease timeout |
| Stopped | no | terminal; the process exits with the code that tells the service manager to restart it normally |
| Refused | no | terminal; the process exits with the code that tells the service manager not to restart it, and names the reason |

**Operator stop**: a request from the service manager, or `stopServer` from the registry,
observed at the next screen boundary check or renewal.

| State \ input | renewal succeeds | renewal matches nothing | database Unavailable | operator stop | removed (read back or observed) | minimum raised above window |
|---|---|---|---|---|---|---|
| Admitting | own status `removed` → Refused; version outside window → Refused; a live lease held by another process → wait one renewal interval and retry; still held after one lease timeout plus one renewal interval → Refused ("already running elsewhere"); acquired → Serving | n/a | stay Admitting, retry each renewal interval | Stopped | Refused | Refused |
| Serving | refresh settings if the version moved; update cached counts; stay | end every session now; if the read-back says removed → Stopped (and Refused on restart); else → Fenced | → Degraded | → Draining | end every session now → Stopped | → Draining |
| Degraded | reconcile, → Serving | as Serving | at the local lease deadline: end every remaining session → Fenced; else keep retrying | → Draining | as Serving | → Draining |
| Fenced | → Admitting (re-acquire with a new generation; listeners stay open) | n/a | keep retrying each renewal interval | Stopped | Refused at Admitting | Refused at Admitting |
| Draining | every session ended, or one lease timeout elapsed → drain (operation 6) → Stopped | end every session now → Stopped | at the local deadline end every session → Stopped without writing | ignored | end every session now → Stopped | continue draining |

Duplicate process with the same identity: it cannot acquire while the first renews, and it
cannot renew (its generation never matches), so it never disturbs the first; it is Refused
after the wait above. A crashed predecessor's lease expires inside that wait, so a restart
after a crash succeeds.

**Suspend**: a server whose own clock shows a gap longer than the lease timeout since its
last renewal treats its lease as lost at the next checkpoint or renewal, whatever the local
deadline says, because a paused host may have been declared expired while it slept.

**Sessions ending after their current screen**: the next `checkpoint` returns `end` with the
message; a session waiting for input ends at the local lease deadline if no input arrives
first.

**Node states** under the occupancy rule: unassigned (no row) → free (a layout operation
creates it) → occupied (claim) → free (release; owner's lease expiry, at once, everywhere;
owner removed, row deleted). A stale row (occupant set but the rule says free) is cleared by
its owner's next acquisition, overwritten by its owner's next claim, deleted by removal, and
treated as free by re-plan.

**Reconcile** (on Degraded → Serving): clear the occupant fields of every own node row whose
session identifier is not in this process's live handles, with the compare-and-set predicate
"owned by this server, that session identifier, this generation"; retry every queued release.
The second run finds nothing to do.

## Failure directions
Serves: ADV-001
| Dependency | Failure | Direction |
|---|---|---|
| database, running | Unavailable on a renewal, or the connection lost | Degraded: refuse callers; sessions end at their next screen boundary; at the local deadline all end; resume on the first successful renewal with no operator action. An Unavailable on any other operation is returned to that caller and does not change the process state |
| lease | lost or expired | closed toward freeing capacity: sessions end, nodes are free under the rule, re-acquisition gets a new generation |
| access control | error | Denied; who's-online Denied |
| trusted proxy list | unparseable | refused at `set`; a stored list that cannot be parsed is treated as empty |
| theme busy screen | missing or fails | the built-in line; the connection still ends |
| audit | fails | the operator action rolls back |
| join credential contract | revocation fails | the removal is Refused |
| own clock | a gap longer than the timeout | the lease is treated as lost |

## Multi-node invariants
Serves: ADV-001
Only in the database: servers, status, leases, layout, occupancy, the minimum version.
Process-local, never truth: open HTTP connections; live session handles (added before a claim
is attempted, removed after release or after an Unavailable claim); queued releases; the
local lease deadline.

| Cache | Invalidation |
|---|---|
| own count, range, occupied count, free count (for health and the pre-login hint) | replaced by every renewal's read-back; `as_of_seconds` exposes the age |
| the minimum engine version | replaced by every renewal's read-back |
| who's-online | none: read on every call |

Jobs: renewal (a compare-and-set extending expiry; a duplicate tick extends to the same or a
later time); reconcile (clears to the same empty state); migrations (each is idempotent and
recorded as applied under the cluster mutex). There is no reaper: an expired server's nodes
are free under the occupancy rule at the instant of expiry.

## Audit
Serves: ADV-001
| Action | When | Before | After |
|---|---|---|---|
| `server.add` | addServer | empty | name, count, range, HTTP limit |
| `server.remove` | removeServer | name, `active`, range, occupied node numbers | `removed` |
| `server.node_count.change` | setNodeCount | count, range | count, range |
| `server.http_limit.change` | setHttpLimit | limit | limit |
| `layout.replan` | applyReplan that changes anything | every active range | every active range |
| `server.stop` | stopServer, or an operator stop observed by the process | lease state | draining |
| `server.transport.change` | the setup tool changing the bootstrap record's transport (recorded by the setup tool as local operator) | transport | transport |

Refused operations change nothing and write no entry.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| node count (a Server field, changed only by setNodeCount) | set at join | sysop tunable | server | live | runtime configuration tools; setup tool at join |
| HTTP connection limit (a Server field, changed only by setHttpLimit) | set at join | sysop tunable | server | live | runtime configuration tools; setup tool at join |
| `cluster.lease_timeout_renewals` | 3 | sysop tunable; validation 2 to 10 (fixed backstops: below 2 one late write drops a healthy server, above 10 a dead server's callers stay listed too long) | board | live at the next renewal | runtime configuration tools |
| `cluster.trusted_proxies` | empty | sysop tunable; a list of address ranges in prefix notation, no names; IPv4 addresses arriving as IPv6-mapped are compared as IPv4 | board | live | runtime configuration tools |
| lease renewal interval | five seconds | calibration target | fixed | | |
| operation deadline for cluster operations | the renewal interval | calibration target | fixed | | |
| node-number backstop | 2,147,483,647 | fixed policy backstop | | | |
| board node backstop | 65,535 nodes across the board | fixed policy backstop (a board larger than this has outgrown the layout model) | | | |
| draining bound | one lease timeout | fixed policy backstop | | | |
| version skew window | one minor version above the minimum, same major | fixed policy backstop | | | |

Tool screens: Servers (listServers, restart-needed flags); Server detail (count with the
resulting range or refusal, HTTP limit, transport as reported, remove with typed
confirmation); Layout (previewReplan; apply disabled while any affected node is occupied,
listing them); Board (lease timeout in renewals with the resulting seconds, trusted proxy
list); in the setup tool, for its own server only: listen addresses, transport, stop.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| node claims and leases | a misconfigured or lying server, or a duplicate process | exhaust numbers, evict another server's callers, keep a lease it should not | ranges assigned only by layout operations under the mutex, from configured counts, bounded by the backstops; a claim names no number and its predicate refuses rows another server owns; renewal and drain are compare-and-sets on own identity and generation; a duplicate cannot acquire a live lease | out-of-range or stale-generation claim Refused; zero-row renewal ends sessions; zero-row drain does nothing |
| listeners | an anonymous flooder | take every node | nodes are taken only at login; a connection with the cached free count at zero is turned away without a database read; the HTTP limit and deadlines bound web traffic (http); per-source limits are the caller features' | at the limit, refuse |
| health | an anonymous mapper | learn fullness and timing | detail only on the management listener and only from a peer inside the trusted proxy list; the public listener says up or down; no forwarded header is consulted; no database read | empty or unparseable list means minimal |
| who's-online | an anonymous caller | count per-server fullness | viewers must be logged in or sysops | Denied on any error |
| registry | a caller without the permission | change the board | every operation gated; the local operator reaches only stopServer for its own server and the connectivity settings | error means Denied |
| removal | whoever holds a removed server's disk | act as a server | removal revokes the server's database login in the same transaction | revocation failure refuses the removal |
| lease timing | anyone who can delay database writes | drop a healthy server's callers, or leave ghosts | timeout in renewals, bounded 2 to 10, on the database clock; the local deadline never falls after the database's; a suspended host treats its lease as lost; expired nodes are free at once | expired means gone |

## Negative tests
Serves: ADV-001
Registry operations named in the gate tests: addServer, listServers, setNodeCount,
setHttpLimit, previewReplan, applyReplan, removeServer, stopServer, whosOnline.list.

1. Re-plan with a caller on an affected node → Refused listing exactly the occupied affected nodes; no row changed; no audit entry.
2. Shrink that would drop an occupied node → Refused listing it; range unchanged.
3. Grow of a server that does not hold the highest range → Refused "re-plan needed"; no range changed.
4. Grow of the server holding the highest range with free numbers above → extended in place; every other range unchanged; the high-water mark advanced.
5. Add or grow whose end would pass the node-number backstop or the board node backstop → Refused "node numbers exhausted"; nothing written.
6. Remove server 3 of 1–8, 9–16, 17–24, then add a server → it gets 25 onward, not 17.
7. applyReplan with a stale expected layout version → Conflict; nothing written.
8. Login with every node occupied → Exhausted; the busy screen; connection closed; no row written.
9. Busy screen fails to render → the built-in line; connection still closed.
10. Connect while the cached free count is zero → busy screen before login; no database read (the test observes no query).
11. Unauthenticated web requests in any number → no occupied row.
12. Two logins race for the last free node → one succeeds, the other is Exhausted.
13. Claim at a generation older than the server's current → Refused; nothing written.
14. A claim whose predicate is forced against a row another server owns → matches nothing; the row unchanged.
15. Renewal at a stale generation → zero rows; the process ends every session and goes Fenced.
16. Database writes from server A delayed past the timeout → A ends every session no later than the database expiry; who's-online on B stops listing A's callers at expiry; A's nodes count as free on B at expiry.
17. A reconnects after expiry → acquires with a new generation; its old occupant fields are cleared.
18. Database unreachable from a Serving server → new logins refused; each session ends at its next screen boundary; an idle session ends at the local deadline; health is 503 `down`.
19. Database restored before the local deadline → Serving again with no operator action; reconcile clears only rows whose sessions are gone.
20. A claim that times out after committing → the surface's release clears the row at reconcile; no ghost.
21. Engine below the minimum → Refused naming the required version.
22. Engine two minors above the minimum, or another major → Refused naming the window.
23. A migration shipped by version N+1 sets the minimum to N → servers on N keep serving; a server on N−1 drains and stops.
24. A second process with the same identity while the first renews → Refused as already running; the first's lease and sessions untouched.
25. Drain from a stale process while a successor holds the lease → zero rows; the successor's lease and occupied nodes untouched.
26. Remove a server → its sessions end within one renewal interval; its rows are gone; its database login no longer authenticates; restarting it → Refused as removed; a later add never receives its ID.
27. Remove with the credential revocation forced to fail → Refused; the server still active.
28. Remove an already removed server → Refused; one audit entry only.
29. Remove with a mismatched confirmation → Invalid; nothing changed.
30. Each registry operation with access control forced to error → Denied; nothing changed; no audit entry.
31. Each registry operation by an actor without the permission → Denied.
32. stopServer by the local operator of another server → Denied.
33. Each registry operation with audit forced to fail → rolled back.
34. Health on the public listener → minimal only, from any peer.
35. Health on the management listener from a peer outside the list → minimal; inside → detailed; empty list → minimal; a forwarded-address header naming a trusted address → minimal.
36. Health with the database unreachable → served from cache, 503 `down`, no query.
37. whosOnline.list by a viewer not logged in → Denied.
38. A board-wide setting changed on A → applied on B within one renewal interval; a restart-mode setting → both tools list the servers needing a restart.
39. `cluster.lease_timeout_renewals` set to 1 or 11 → Invalid.
40. `cluster.trusted_proxies` with a name or an unparseable entry → Invalid; stored list unchanged.
41. A host clock gap longer than the timeout → the lease treated as lost at the next checkpoint.
42. Release twice for one session → both succeed; the node is free once.
43. An operator stop from Serving → `server.stop` audited; sessions end at their next boundary; the process exits with the normal-restart code; a removed or duplicate server exits with the no-restart code.

## Revision history
- 2026-09-23: created for ADV-001.

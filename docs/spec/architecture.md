# Architecture
Serves: ADV-001

## Purpose
Serves: ADV-001
The engine is one board run by any number of servers against one database. This document is
the map: which subsystem owns what, the properties every subsystem may rely on from the
database, where identifiers and time come from, the error classes every contract uses, the
order in which entities are held, and the order in which a server starts. Every mechanism
is stated once, in the subsystem that owns it; this document owns only what is shared.

## Terms
Serves: ADV-001
As the estate glossary defines them: board, server, node, caller, session, surface, database,
lease, sysop, local operator, setup tool, runtime configuration tools, bootstrap record,
key-encryption key, layout, re-plan, occupancy, screen boundary, reconcile, trusted proxy
list, public listener, management listener, actor.

## Contracts
Serves: ADV-001
Provided: none at this level; every contract is provided by a subsystem and listed in its
document. Consumed contracts that no subsystem in this corpus provides are published in the
estate's contracts register by name and version and cited that way.

The subsystems, each with its own document:

| Subsystem | Owns |
|---|---|
| database-access | the bootstrap record, the connection and its transport decision, transactions, the cluster mutex, the database clock, sealing of sensitive values, the mapping of database failures onto error classes |
| access-control | the principals and the one authorisation check every gate calls |
| cluster | the board, servers, leases, the layout, node occupancy, who's-online, server health, version admission, removal, board creation |
| configuration | the settings registry: keys, kinds, scopes, defaults, values, versions, restart-needed reporting |
| audit | the audit entry and the one way to write and read it |
| http | each server's public and management listeners, their connection limits and deadlines, and the routes other subsystems mount |

Programs, each a separate process: the engine; the setup tool, run by the local operator on
the server's host; the runtime configuration tools (command-line and graphical), run on a
server's host, acting as the sysop who logs into them through accounts v1. Which account each
runs as, per protection tier, is database-access's table. Every program reaches the database
only through database-access; no other subsystem holds a connection.

Error classes, used by every contract and owned here:

| Class | Meaning |
|---|---|
| Unavailable | the database could not be reached, the connection was lost, or the operation passed its deadline; a write's outcome is unknown |
| Conflict | a compare-and-set matched nothing, a uniqueness constraint rejected the write, or the database aborted the transaction for contention |
| Refused | a policy check failed; the reason is reported |
| Invalid | an input failed validation |
| Denied | the actor lacks permission, or the permission check itself failed |
| NotFound | the named entity does not exist |
| Fatal | the process cannot run and must stop |

The operation deadline: every transaction a subsystem runs has a deadline of five seconds
(calibration target); a subsystem that needs a different one says so.

What may retry after a failure, and nothing else: database-access re-establishes a lost
connection with backoff; a scheduled job runs again at its next tick; a node claim moves to
the next row after a Conflict; a lease renewal or acquisition that meets a Conflict retries
within its interval, and an admission that finds a live lease waits and retries for the
duplicate-process wait; queued node releases and pending revocations are retried at every
renewal; a settings write that loses the race to create a row retries once. A retried
operator action is a new action and writes a new audit entry.

## Data model
Serves: ADV-001
The database is the board's single source of truth. Properties every subsystem may rely on,
realised by the stack:

- **A transaction** groups reads and writes so that either all of them take effect or none,
  and no other transaction sees a partial result.
- **A compare-and-set** is a write whose predicate names the values it expects; it reports
  whether it changed anything, and a check-then-act is atomic when the check is that
  predicate.
- **Holds**, exclusive and shared, and **compare-and-set** as the glossary defines them; a
  compare-and-set on a row waits for that row's exclusive holder and for nothing else. **The
  cluster mutex** is an exclusive hold on the single board row.
- **A uniqueness constraint** rejects, inside the transaction, a second row with the same
  key; a constraint may apply to rows where a field is set and ignore rows where it is empty.
- **The database clock** is the one time source for every stored timestamp and every
  comparison of times across servers.
- **An increasing identifier**, as the glossary defines it.
- **A login** is what a program authenticates to the database with. A server login is bound
  to one server ID: the database lets it write only that server's own row, layout row and
  node rows, and read everything a server needs. A server login cannot create, disable or
  revoke logins; login administration is one database-side operation, reachable only through
  join v1 and createBoard, that records every login it creates against a server row.
  Disabling a login takes part in the transaction that requests it and refuses new
  connections from commit; ending its open connections and revoking it happen after commit
  and are retried until done. Audit entries are owned by a role no server login holds, so no
  server login can change or delete one; the database administrator's credential, used once
  at first run, is outside this property.
- **A notification** is delivered to every connected server after a commit, at most once,
  and may be lost; nothing in this corpus depends on receiving one.

Hold order, global, so that no two transactions wait on each other: board, then settings
state, then server rows in ascending ID, then layout rows in ascending server ID, then
setting rows in key order, then node rows in ascending number. A transaction takes holds in
that order and never goes back.

Identity sources: server IDs, audit entry IDs and applied-change IDs are increasing
identifiers. Node numbers and layout positions are assigned by cluster's layout operations
under the cluster mutex. Session identifiers come from one source, sessions v1, and are
unpredictable and unique across servers.

Time on a server: a server's own clock is used only for scheduling its own work and for its
local lease deadline; it counts elapsed real time including any period the host was
suspended, and never goes backwards.

## Behaviour
Serves: ADV-001
Start-up order on every server: database-access opens the connection; configuration builds
the registry; cluster checks the version, admits the server and holds its lease; configuration
loads the snapshot; http opens the listeners; only then does any surface accept a caller.
The process states are cluster's.

## Failure directions
Serves: ADV-001
Every gate fails closed: an error, a timeout or "no result" from a permission check, a lease
check or an occupancy check is treated as denial. Database failures are classified by
database-access; only cluster turns them into process states.

## Multi-node invariants
Serves: ADV-001
Nothing a server keeps in memory is truth; each subsystem lists what it caches and when the
cache is invalidated. Any scheduled job may run on every server at once and twice on one
server; each subsystem states why its jobs are idempotent. Only database-access holds a
database connection.

## Audit
Serves: ADV-001
Every state-changing operator action writes an audit entry through audit v1, as audit's
contract requires. An action the engine performs on the local operator's behalf without a
transaction of its own (a change to the bootstrap record, a start) is recorded by the
transaction that first observes it, as cluster states.

## Configuration
Serves: ADV-001
None at this level; each subsystem declares its own keys in the configuration registry and
lists them in its document.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| a caller at a surface | anyone on the network | act beyond a caller's standing | untrusted until a session vouches; every gate calls access-control | Denied |
| a server at the database | anyone holding a server login | act as a server | a login is trusted as a server; the wire is protected by database-access; what a login can create or reach is bounded by the login properties above | no verified transport, no connection |
| the local operator | whoever holds a bootstrap record | act on the board | they hold a server login and are trusted as a server; the setup tool offers them only their server's connectivity, which is convenience and audit, not a boundary | n/a |
| a sysop | an account holding the sysop permission | change the board | trusted as their permissions allow; every action audited | Denied on any check failure |

## Negative tests
Serves: ADV-001
Tests inject database failures (a refused connection, a delayed or dropped write, an aborted
transaction, a rejected login) and clock movement through a controllable connection and clock
that the stack provides, and can open a connection under any server's login, so every
negative test in the subsystem documents can force its dependency to fail. None at this level.

## Revision history
- 2026-09-23: created for ADV-001.

# Architecture
Serves: ADV-001, ADV-002

## Purpose
Serves: ADV-001
The engine is one board run by any number of servers against one database. This document is
the map: which subsystem owns what, the properties every subsystem may rely on from the
database, where identifiers and time come from, the error classes every contract uses, the
order in which entities are held, and the order in which a server starts. Every mechanism
is stated once, in the subsystem that owns it; this document owns only what is shared.

## Terms
Serves: ADV-001, ADV-002
As the estate glossary defines them: board, server, node, caller, session, surface, database,
lease, sysop, local operator, setup tool, runtime configuration tools, bootstrap record,
key-encryption key, layout, re-plan, occupancy, screen boundary, reconcile, trusted proxy
list, public listener, management listener, actor, database-side operation, administrator
credential, Admin API, allow list, host connection, local endpoint, source address, operator
account, credential, settings group, loosening finding, confirmation, relayed action, board
signing key, board identifier; access-control defines the credential ceiling.

## Contracts
Serves: ADV-001, ADV-002
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
| http | each server's public, management and admin listeners and its local endpoint, their connection limits and deadlines, and the routes other subsystems mount |
| sessions | the engine's one home for session handling: the record of operator credentials, their console devices and sign-in attempts, issuing, verifying, expiring and revoking them; the caller sessions of sessions v1 belong here when their feature publishes them |
| admin-api | the Admin API every administration tool reaches the board through: the allow list, connection admission, sign-in, the per-request pipeline, the remote exposure, the relay of an action to another server |

Programs, each a separate process: the engine; the setup tool, run by the local operator on
the server's host; and the administration tools (the runtime configuration tools, the console
and the tools later features add, each command-line or text-mode, and graphical), run on any
computer, which reach the board only through admin-api v1 on any server, acting as the
operator account signed in to them. Which account the engine and the setup tool run as, per
protection tier, is database-access's table. The engine and the setup tool reach the database
only through database-access v1, and no other subsystem holds a connection; an administration
tool holds no database login and makes no permission decision of its own, so every mechanism
the constitution requires once has exactly one implementation, in the engine.

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
Serves: ADV-001, ADV-002
The database is the board's single source of truth. Properties every subsystem may rely on,
realised by the stack:

- **A transaction** groups reads and writes so that either all of them take effect or none,
  and no other transaction sees a partial result. A data-model change takes part in a
  transaction like any write; of two transactions creating the same entity, one commits and
  the other is Conflict.
- **A compare-and-set** is a write whose predicate names the values it expects; it reports
  whether it changed anything, and a check-then-act is atomic when the check is that
  predicate.
- **Holds**, exclusive and shared, and **compare-and-set** as the glossary defines them; a
  compare-and-set on a row waits for that row's exclusive holder and for nothing else. A
  login may take a shared or exclusive hold on any row it may read: a hold is not a write.
  **The cluster mutex** is an exclusive hold on the single board row.
- **A uniqueness constraint** rejects, inside the transaction, a second row with the same
  key; a constraint may apply to rows where a field is set and ignore rows where it is empty.
- **The database clock** is the one time source for every stored timestamp and every
  comparison of times across servers.
- **An increasing identifier**, as the glossary defines it.
- **A login** is what a program authenticates to the database with. The engine and the setup
  tool authenticate with their server's login, except that the setup tool uses the
  administrator credential through database-access's `openWith` at first run, at an upgrade
  and for a secret reset; an administration tool holds no login. Rights come in three tiers, and the database enforces every one:
  - **A server login** is bound to one server ID. It reads everything a server needs. It
    writes directly only these fields of its own server row: lease generation, lease expires
    at, lease timeout used, engine version, operating system and processor architecture,
    transport, database address, trust-anchor fingerprint, record version, started settings
    version, and the reported HTTP fields; and the occupant fields and claim
    generation of the node rows it owns. It inserts audit entries, and it calls the
    database-side operations. The database refuses every other write from it: any other
    field of its own row, another server's row, a node row it does not own, any node row's
    owner or number, an inserted server or node row, the board row, a layout row, a setting
    row, the settings state, an applied-change row, a login row, a credential, console device or
sign-in attempt row, a relayed action row, the remote-administration policy row.
  - **A database-side operation** runs inside the database with the data model owner's
    rights. Every one that an operator action reaches directly takes the actor as an input,
    checks its preconditions against row state or the calling connection, and records its
    own audit entry through audit v1 inside itself, naming the actor it was given and, as
    origin server, the server bound to the login that called it (cluster's Login entity;
    empty under the administrator credential); one reached only from inside another
    operation is recorded by that operation, and one reached both ways records its own
    entry in both cases. A mistaken or forged call therefore cannot corrupt the layout or mint an unrecorded login,
    and what it did is on the record. They are the layout operations (createBoard, addServer,
    setNodeCount, applyReplan, removeServer), completeRemoval, the settings writes
    (`writeSetting`, which configuration's `set` and `setWithin` reach, and `initWithin`),
    cluster's login operations, sessions' credential operations (`endExpired`, `touch`, issue,
    end, revoke, `revokeForAccount`, `revokeForServer`, the attempt operations and the sweep),
    admin-api's relay and policy operations, and applyChanges,
    createBoard and resetSecret, which run only under the administrator credential, a
    precondition the database checks and not only the gate. Any server login may
    call the others, except createLogin, disableLogin and revokeLogin, which the database
    grants to no server login (only their containing operations reach them): a server holding a login can therefore run a registry operation directly, past
    the access-control gate, which is the trust the brief grants a server login; the gate
    bounds the tools and the sysop, and the entry names where the call came from.
    Validating a setting's value against its declaration is the tools' job, not the
    operation's; configuration states how a stored value outside its declaration is read.
  - **The administrator credential** is held by no program. Only under it are the entities,
    constraints, roles and database-side operations created or changed, applied-change rows
    written, and a server's login secret reset.

  Audit entries and applied-change rows are owned by the data model's owner, so no server
  login can change or delete one. The login lifecycle is cluster's, as its login operations
  and removal state; what an engine does about an unapplied change is cluster's version rule.
- **A notification** is delivered to every connected server after a commit, at most once,
  and may be lost; nothing in this corpus depends on receiving one.

Hold order, global, so that no two transactions wait on each other: board, then settings
state, then the remote-administration policy, then server rows in ascending ID, then layout
rows in ascending server ID, then setting rows in key order, then node rows in ascending
number, then login rows in login-name order, then the rows accounts v1, rbac v1 and
second-factor v1 own (in the order their providing feature states), then relayed action rows,
then sign-in attempt rows, then console device rows, then credential rows, each of the last
four in ascending ID. A transaction takes holds in that order and never goes back. Credential
rows are last so that any owner's transaction can revoke an account's or a server's
credentials inside itself. A relayed action's claim and its finish are transactions of their
own, so the handler between them takes its holds afresh.

Identity sources: server IDs, audit entry IDs, credential, console device, sign-in attempt
and relayed action IDs, and the applied-change order are increasing identifiers; a change identifier is fixed by the release that ships it. Node numbers and layout positions are assigned by cluster's layout operations
under the cluster mutex. Session identifiers come from one source, sessions v1, and are
unpredictable and unique across servers.

Time on a server: a server's own clock is used only for scheduling its own work and for its
local lease deadline; it counts elapsed real time including any period the host was
suspended, and never goes backwards.

## Behaviour
Serves: ADV-001, ADV-002
Start-up order on every server: database-access opens the connection; configuration builds
the registry; cluster checks the version and the applied changes, admits the server and holds
its lease; configuration
loads the snapshot; admin-api reads the allow list and resolves its hostnames, and reads its
certificate chain; http opens the listeners, the admin listener only when a chain exists; the
sessions sweep, the relay sweep and the hostname refresh start; only then does any surface
accept a caller.
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
transaction of its own (a change to the bootstrap record) is recorded by the transaction
that first observes it, as cluster states.

## Configuration
Serves: ADV-001
None at this level; each subsystem declares its own keys in the configuration registry and
lists them in its document.

## Security considerations
Serves: ADV-001, ADV-002
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| a caller at a surface | anyone on the network | act beyond a caller's standing | untrusted until a session vouches; every gate calls access-control | Denied |
| a server at the database | anyone holding a server login | act as a server, or beyond one | a login is trusted as a server; the wire is protected by database-access; what it writes directly, what only a database-side operation may do, and what only the administrator credential may do are the login tiers above | no verified transport, no connection; a write outside the tier is rejected |
| the local operator | whoever holds a bootstrap record | act on the board | they hold a server login and are trusted as a server; the setup tool offers them only their server's connectivity, which is convenience and audit, not a boundary | n/a |
| an operator account | an account signed in through admin-api | change the board | trusted as its permissions and its credential's ceiling allow; every action audited with the credential and source | Denied on any check failure |
| an administration tool | whoever runs it, and anyone on the network path | reach the database, or act past a check | a tool holds no database login and decides nothing; admin-api admits, authenticates and authorises every request in the engine | no admission, no request; any check failure refuses it |

## Negative tests
Serves: ADV-001, ADV-002
Tests inject database failures (a refused connection, a delayed or dropped write, an aborted
transaction, a rejected login) and clock movement through a controllable connection and clock
that the stack provides, and can open a connection under any server's login or under the
administrator credential, so every
negative test in the subsystem documents can force its dependency to fail. None at this level.

## Revision history
- 2026-09-23: created for ADV-001.
- 2026-09-23: the graphical runtime configuration tool carries its own database-access and
  access-control implementation, held equal by the shared negative tests.
- 2026-09-23: the administration tools reach the board only through the Admin API; the
  graphical tool's second implementations removed; sessions and admin-api added.

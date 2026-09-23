# Audit
Serves: ADV-001

## Purpose
Serves: ADV-001
The record of every state-changing operator action, written by one operation inside the
action's own transaction so that no action succeeds without its entry, and read by one
operation for the sysop. It decides nothing about what is audited or what a value means;
the owning subsystems do.

## Terms
Serves: ADV-001
As the glossary defines it: actor.

## Contracts
Serves: ADV-001
Provided, **audit v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| record | inside the caller's transaction (a database-side operation calls it inside itself): actor, action name, target server (optional), before, after; the entry ID, occurred at and origin server are filled by the database on every insert, never taken from the caller | none | whatever the transaction reports; the caller's action fails with it |
| list | actor; optional filters: action name, target server, time range; a page size; a cursor (the entry ID to continue below, or none for the newest) | entries in descending entry ID, and the cursor for the next page | Denied, Invalid (page size out of bounds), Unavailable |

`list` requires `audit.read` through access-control v1; any error from that check is Denied.
`record` writes the values it is given; the caller decides what it gives (configuration
passes "changed" for a secret value).

Consumed: access-control v1; database-access v1.

## Data model
Serves: ADV-001
**Audit entry**, append-only: no operation of any subsystem updates or deletes one, and no
server login is granted the right to.

| Field | Meaning |
|---|---|
| entry ID | increasing identifier, the key |
| occurred at | the database clock |
| actor kind | `sysop-account`, `local-operator`, `first-run-operator`, or `engine` (for an entry the engine writes on its own initiative: a start, a fault, a revocation) |
| actor reference | by kind: `sysop-account`, the account; `local-operator`, the server ID acted for; `first-run-operator`, empty; `engine`, the server ID of the process |
| origin server | the server bound to the login the action ran under; empty under the administrator credential |
| action | a name declared by the subsystem that owns the action |
| target server | the server acted upon, if any |
| before, after | the values the action changed, as the owning subsystem defines them |

## Behaviour
Serves: ADV-001
| Input | Outcome |
|---|---|
| `record` inside a transaction that commits | one entry |
| `record` inside a transaction that fails | no entry; the action did not happen |
| `record` inside a transaction that times out | Unavailable; the action and its entry either both exist or neither does |
| `record` while the connection is lost | Unavailable, as above |
| the same action retried after an Unavailable | a new action, a new entry |
| two actions concurrently, on this or another server | two entries; entry IDs order them |
| `list` with a cursor | entries with IDs below the cursor; paging is exact for entries committed before the first page was read, and an entry committed later with a lower ID than the cursor is seen only by a fresh listing |
| `list` with a page size outside its bounds | Invalid |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| the insert fails | the caller's transaction fails; the action does not happen |
| access control errors on `list` | Denied |

## Multi-node invariants
Serves: ADV-001
Entries live only in the database. Nothing is cached. No scheduled job.

## Audit
Serves: ADV-001
None: the audit log does not audit itself.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| page size default | 100 | calibration target | fixed | n/a | not exposed |
| page size maximum | 1,000 | fixed policy backstop | fixed | n/a | not exposed |

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| the audit log | a sysop acting through the tools, or any program | alter or remove entries | append-only, and the database grants no server login the right to change or delete an entry | none needed |
| the audit log | a reader without the permission | learn operator actions | `list` gated on `audit.read` | error means Denied |
| an entry's actor | a holder of any server login | forge an entry naming another actor | accepted: the actor is asserted by a program the board trusts as a server; the origin server, the entry ID and the time are filled by the database, so a forged entry names the server it came from | n/a |

## Negative tests
Serves: ADV-001
- An action whose `record` is forced to fail → the action is rolled back; nothing changed.
- `list` with access control forced to error → Denied.
- `list` by an actor without the permission → Denied.
- An update or delete of an entry attempted with any server login → rejected by the
  database.
- A direct insert under server A's login naming B as origin server, or supplying an entry ID
  or a time → the stored entry carries A, the database's next ID and the database clock.
- `list` with page size 0 or 1,001 → Invalid.
- Two pages with the cursor, with no writer between them → no entry repeated or skipped.

## Revision history
- 2026-09-23: created for ADV-001.

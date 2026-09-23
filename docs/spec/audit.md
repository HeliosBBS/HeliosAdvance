# Audit
Serves: ADV-001

## Purpose
Serves: ADV-001
The record of every state-changing operator action, written by one operation inside the
action's own transaction so that no action can succeed without its entry, and read by one
operation for the sysop.

## Terms
Serves: ADV-001
- **Actor**: who did it: a sysop account, or the local operator of a named server.

## Contracts
Serves: ADV-001
Provided, **audit v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| record | inside the caller's transaction: actor, origin server, action name, target server (optional), before, after | none | whatever the transaction reports; the caller's action then fails with it |
| list | actor; optional filters: action name, target server, time range; a page size | entries, newest first | Denied, Unavailable |

`list` requires the sysop permission through the access-control contract; any error from
that check is Denied.

Consumed: access-control (the accounts feature's), for `list`.

## Data model
Serves: ADV-001
**Audit entry**, append-only; no operation updates or deletes one.

| Field | Meaning |
|---|---|
| entry ID | increasing identifier, the key |
| occurred at | the database clock |
| actor kind | `sysop-account` or `local-operator` |
| actor reference | the account, or the server ID the local operator acted for |
| origin server | the server the action ran on, if any |
| action | a name declared by the subsystem that owns the action |
| target server | the server acted upon, if any |
| before, after | the values the action changed, as the owning subsystem defines them; a value declared secret is recorded as "changed", never as its content |

## Behaviour
Serves: ADV-001
`record` inserts one entry in the caller's transaction. There is no other state.

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| the insert fails | the caller's transaction fails; the action does not happen |
| access control errors on `list` | Denied |

## Multi-node invariants
Serves: ADV-001
Entries live only in the database. Nothing is cached. `record` inside a transaction that runs
twice writes at most one entry, because the transaction commits at most once.

## Audit
Serves: ADV-001
None: the audit log does not audit itself.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Exposed by |
|---|---|---|---|
None.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| the audit log | a sysop covering tracks | alter or remove entries | append-only; no operation changes an entry | none needed |
| the audit log | a reader without the permission | learn operator actions | `list` gated on the sysop permission | error means Denied |
| secret values | anyone reading the log | learn a secret from before or after | secret-declared values are never written | none needed |

## Negative tests
Serves: ADV-001
- An action whose `record` is forced to fail → the action is rolled back; nothing changed.
- `list` with access control forced to error → Denied.
- `list` by an actor without the permission → Denied.
- A secret-declared setting changed → the entry says "changed" and holds no value.

## Revision history
- 2026-09-23: created for ADV-001.

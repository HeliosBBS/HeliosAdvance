# Configuration
Serves: ADV-001

## Purpose
Serves: ADV-001
The settings model every feature with a sysop setting uses: a setting has a key, a kind, a
scope, a default, validation, an apply mode, and a value in the database; a change is
recorded, audited and applied on every server; the tools that show and change settings work
from one registry rather than knowing each key.

## Terms
Serves: ADV-001
- **Registry**: the declared settings, built at start-up from every subsystem's declarations.
- **Scope**: `board` (one value for the board) or `server` (one value per server).
- **Apply mode**: `live` (every server applies the new value without a restart) or `restart`
  (the value is stored now and used by a server from its next start).
- **Snapshot**: a server's in-memory copy of every value it needs.

## Contracts
Serves: ADV-001
Provided, **configuration v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| declare | at start-up only: key, kind, scope, default, validation rule, apply mode, whether the value is secret, whether it is a connectivity setting | none | Invalid (duplicate key: a start-up defect, the process stops) |
| get | key; for a server-scoped key, this server is implied | the value from the snapshot, or the default when no value is stored | none |
| set | actor, key, target server (for a server-scoped key), value | the value stored | Denied, Invalid, NotFound, Unavailable |
| restartNeeded | server | the restart-mode keys, board-scoped or scoped to that server, changed since that server's process started | Unavailable |
| refresh | the settings version reported by the last lease renewal | none | Unavailable |

Gate for `set`: a sysop account through the access-control contract; or the local operator
of the target server, for a server-scoped key declared as a connectivity setting and only
for that server. Any error from the check is Denied.

Consumed: audit v1 (every `set` records `setting.change`); access-control (the accounts
feature's); cluster v1, for the lease renewal that carries the settings version.

## Data model
Serves: ADV-001
**Setting**: one row per stored value.

| Field | Meaning |
|---|---|
| key | as declared |
| scope server | the server, for a server-scoped key; empty for a board-scoped key |
| value | typed as declared; a secret value is encrypted at rest |
| changed at version | the board's settings version this change produced |

Key: (key, scope server). An absent row means the declared default.

**Board** (one row, shared with cluster): `settings version`, an integer that the `set`
transaction increments, so that a server can tell whether its snapshot is behind.

`set` is one transaction: take an exclusive hold on the setting row (creating it if
absent), read the value it replaces, write the new value, increment the board's settings
version, stamp the row with it, record the audit entry. Two sysops changing one key: the
second waits for the first; each entry records the value it truly replaced.

## Behaviour
Serves: ADV-001
| State | Input | Transition |
|---|---|---|
| Snapshot at version v | a lease renewal reports version w > v | reload the whole snapshot from the database; snapshot at w |
| Snapshot at version v | a lease renewal reports version ≤ v | nothing |
| Snapshot at version v | a local `set` commits, producing version w | reload the whole snapshot; snapshot at w (a partial patch is never applied, so a change from another server between v and w is not skipped) |
| any | `get` for a live-mode key | the snapshot's value |
| any | `get` for a restart-mode key | the value the snapshot held when the process started |
| any | `set` with a value failing the declared validation | Invalid; nothing written |
| any | `set` for an undeclared key | NotFound |

A server's process records the settings version it loaded at its first snapshot; that value
is what `restartNeeded` compares against, and it is written once per process start, not per
lease.

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| reload fails | the previous snapshot stays in force; the failure is Unavailable and cluster's process states decide what that means |
| access control errors | Denied |
| audit fails | the `set` rolls back |

## Multi-node invariants
Serves: ADV-001
Values live only in the database. The snapshot is a cache, invalidated by a higher settings
version at a lease renewal or by a local `set`; its staleness is bounded by one lease renewal
interval. The settings version is incremented only inside the transaction that changes a
value, so it never disagrees with the data.

## Audit
Serves: ADV-001
| Action | When | Before | After |
|---|---|---|---|
| `setting.change` | every `set` | the value replaced (or "changed" for a secret) | the value stored (or "changed"), the key, the scope server |

## Configuration
Serves: ADV-001
| Key | Default | Kind | Exposed by |
|---|---|---|---|
None of its own; every key is declared by its owning subsystem.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| `set` | a caller without the permission | change the board | gated on the sysop permission, or on the local operator for that server's connectivity keys only | error means Denied |
| secret values | a reader of the database or the audit log | learn a secret | encrypted at rest; audited as "changed"; never shown by the tools | none needed |
| the snapshot | a server that misses a change | act on a stale value | every renewal carries the version; a change is never missed for longer than one renewal interval | Unavailable stops the server accepting callers (cluster) |

## Negative tests
Serves: ADV-001
- `set` by a local operator of server A on a server-scoped key of server B → Denied.
- `set` by a local operator on a board-scoped key, or on a server-scoped key not declared as
  connectivity → Denied.
- `set` with access control forced to error → Denied; nothing written; no audit entry.
- `set` with audit forced to fail → rolled back.
- Server A sets K1, then server B sets K2 and reloads → B's snapshot holds K1's new value.
- A restart-mode key changed → `restartNeeded` lists the affected server; a server that
  re-acquires its lease without restarting is still listed.
- A secret-declared key changed → the audit entry holds no value; the tools show none.
- A value failing validation → Invalid; the stored value unchanged.

## Revision history
- 2026-09-23: created for ADV-001.

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
As the glossary defines them: registry, scope, apply mode, snapshot, connectivity setting.

## Contracts
Serves: ADV-001
Provided, **configuration v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| declare | at start-up only: key, kind, scope (`board` or `server`), default, validation rule, apply mode (`live` or `restart`), secret (yes or no), connectivity setting (yes or no) | none | Invalid (duplicate key: a start-up defect; the process stops with Fatal) |
| get | key; for a server-scoped key this server is implied | the value from the snapshot, or the default when none is stored | none |
| set | actor, key, target server (for a server-scoped key), value | the value stored | Denied, Invalid, NotFound, Conflict, Unavailable |
| restartNeeded | server | the restart-mode keys, board-scoped or scoped to that server, changed since that server's process loaded its first snapshot | Unavailable |
| refresh | the settings version reported by the last lease renewal | none | Unavailable |
| markStarted | none; called once by the engine after its first snapshot load | none | Unavailable |

Gate for `set`, through access-control v1: `board.administer`; or `server.connectivity` for
the target server when the key is a connectivity setting. Any error from the check is Denied.

Consumed: access-control v1; audit v1 (every `set` records `setting.change`); database-access
v1 (transactions, `seal` and `open` for secret values); cluster.registry v1 (`markStarted`
writes the server's started settings version through it).

## Data model
Serves: ADV-001
**Setting**, one row per stored value:

| Field | Meaning |
|---|---|
| key | as declared |
| scope server | the server, for a server-scoped key; empty for a board-scoped key |
| value | typed as declared; a secret value is stored sealed |
| changed at version | the settings version this change produced |

Key: (key, scope server). An absent row means the declared default.

**Settings state**, exactly one row: `settings version`, an integer increased by every `set`,
so that a server can tell whether its snapshot is behind.

`set` is one transaction, taking holds in the global order: exclusive hold on the settings
state row; then the setting row, held exclusively if present or created if absent (two
concurrent creates of one absent row race on the uniqueness constraint, and the loser gets
Conflict and retries once); read the value it replaces; write the new value (sealed if
secret); increase the settings version; stamp the row; record the audit entry with the
replaced and stored values, or "changed" for a secret. Two sysops changing one existing key:
the second waits for the first, and each entry records the value it truly replaced.

The server's **started settings version** is a field of cluster's Server entity, written once
per process by `markStarted` after the first snapshot load; `restartNeeded` compares against
it.

## Behaviour
Serves: ADV-001
| State | Input | Transition |
|---|---|---|
| Snapshot at version v | a lease renewal reports version w > v | reload the whole snapshot; snapshot at w |
| Snapshot at version v | a lease renewal reports version ≤ v | nothing |
| Snapshot at version v | a local `set` commits, producing version w | reload the whole snapshot; snapshot at w (never a partial patch, so a change from another server between v and w is not skipped) |
| Snapshot at version v | reload fails (Unavailable) | snapshot stays at v; cluster's process states decide what Unavailable means |
| any | `get` for a live-mode key | the snapshot's value |
| any | `get` for a restart-mode key | the value the snapshot held at the first load |
| any | `set` with a value failing validation | Invalid; nothing written |
| any | `set` for an undeclared key | NotFound |
| any | `set` passing its deadline | Unavailable; the write's outcome is unknown; the tool shows the stored value on its next read |
| any | `set` concurrently from two sessions or two servers | serialised by the holds above; both entries written |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| reload fails | the previous snapshot stays in force |
| access control errors | Denied |
| audit fails | the `set` rolls back |
| `seal` fails | the `set` rolls back |

## Multi-node invariants
Serves: ADV-001
Values live only in the database. The snapshot is a cache, invalidated by a higher settings
version at a lease renewal or by a local `set`; its staleness is bounded by one lease renewal
interval. The settings version is increased only inside the transaction that changes a
value, so it never disagrees with the data. No scheduled job of its own; the reload runs
inside cluster's renewal.

## Audit
Serves: ADV-001
| Action | When | Before | After |
|---|---|---|---|
| `setting.change` | every `set` | the value replaced ("changed" for a secret) | the value stored ("changed" for a secret), the key, the scope server |

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
None of its own; every key is declared by its owning subsystem.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| `set` | a caller without the permission | change the board | gated on `board.administer`, or `server.connectivity` for a connectivity setting of that server | error means Denied |
| secret values | a reader of the database or the audit log | learn a secret | stored sealed; audited as "changed"; never shown by the tools | none needed |
| the snapshot | a server that misses a change | act on a stale value | every renewal carries the version; a change is never missed for longer than one renewal interval | Unavailable stops the server accepting callers (cluster) |

## Negative tests
Serves: ADV-001
- `set` by the local operator of server A on a connectivity key of server B → Denied.
- `set` by the local operator on a board-scoped key, or on a server-scoped key that is not a
  connectivity setting → Denied.
- `set` with access control forced to error → Denied; nothing written; no audit entry.
- `set` with audit forced to fail → rolled back.
- `set` with `seal` forced to fail on a secret key → rolled back.
- Server A sets K1, then server B sets K2 and reloads → B's snapshot holds K1's new value.
- A restart-mode key changed → `restartNeeded` lists the affected server; after that server
  re-acquires its lease without restarting, it is still listed.
- A secret key changed → the audit entry holds no value; the stored value is sealed; the
  tools show none.
- A value failing validation → Invalid; the stored value unchanged.
- Two concurrent first `set`s of one absent key → one Conflict retried, both entries written,
  the later value stored.

## Revision history
- 2026-09-23: created for ADV-001.

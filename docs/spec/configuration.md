# Configuration
Serves: ADV-001

## Purpose
Serves: ADV-001
The settings model every feature with a sysop setting uses: a setting has a key, a kind, a
scope, a default, validation, an apply mode, and a value in the database; a change is
recorded, audited and applied on every server; the tools that show and change settings work
from one registry rather than knowing each key. It is not the owner of any setting's
meaning: each subsystem declares its keys and reads its own values.

## Terms
Serves: ADV-001
As the glossary defines them: registry, scope, apply mode, snapshot, connectivity setting.

## Contracts
Serves: ADV-001
Provided, **configuration v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| declare | at start-up only: key, kind, scope (`board` or `server`), default, validation rule, apply mode (`live` or `restart`), secret (yes or no), connectivity setting (yes or no; allowed only with scope `server`) | none | Invalid (duplicate key, or a board-scoped connectivity setting: a start-up defect; the process stops with Fatal) |
| get | key; for a server-scoped key this server is implied | the value from the snapshot; the default when none is stored, or when the stored value fails the declared validation | none |
| set | actor, key, target server (for a server-scoped key), value | the value stored | Denied, Invalid, NotFound, Conflict, Unavailable |
| restartNeeded | server | the restart-mode keys, board-scoped or scoped to that server, changed since that server's process loaded its first snapshot | Unavailable |
| refresh | the settings version reported by the last lease renewal | none | Unavailable |
| read | inside a caller's transaction: key, target server | the stored value; the default when none is stored, or when the stored value fails the declared validation | NotFound |
| setWithin | inside a caller's transaction: actor, key, target server, value | the value stored; takes the settings state hold if the caller has not; records its own entry | whatever the transaction reports |
| initWithin | inside createBoard's transaction | the settings state row, created | Conflict (exists) |
| list | actor, target server | every declared key with its kind, scope, apply mode, default and the stored value for that target (a secret value withheld; a stored value failing validation flagged as invalid) | Denied, Unavailable |

Gate for `set` and `list`, through access-control v1: `board.administer`; or
`server.connectivity` for the target server when the key is a connectivity setting (`list`
then shows only that server's connectivity settings). Any error from the check is Denied.
`read` and `setWithin` run inside another subsystem's transaction and are gated by that
subsystem's operation. `set` is the process-side step (the gate, validation against the
declaration, NotFound for an undeclared key) that calls the database-side write; the write
itself raises no Invalid or NotFound, and a caller of `setWithin` checks the rule for the
key it writes (the layout operations check the HTTP limit's bounds inside themselves). The engine calls cluster.registry v1 `markStarted` once after its
first snapshot load.

Consumed: access-control v1; audit v1 (every `set` and `setWithin` records
`setting.change`); database-access v1 (transactions, `seal` and `unseal` for secret values).

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
concurrent creates of one absent row race on the uniqueness constraint; the loser gets
Conflict and retries once, a fixed backstop, then reports Conflict); read the value it
replaces; write the new value (sealed if secret); increase the settings version; stamp the
row; record the audit entry with the replaced and stored values, or "changed" for a secret.
Two sysops changing one existing key: the second waits for the first, and each entry records
the value it truly replaced. `setWithin` does the same inside the caller's transaction. `set`,
`setWithin` and `initWithin` are database-side operations (the architecture's login tiers):
a server login's direct write to a setting row or the settings state row is refused by the
database, so every stored value carries its entry and moved the settings version.
Validation against the declaration is the tools' job: `set` reports Invalid before writing;
a value a direct call stores outside its declaration is read as the default by `get` and
flagged by `list`, so no reader acts on it.

The server's started settings version is a field of cluster's Server entity; `restartNeeded`
compares against it.

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
| any | the connection lost during `set` | Unavailable; the outcome is unknown until the next read |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| reload fails | the previous snapshot stays in force |
| access control errors | Denied |
| audit fails | the `set` rolls back |

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
| `setting.change` | every `set` and `setWithin` | the value replaced ("changed" for a secret) | the value stored ("changed" for a secret), the key, the scope server |

## Configuration
Serves: ADV-001
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
- `declare` of a board-scoped connectivity setting → Invalid; the process stops.
- `list` by the local operator of server A → only server A's connectivity settings; by a
  sysop → every key with its stored value, secret values withheld.
- `list` with access control forced to error → Denied.
- `set` with access control forced to error → Denied; nothing written; no audit entry.
- `set` with audit forced to fail → rolled back.
- Server A sets K1, then server B sets K2 and reloads → B's snapshot holds K1's new value.
- A restart-mode key changed → `restartNeeded` lists the affected server; after that server
  re-acquires its lease without restarting, it is still listed.
- A secret key changed → the audit entry holds no value; the stored value is sealed; the
  tools show none.
- A value failing validation → Invalid; the stored value unchanged.
- Two concurrent first `set`s of one absent key → one Conflict retried, both entries written,
  the later value stored.
- A direct write of a setting row or the settings state row under a server login, outside
  `set` → rejected by the database; the stored value unchanged.
- `cluster.lease_timeout_renewals` stored as 0 by a direct `set` under a server login → its
  entry exists; every server's `get` returns the default and no lease shortens; an
  acquisition after the store writes expiry = now + the default; `list` shows the stored
  value as invalid; a later valid `set` replaces it.

## Revision history
- 2026-09-23: created for ADV-001.

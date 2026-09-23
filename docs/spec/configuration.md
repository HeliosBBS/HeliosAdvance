# Configuration
Serves: ADV-001, ADV-002

## Purpose
Serves: ADV-001
The settings model every feature with a sysop setting uses: a setting has a key, a kind, a
scope, a default, validation, an apply mode, and a value in the database; a change is
recorded, audited and applied on every server; the tools that show and change settings work
from one registry rather than knowing each key. It is not the owner of any setting's
meaning: each subsystem declares its keys and reads its own values.

## Terms
Serves: ADV-001, ADV-002
As the glossary defines them: registry, scope, apply mode, snapshot, connectivity setting,
settings group, loosening finding, confirmation. This document introduces:

- **revision**: a stored value's `changed at version`; 0 for an absent row.
- **owner-set**: a key only its owning subsystem's operation writes, through `setWithin`.
- **the confirmation rule**: how every loosening is confirmed, stated once under Contracts.

## Contracts
Serves: ADV-001, ADV-002
Provided, **configuration v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| declareGroup | at start-up only: group name, whether it is closed to automation tokens | none | Invalid (duplicate group: a start-up defect; Fatal) |
| declare | at start-up only: key, kind, scope (`board` or `server`), default, validation rule, apply mode (`live` or `restart`), secret (yes or no), connectivity setting (yes or no; allowed only with scope `server`), settings group, loosening rule (none, or a rule from the before and after values to a list of loosening findings), owner-set (yes when only its owning subsystem's operation may write it, through `setWithin`) | none | Invalid (duplicate key, an undeclared group, or a board-scoped connectivity setting: a start-up defect; the process stops with Fatal) |
| groupClosed | a group name | whether it is closed to automation tokens | NotFound |
| get | key; for a server-scoped key this server is implied | the value from the snapshot; the default when none is stored, or when the stored value fails the declared validation | none |
| preview | actor, key, target server, value | the loosening findings the change would have, and their confirmation | Denied, Invalid, NotFound, Unavailable |
| set | actor, key, target server (for a server-scoped key), value, expected revision (optional), confirmation (optional) | the value stored and its revision | Denied, Invalid (an owner-set key), NotFound, Conflict (the expected revision moved), Refused (confirmation required, with the findings), Unavailable |
| lockWithin | inside a caller's transaction: nothing | the settings state held exclusively, for an owner that then takes later holds before `setWithin` | whatever the transaction reports |
| restartNeeded | server | the restart-mode keys, board-scoped or scoped to that server, changed since that server's process loaded its first snapshot | Unavailable |
| refresh | the settings version reported by the last lease renewal | none | Unavailable |
| read | inside a caller's transaction: key, target server | the stored value; the default when none is stored, or when the stored value fails the declared validation | NotFound |
| setWithin | inside a caller's transaction: actor, key, target server, value, confirmed findings (optional) | the value stored; takes the settings state hold if the caller has not; records its own entry | whatever the transaction reports |
| initWithin | inside createBoard's transaction | the settings state row, created | Conflict (exists) |
| writeSetting | the database-side write that `set` and `setWithin` reach: actor, key, target server, value, confirmed findings (optional) | the value stored | Conflict, Unavailable |
| list | actor, target server, a settings group or none | every declared key the actor may read with its kind, scope, apply mode, default, group, whether it has a loosening rule, the stored value for that target and its revision (a secret value withheld; a stored value failing validation flagged as invalid) | Denied, Unavailable |

Gate for `set` and `preview`, through access-control v1: `settings.change` with the key's
settings group as the target, or, when the key is a connectivity setting, `server.connectivity`
for the target server; either suffices. Gate for `list`: `settings.read` for each key's group, a key whose group
is refused being left out; or `server.connectivity` for the target server, `list` then showing
only that server's connectivity settings. Any error from a check is Denied.

The **confirmation rule**, stated here once and used by every owner of a loosening: the
findings are computed by the engine, never taken from the client; the confirmation of a change
is the SHA-256 (FIPS 180-4) of the JSON canonical form (RFC 8785) of the object holding the
operation name, the key or subject, the target, the requested value and the findings sorted by
code then subject; the change is made when it has no findings, or when the confirmation given
equals the one recomputed from the findings found inside the change's own transaction after its
holds are taken; otherwise it is Refused (confirmation required) with the findings, and nothing
is written. The confirmed findings are recorded in the change's audit entry. `set` computes the
findings for a key with a loosening rule after taking the settings state hold, so no change
between its reads and its write goes unjudged.
`read` and `setWithin` run inside another subsystem's transaction and are gated by that
subsystem's operation. `set` is the process-side step (the gate, validation against the
declaration, NotFound for an undeclared key) that calls `writeSetting`, the database-side write, which
itself raises no Invalid or NotFound, and a caller of `setWithin` checks the rule for the
key it writes (the layout operations check the HTTP limit's bounds inside themselves). The engine calls cluster.registry v1 `markStarted` once after its
first snapshot load.

Consumed: access-control v1; audit v1 (every `writeSetting` records
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

**Settings state**, exactly one row: `settings version`, an integer increased by every `writeSetting`,
so that a server can tell whether its snapshot is behind.

`writeSetting` runs in the caller's transaction (`set` opens one of its own; `setWithin` is
the call from inside another operation), taking holds in the global order: exclusive hold on the settings
state row; then the setting row, held exclusively if present or created if absent (two
concurrent creates of one absent row race on the uniqueness constraint; the loser gets
Conflict and retries once, a fixed backstop, then reports Conflict); read the value it
replaces; write the new value (sealed if secret); increase the settings version; stamp the
row; record the audit entry with the replaced and stored values, or "changed" for a secret.
Two sysops changing one existing key: the second waits for the first, and each entry records
the value it truly replaced. `writeSetting` and `initWithin` are database-side operations (the
architecture's login tiers):
a server login's direct write to a setting row or the settings state row is refused by the
database, so every stored value carries its entry and moved the settings version.
Validation against the declaration is the tools' job: `set` reports Invalid before writing;
a value a direct call stores outside its declaration is read as the default by `get` and
flagged by `list`, so no reader acts on it.

The server's started settings version is a field of cluster's Server entity; `restartNeeded`
compares against it.

## Behaviour
Serves: ADV-001, ADV-002
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
| any | `set` of a key with a loosening rule, findings, no confirmation or one that does not match | Refused (confirmation required) with the findings; nothing written |
| any | `set` of a key with a loosening rule, findings, the matching confirmation | written; the entry records the confirmed findings |
| any | `set` with an expected revision that is no longer the stored one | Conflict; nothing written |
| any | `set` of an owner-set key | Invalid, naming the owner's operation; nothing written |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| reload fails | the previous snapshot stays in force |
| access control errors | Denied |
| audit fails | the `writeSetting` rolls back |

## Multi-node invariants
Serves: ADV-001
Values live only in the database. The snapshot is a cache, invalidated by a higher settings
version at a lease renewal or by a local `set`; its staleness is bounded by one lease renewal
interval. The settings version is increased only inside the transaction that changes a
value, so it never disagrees with the data. No scheduled job of its own; the reload runs
inside cluster's renewal.

## Audit
Serves: ADV-001, ADV-002
| Action | When | Before | After |
|---|---|---|---|
| `setting.change` | every `writeSetting`, whether reached through `set`, `setWithin` or directly | the value replaced ("changed" for a secret) | the value stored ("changed" for a secret), the key, the scope server; the confirmed findings, in audit v1's field |

## Configuration
Serves: ADV-001
None of its own; every key is declared by its owning subsystem.

## Security considerations
Serves: ADV-001, ADV-002
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| `set` | a caller without the permission | change the board | gated on `settings.change` for the key's group, or `server.connectivity` for a connectivity setting of that server; an automation token bounded by the credential ceiling | error means Denied |
| a loosening change | a sysop by mistake | open the board without seeing it | the engine computes the findings inside the change's transaction; the change needs the confirmation of exactly those findings, recorded in the entry, which is what exposes a tool that confirms on its own | no matching confirmation, nothing written |
| secret values | a reader of the database or the audit log | learn a secret | stored sealed; audited as "changed"; never shown by the tools | none needed |
| the snapshot | a server that misses a change | act on a stale value | every renewal carries the version; a change is never missed for longer than one renewal interval | Unavailable stops the server accepting callers (cluster) |

## Negative tests
Serves: ADV-001, ADV-002
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
- A change with findings and no confirmation, or a confirmation computed for other findings →
  Refused with the findings; nothing written.
- A confirmation taken, then a concurrent change that alters the findings, then `set` with the
  old confirmation → Refused; nothing written.
- `set` with an expected revision older than the stored one → Conflict.
- `set` of an owner-set key → Invalid; nothing written.
- `list` by an actor allowed `settings.read` for one group only → only that group's keys.
- `declare` naming an undeclared group → Invalid; the process stops.
- An automation token with `listeners` among its change groups setting `http.public_listen` →
  allowed through `settings.change`; without it → Denied, since it holds no
  `server.connectivity`.
- Two concurrent first `set`s of one absent key → one Conflict retried, both entries written,
  the later value stored.
- A direct write of a setting row or the settings state row under a server login, outside
  `writeSetting` → rejected by the database; the stored value unchanged.
- `cluster.lease_timeout_renewals` stored as 0 by a direct `writeSetting` under a server login → its
  entry exists; every server's `get` returns the default and no lease shortens; after that write, an
  acquisition writes expiry = now + the default; `list` shows the stored
  value as invalid; a later valid `set` replaces it.

## Revision history
- 2026-09-23: created for ADV-001.
- 2026-09-23: settings groups, the loosening rule and confirmation, owner-set keys and revisions
  for ADV-002.

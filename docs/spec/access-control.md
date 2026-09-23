# Access control
Serves: ADV-001

## Purpose
Serves: ADV-001
The one authorisation check every gate in the engine calls, and the principals it knows.
Roles, permissions as sysop-editable data, and the authentication of accounts are the
accounts and role-based access control features' work; this document holds only what one
board on many servers needs to gate its operator actions and who's-online.

## Terms
Serves: ADV-001
- **Principal**: who is acting: a **sysop account** (an account holding the sysop
  permission) or the **local operator of server N** (whoever runs the setup tool on server
  N's host).
- **Permission**: a named capability checked by the gate.

## Contracts
Serves: ADV-001
Provided, **access-control v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| authorize | actor (principal), permission, target (a server, or none) | allowed | Denied |

Any failure inside the check, including an unreachable database, is Denied.

Permissions this corpus declares, and who holds them:

| Permission | Holder |
|---|---|
| `board.administer` | a sysop account |
| `server.connectivity` for target server N | the local operator of server N, and a sysop account |
| `server.stop` for target server N | the local operator of server N, and a sysop account |
| `whos_online.view` | any logged-in caller, and a sysop account |
| `audit.read` | a sysop account |

Consumed: sessions v1, to tell whether an actor is a logged-in caller; the accounts feature's
authentication supplies the sysop account principal, published in the contracts register.

## Data model
Serves: ADV-001
None of its own in this corpus; the holder table above is fixed until the role-based access
control feature makes it data.

## Behaviour
Serves: ADV-001
| Input | Outcome |
|---|---|
| a permission the actor holds, target matching where the permission is per server | allowed |
| a permission the actor holds for server N, target server M | Denied |
| a permission the actor does not hold | Denied |
| the check cannot complete (Unavailable, unknown principal, unknown permission) | Denied |
| the same check concurrently from two sessions | independent; no state |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| any | Denied |

## Multi-node invariants
Serves: ADV-001
No state; nothing cached.

## Audit
Serves: ADV-001
None; the actions that pass the gate are audited by their owners.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
None.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| every gate | anyone | act without the permission | one check, called by every gate, with no other path | any failure is Denied |
| the local operator | a holder of server N's bootstrap record | act on the board beyond server N | the permissions above give them only server N's connectivity and stop through the tools; they also hold server N's database login, which is trusted as a server, so the tools' scope is convenience and audit, not a boundary | n/a |

## Negative tests
Serves: ADV-001
- The local operator of server A asking `server.connectivity` for server B → Denied.
- The local operator asking `board.administer` → Denied.
- A caller not logged in asking `whos_online.view` → Denied.
- The check with the database forced unreachable → Denied.
- An unknown permission name → Denied.

## Revision history
- 2026-09-23: created for ADV-001.

# Access control
Serves: ADV-001

## Purpose
Serves: ADV-001
The one authorisation check every gate in the engine calls, and the principals it knows. It
is not a store of roles, not an authentication mechanism, and not the sysop's permission
editor: it holds only the permissions one board on many servers needs to gate its operator
actions and who's-online, as a fixed table.

## Terms
Serves: ADV-001
As the glossary defines them: principal (sysop account, caller, local operator), permission.

## Contracts
Serves: ADV-001
Provided, **access-control v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| authorize | actor (a principal), permission, target (a server, or none) | allowed | Denied |

Any failure inside the check, including an unreachable database or a dependency that cannot
answer, is Denied.

Permissions this corpus declares, and who holds them:

| Permission | Target | Holder |
|---|---|---|
| `board.administer` | none | a sysop account |
| `board.create` | none | the local operator of the host running first-run setup |
| `server.connectivity` | a server | the local operator of that server, and a sysop account |
| `whos_online.view` | none | a caller, and a sysop account |
| `audit.read` | none | a sysop account |

Consumed: sessions v1, which vouches for a caller principal (a live session) and for whether
it is logged in; accounts v1, which authenticates a sysop account principal.

## Data model
Serves: ADV-001
None in the database; the holder table above is this document's data.

## Behaviour
Serves: ADV-001
| Input | Outcome |
|---|---|
| a permission the actor holds; the permission takes no target and none is given | allowed |
| a permission the actor holds for server N; target server N | allowed |
| a permission the actor holds for server N; target server M, or no target | Denied |
| a permission the actor does not hold | Denied |
| an unknown permission name, or an unknown principal kind | Denied |
| the check cannot complete: Unavailable, or sessions v1 or accounts v1 errors or cannot vouch | Denied |
| the same check concurrently from two sessions or two servers | independent; no state |
| a timeout inside the check | Denied |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| any | Denied |

## Multi-node invariants
Serves: ADV-001
No state; nothing cached; no scheduled job.

## Audit
Serves: ADV-001
None; the actions that pass the gate are audited by their owners.

## Configuration
Serves: ADV-001
None.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| every gate | anyone | act without the permission | one check, called by every gate, with no other path | any failure is Denied |
| the local operator | a holder of server N's bootstrap record | act on the board beyond server N | the table gives them server N's connectivity and first-run creation through the setup tool; they also hold server N's database login, which the board trusts as a server, so the table bounds the tool, not the person | n/a |
| a caller | a session that ended or was forged | view who's-online | sessions v1 vouches for the session; no answer means Denied | Denied |

## Negative tests
Serves: ADV-001
- The local operator of server A asking `server.connectivity` for server B → Denied.
- The local operator asking `server.connectivity` with no target → Denied.
- The local operator asking `board.administer` → Denied.
- A caller whose session sessions v1 cannot vouch for asking `whos_online.view` → Denied.
- A caller asking `whos_online.view` with sessions v1 forced to error → Denied.
- A sysop account with accounts v1 forced to error → Denied.
- The check with the database forced unreachable → Denied.
- An unknown permission name → Denied.

## Revision history
- 2026-09-23: created for ADV-001.

# Access control
Serves: ADV-001, ADV-002

## Purpose
Serves: ADV-001, ADV-002
The one authorisation check every gate in the engine calls, the principals it knows, and the
credential ceiling that bounds each kind of operator credential whatever its account holds. It
is not a store of roles, not an authentication mechanism, and not the sysop's permission
editor: its permissions are a table, fixed where this document says so and otherwise answered
by rbac v1.

## Terms
Serves: ADV-001, ADV-002
As the glossary defines them: principal (operator account, sign-in principal, caller, local
operator, first-run operator), permission, credential, settings group. This document introduces:

- **Sysop-role account**: a principal carrying an account (an operator account, or a sign-in
  principal as admin-api defines it) whose account holds role 1, the Sysop role, as rbac v1
  `rolesOf` answers at the time of the check.
- **credential ceiling**: the permissions a kind of operator credential may ever be allowed,
  applied before the holder table.

## Contracts
Serves: ADV-001, ADV-002
Provided, **access-control v1**:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| authorize | actor (a principal), permission, target (a server, a settings group, or none) | allowed | Denied, with its cause: `not held` or `could not complete` |

Any failure inside the check, including an unreachable database or a dependency that cannot
answer, is Denied.

Permissions this corpus declares, and who holds them:

| Permission | Target | Holder |
|---|---|---|
| `board.administer` | none | a Sysop-role account |
| `settings.read` | a settings group | a Sysop-role account |
| `settings.change` | a settings group | a Sysop-role account |
| `board.create` | none | the first-run operator: the principal whose administrator credential the database accepted through database-access v1 `openWith` |
| `board.upgrade` | none | the first-run operator |
| `login.reset` | a server | the first-run operator |
| `server.connectivity` | a server | the local operator of that server, and a Sysop-role account |
| `whos_online.view` | none | a caller that sessions v1 vouches for as logged in, and an operator account holding `tool.console` |
| `audit.read` | none | a Sysop-role account |
| `credentials.manage` | none | a Sysop-role account |
| `tool.config` | none | a Sysop-role account; fixed: no grant reaches another holder |
| `tool.console` | none | a Sysop-role account, and an operator account or sign-in principal one of whose roles rbac v1 `grants` it |
| a permission admin-api `declareAction` declares | none | a Sysop-role account, and an operator account one of whose roles rbac v1 `grants` it |
| a tool permission a later feature declares | none | as that feature states, never fixed to the Sysop role unless it says so |

The credential ceiling, for an operator account; a permission outside it is Denied whatever
the account holds:

| Credential | May be allowed |
|---|---|
| interactive, tool `config` | every permission the table gives an operator account |
| interactive, tool `console` | `tool.console`, `whos_online.view`, and the permissions declared as lying in the console ceiling |
| console token | as interactive with tool `console` |
| interactive, a tool a later feature declares | that tool's permission, and the permissions that feature states for it |
| automation token | `tool.config`; `settings.read` for a group among its read groups; `settings.change` for a group among its change groups that configuration v1 does not declare closed to automation tokens; nothing else |

For an operator account, `authorize` first asks the credential's tool permission,
`tool.<tool>`, then applies the credential ceiling, then the holder table; a caller asks only
for the operation's own permission. An operator account carries its credential (kind,
identifier, label), the source address and the reached server, which audit v1 `record` takes
from the actor.

Consumed: rbac v1 `rolesOf` and `grants`, as admin-api states them; configuration v1's group
declarations (whether a group is closed to automation tokens); sessions v1, whose operations
this document states as the contract until its providing feature publishes it:

| Contract | Operation | Inputs | Outputs | Errors |
|---|---|---|---|---|
| sessions v1 | vouch | a session identifier | the caller reference, the surface, whether the session is logged in | NotFound (no such live session), Unavailable |
| sessions v1 | displayName | a caller reference | the name to show | NotFound, Unavailable |
| sessions v1 | mint | the surface | a session identifier, unpredictable and unique across servers, and a live session that is not yet logged in | Unavailable |
| sessions v1 | end | a session identifier | none; idempotent; releases the node through cluster.nodes v1 | Unavailable |
| sessions v1 | property | | a session ends when its surface's connection closes, when it logs out, or after the idle time sessions v1 owns; per-account concurrent sessions are bounded by sessions v1 before any node claim | |

## Data model
Serves: ADV-001
None in the database; the holder table above is this document's data.

## Behaviour
Serves: ADV-001, ADV-002
| Input | Outcome |
|---|---|
| a permission the actor holds; the permission takes no target and none is given | allowed |
| a permission the actor holds; the permission takes no target and a target is given | allowed; the target is ignored |
| `whos_online.view` for a caller that sessions v1 vouches for but reports not logged in | Denied |
| `board.create`, `board.upgrade` or `login.reset` for any principal but the first-run operator | Denied |
| a permission the actor holds for server N; target server N | allowed |
| a permission the actor holds for server N; target server M, or no target | Denied |
| a targeted permission whose holder is bound to no server (a Sysop-role account, the first-run operator); any named target | allowed |
| a targeted permission whose holder is bound to no server; no target | Denied |
| a permission the actor does not hold | Denied |
| an unknown permission name, or an unknown principal kind | Denied |
| the check cannot complete: Unavailable, or sessions v1, rbac v1 or configuration v1 errors or cannot answer | Denied |
| the same check concurrently from two sessions or two servers | independent; no state |
| a timeout inside the check | Denied |
| an operator account, a permission outside its credential's ceiling | Denied |
| an automation token, `settings.read` or `settings.change` for a group outside the matching set, or `settings.change` for a group closed to automation tokens | Denied |
| `tool.config` for an operator account without role 1, whatever its roles grant | Denied |
| a sign-in principal, its tool's permission | answered for its account by the holder table, with no credential ceiling |
| a sign-in principal, any other permission | Denied |

Every Denied carries its cause: `not held` when the check completed and refused, `could not
complete` when it failed to answer. Every gate refuses both; a caller may treat the second as
Unavailable toward its client.

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
Serves: ADV-001, ADV-002
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| every gate | anyone | act without the permission | one check, called by every gate, with no other path | any failure is Denied |
| the local operator | a holder of server N's bootstrap record | act on the board beyond server N | the table gives them server N's connectivity through the setup tool; they also hold server N's database login, which the board trusts as a server, so the table bounds the tool, not the person | n/a |
| a caller | a session that ended or was forged | view who's-online | sessions v1 vouches for the session; no answer means Denied | Denied |
| an operator credential | whoever holds a console or automation token | use the token beyond its purpose | the credential ceiling and the tool permission are applied inside the one check, before the holder table; `tool.config` is fixed to role 1 | Denied |

## Negative tests
Serves: ADV-001, ADV-002

- The local operator of server A asking `server.connectivity` for server B → Denied.
- The local operator asking `server.connectivity` with no target → Denied.
- The first-run operator asking `login.reset` with no target → Denied; a Sysop-role account
  asking `server.connectivity` with no target → Denied.
- The local operator asking `board.administer` → Denied.
- An operator account, a caller, or a local operator asking `board.create`, `board.upgrade` or
  `login.reset` → Denied.
- A caller vouched for but not logged in asking `whos_online.view` → Denied.
- A caller whose session sessions v1 cannot vouch for asking `whos_online.view` → Denied.
- A caller asking `whos_online.view` with sessions v1 forced to error → Denied.
- An operator account with rbac v1 `rolesOf` or `grants` forced to error → Denied.
- The check with the database forced unreachable → Denied.
- An unknown permission name → Denied.
- A console token asking `board.administer`, `credentials.manage` or `tool.config` → Denied,
  with its account holding role 1.
- An automation token asking `credentials.manage`, `audit.read`, `tool.console` or
  `board.administer` → Denied.
- An automation token asking `settings.change` for a group among its read groups but not its
  change groups → Denied; `settings.read` for that group → allowed.
- An automation token asking `settings.change` for `credential lifetimes`, even if a change
  group → Denied.
- An operator account whose roles rbac v1 says grant everything, without role 1, asking
  `tool.config` → Denied.
- An operator account without role 1 whose role rbac v1 `grants` `tool.console` → allowed
  `tool.console`; with `grants` forced to error → Denied.
- A sign-in principal asking `board.administer` → Denied (`not held`); a sign-in principal for
  `tool.console` with `grants` forced to error → Denied (`could not complete`).

## Revision history
- 2026-09-23: created for ADV-001.
- 2026-09-23: the graphical runtime configuration tool's own implementation of the check.
- 2026-09-23: operator accounts, the credential ceiling, rbac v1 grants and the ADV-002
  permissions; the graphical tool's own implementation removed.

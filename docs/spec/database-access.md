# Database access
Serves: ADV-001

## Purpose
Serves: ADV-001
Every program's one way to the database: the bootstrap record on a server's disk, the
connection and how its transport is decided, transactions, the cluster mutex, the database
clock, the sealing of sensitive values under the key-encryption key, and the mapping of
database failures onto error classes. It exists so that the database wire is protected in one
place and the board's root of trust is guarded once.

## Terms
Serves: ADV-001
As the glossary defines them: bootstrap record, key-encryption key, loopback address, local
socket.

## Contracts
Serves: ADV-001
Provided, **database-access v1**, to every subsystem and program:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| open | none; the record is read from its fixed location on the host | a connection | Fatal (record missing, malformed or over-exposed; login rejected; transport cannot be established as the record requires), Unavailable (no answer yet; the connection keeps being attempted) |
| transaction | the work to do; a deadline (the operation deadline unless the caller states another) | the work's result | Unavailable, Conflict, and whatever the work reports |
| now | inside a transaction | the database clock |  |
| lockBoard | inside a transaction | the cluster mutex, held until the transaction ends | Unavailable |
| seal | a value | the value encrypted under the key-encryption key | Fatal (no key) |
| open (value) | a sealed value | the value | Invalid (not sealed under this key) |
| reachable | none | whether the last operation succeeded |  |
| recordFields | none | the record's non-secret fields: server ID, database address, transport | Fatal |
| writeRecord | the setup tool only: the fields to change | none | Fatal (cannot write at the required tier), Invalid |

Consumed: none.

## Data model
Serves: ADV-001
The **bootstrap record**, one per server host:

| Field | Meaning |
|---|---|
| server ID | the identity this server runs as; empty until the board is created or joined |
| database address | an address literal, a name, or a local socket |
| database login and secret | this server's own login; sensitive |
| trust anchor | what the database's certificate must chain to; empty when the transport is `plaintext` |
| transport | `tls` or `plaintext` |
| key-encryption key | the board's key for values sealed at rest; sensitive |

The record is written by the setup tool (first run, join, and any later change to restore
connectivity) and read by the programs on that host. The transport is valid only as follows:
`tls` with an address literal or a name; `plaintext` only with a loopback address literal or a
local socket. A local socket is always `plaintext`, because it carries no name to verify.

Protection tier, by host:

| Host | Tier | Who can read |
|---|---|---|
| Windows | encrypted by the operating system's per-machine data protection | the service account and members of the host's Administrators group |
| Linux, with a credential store in the service manager | held in that store | the service, and the host's superuser |
| any other | a file with permissions for one account | the service account, and the host's superuser |

A program refuses to start (Fatal) when the record is missing, malformed, or readable by any
account other than those listed for its tier. The setup tool, which runs with the host's
administrative rights, can read and write the record under every tier and reports which tier
it used; the runtime configuration tools run on a server's host as the service account or an
administrator and read that host's record.

Failure classes, mapped here and nowhere else:

| Database report | Class |
|---|---|
| connection refused, lost, or no answer within the deadline | Unavailable |
| a transaction aborted by the database for contention with another | Conflict |
| a constraint or uniqueness violation | Conflict |
| login rejected after a successful transport handshake | Fatal |
| the transport cannot be established as the record requires (certificate does not chain, name mismatch, plaintext to a non-local address) | Fatal |
| the handshake cut off by the network before it completes | Unavailable |
| any other error the database reports | Unavailable |

Sealed values: a value sealed under the key-encryption key can be opened only with that key;
the key never enters the database; the sealed form is what configuration stores for a secret
setting.

## Behaviour
Serves: ADV-001
Opening the connection, from `open` and again on every reconnect after loss; the decision
depends only on the record and the handshake, never on anything read from the database, and
no credential is sent before it is settled:

| State | Input | Transition |
|---|---|---|
| Reading record | record valid | → Connecting |
| Reading record | record missing, malformed, over-exposed, or transport invalid for the address | → Fatal, naming the fault |
| Connecting, `tls` | handshake completes and the certificate chains to the trust anchor and names the address | → Authenticating |
| Connecting, `tls` | certificate does not chain, or name mismatch | → Fatal; never plaintext |
| Connecting, `tls` | handshake cut off by the network | Unavailable; retry with backoff; stay Connecting |
| Connecting, `plaintext` | loopback address literal or local socket | → Authenticating over plaintext |
| Connecting | no answer within the connect deadline | Unavailable; retry with backoff; stay Connecting |
| Authenticating | login accepted | → Open |
| Authenticating | login rejected | → Fatal |
| Open | connection lost | → Connecting; the full decision runs again |
| any | a second `open` from the same process | the same connection; no second decision |
| any | the record changed on disk while the process runs | ignored until the process restarts; the setup tool restarts the engine after writing the record |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| record unreadable or over-exposed | closed: the program does not start |
| TLS cannot be verified | closed: no plaintext fallback, ever |
| plaintext to a non-local address | closed: the record is invalid |
| database unreachable | Unavailable to every caller until it returns; cluster decides what that means for the server |
| deadline passed | Unavailable; the write's outcome is unknown and the caller treats it so |
| no key-encryption key | Fatal at `seal`; a program without the key cannot run |

## Multi-node invariants
Serves: ADV-001
Nothing here is board state. The connection and its state are process-local. The record is
per host and reaches another host only through the join v1 contract.

## Audit
Serves: ADV-001
None here. Changes the setup tool makes to the record are recorded by cluster at the server's
next admission (cluster's Audit, `server.record.change`).

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| connect retry backoff | one second, doubling to the lease renewal interval | calibration target | fixed | | not exposed |
| connect deadline | the lease renewal interval | calibration target | fixed | | not exposed |

The record's fields are not settings; the setup tool changes them on the host, and the
runtime configuration tools show each server's transport and address as cluster reports them.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| the database wire, `tls` | anyone on the network path | read or alter credentials, hashes, messages | TLS verified against the record's trust anchor and the address; a failed verification never downgrades | no verified transport, no connection |
| the database wire, `plaintext` | a process on the same host that binds the loopback endpoint or local socket while the database is down | receive the server's login | not closed: the local operator chose plaintext on this host knowing this, and the setup tool says so when the choice is made; the endpoint is reachable only from the host | none; accepted by the local operator's choice |
| the bootstrap record | a local user, a thief of the disk, a backup | take the login and act as a server | protected at the host's tier; the program refuses to run an over-exposed record; the record holds nothing but what reaching the database needs | over-exposed means the program does not start |

## Negative tests
Serves: ADV-001
- Record readable by an account outside its tier → the program does not start; the fault is
  named.
- `tls` with a certificate that does not chain to the trust anchor → does not start; the test
  observes no plaintext connection attempt.
- `tls` with a certificate for another name → does not start.
- `plaintext` with a non-loopback address literal or a name → does not start.
- `plaintext` with a loopback address → connects; the transport reported is `plaintext`.
- Connection lost while open, then the database returns with a certificate that no longer
  verifies → Fatal; no plaintext attempt.
- Connection lost while open, then the handshake is cut off twice by the network before
  succeeding → Unavailable meanwhile, then Open; no Fatal.
- Login rejected → Fatal, not a retry loop.
- No answer within the connect deadline → callers see Unavailable; the connection is retried
  with backoff and succeeds when the database answers.
- `seal` without a key → Fatal; `open` of a value sealed under another key → Invalid.

## Revision history
- 2026-09-23: created for ADV-001.

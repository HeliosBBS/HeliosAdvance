# Database access
Serves: ADV-001

## Purpose
Serves: ADV-001
Every program's one way to the database: the bootstrap record on a server's disk, the
connection and how its transport is decided, transactions, the cluster mutex, the database
clock, and the mapping of database failures onto error classes. It exists so that the
database wire is protected in one place and the board's root of trust is guarded once.

## Terms
Serves: ADV-001
- **Bootstrap record**: the file on a server's disk that holds what the server needs to reach
  the database, and nothing else (see Data model).
- **Loopback address**: an address literal that the host's network stack delivers only to the
  host itself; **local socket**: a connection endpoint the host's operating system exposes
  only to processes on that host.

## Contracts
Serves: ADV-001
Provided, **database-access v1**, to every subsystem and program:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| open | none (the bootstrap record is read from its fixed location) | a connection, or the reason it cannot be made | Fatal (record missing, malformed or over-exposed; credentials rejected; transport refused), Unavailable |
| transaction | a deadline; the work to do | the work's result | Unavailable, Conflict, and whatever the work reports |
| now | inside a transaction | the database clock's time | none |
| lockBoard | inside a transaction | the cluster mutex, held until the transaction ends | Unavailable |
| reachable | none | whether the last operation succeeded | none |
| recordFields | none | the record's non-secret fields: server ID, database address, transport | Fatal |

Consumed: none.

## Data model
Serves: ADV-001
The **bootstrap record**, one per server, on that server's disk:

| Field | Meaning |
|---|---|
| server ID | the board-assigned identity this server runs as |
| database address | where the database is; an address literal or a name, or a local socket |
| database login and secret | this server's own login, created by the join feature; sensitive |
| trust anchor | what the database's certificate must chain to |
| transport | `tls` or `plaintext`; `plaintext` is only valid with a loopback address or a local socket |
| key-encryption key | the board's key for fields encrypted at rest; sensitive |

The record is written only by the setup tool (first run and join) and read only by the
programs on that host. Its protection is the operating system's best available tier:

| Host | Tier |
|---|---|
| Windows | encrypted by the operating system's per-machine data protection, readable by the service account and the host's administrators |
| Linux with a credential store in its service manager | held in that store, readable by the service |
| any other | a file readable only by the service account |

A program refuses to start (Fatal) when the record is missing, malformed, or readable by any
account other than the service account and the host's administrators. The setup tool reports
which tier it used.

Failure classes are mapped here and nowhere else:

| Database report | Class |
|---|---|
| connection refused, lost, or no answer within the deadline | Unavailable |
| a transaction aborted by the database for contention with another | Conflict |
| a constraint or uniqueness violation | Conflict |
| credentials rejected after a successful transport handshake | Fatal |
| the transport could not be established as the record requires | Fatal |
| any other error the database reports | Unavailable |

A transaction is never retried by database-access; the caller decides.

## Behaviour
Serves: ADV-001
Opening the connection, from `open` and again on every reconnect after loss:

| State | Input | Transition |
|---|---|---|
| Reading record | record valid | → Connecting |
| Reading record | record missing, malformed, over-exposed | → Fatal, naming the fault |
| Connecting, transport `tls` | handshake succeeds and the certificate chains to the trust anchor and names the address | → Authenticating |
| Connecting, transport `tls` | handshake fails, certificate does not chain, or name mismatch | → Fatal; never plaintext |
| Connecting, transport `plaintext` | address is loopback or a local socket | → Authenticating over plaintext |
| Connecting, transport `plaintext` | address is anything else | → Fatal ("plaintext is permitted only to a loopback address or a local socket") |
| Connecting | no answer within the connect deadline | retry with backoff, indefinitely, stay Connecting; the caller sees Unavailable meanwhile |
| Authenticating | login accepted | → Open |
| Authenticating | login rejected | → Fatal |
| Open | connection lost | → Connecting (the full decision runs again) |

No credential is sent before the transport decision is settled, and the decision depends
only on the record and the handshake, never on anything read from the database.

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| record unreadable or over-exposed | closed: the program does not start |
| TLS cannot be established or verified | closed: no plaintext fallback, ever |
| plaintext to a non-local address | closed |
| database unreachable | Unavailable to every caller until it returns; cluster decides what that means for the server |
| deadline passed | Unavailable; the write's outcome is unknown and the caller treats it as unknown |

## Multi-node invariants
Serves: ADV-001
Nothing here is board state. The connection and its state are process-local. The record is
per host and never copied to another host except by the join feature.

## Audit
Serves: ADV-001
None. Changes to the record are made by the setup tool and audited by cluster as
local-operator actions (see cluster's Audit).

## Configuration
Serves: ADV-001
| Key | Default | Kind | Exposed by |
|---|---|---|---|
| connect retry backoff | one second, doubling to the lease renewal interval | calibration target | none (fixed) |
| connect deadline | the lease renewal interval | calibration target | none (fixed) |
The transport is a field of the bootstrap record, changed only by the setup tool on the host;
the runtime configuration tools show each server's transport as cluster reports it.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| the database wire | anyone on the network path | read or alter credentials, hashes, messages | TLS verified against the record's trust anchor and the address; plaintext only to loopback or a local socket, chosen by the local operator on that host; a failed verification never downgrades | no transport, no connection |
| the bootstrap record | a local user, a thief of the disk, a backup | take the credentials and act as a server | OS-protected as above; the program refuses to run an over-exposed record; the record holds nothing but what reaching the database needs | over-exposed means the program does not start |
| a local impostor on the database port | a local user while the database is down | receive the server's credentials | with `tls` the impostor cannot present a certificate that chains to the trust anchor; with `plaintext` the record's own choice was made by the local operator, on that host, knowing this | verification failure is Fatal |

## Negative tests
Serves: ADV-001
- Record readable by another account → the program does not start; the fault is named.
- `tls` with a certificate that does not chain to the trust anchor, on a loopback address →
  does not start; no plaintext connection is attempted (the test observes the wire).
- `tls` with a certificate for another name → does not start.
- `plaintext` with a non-loopback address → does not start.
- `plaintext` with a loopback address → connects; the transport reported is `plaintext`.
- Connection lost while open, then the database returns with a certificate that no longer
  verifies → stays unavailable; no plaintext attempt.
- Login rejected → Fatal, not a retry loop.
- No answer within the connect deadline → callers see Unavailable; the connection is
  retried with backoff and succeeds when the database answers.

## Revision history
- 2026-09-23: created for ADV-001.

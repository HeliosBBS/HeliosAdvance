# HTTP
Serves: ADV-001

## Purpose
Serves: ADV-001
Each server's HTTP listeners: the public listener that callers reach, and the management
listener that serves detailed health to a proxy. The per-server connection limits and the
deadlines that keep a slow client from holding a connection are properties of a listener,
whatever route a request reaches, so they live here. It serves no route of its own and
decides nothing about what a route may reveal.

## Terms
Serves: ADV-001
As the glossary defines them: public listener, management listener. **Open connection**: an
accepted connection counted against a listener's limit.

## Contracts
Serves: ADV-001
Provided, **http v1**, to subsystems on the same server:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| mount | listener (`public` or `management`), path prefix, handler; at start-up only | none | Invalid (duplicate prefix; a start-up defect: the process stops with Fatal) |
| inUse | listener | open connections on that listener | none |
| limit | listener | that listener's connection limit | none |

Consumed: configuration v1, for the keys below.

## Data model
Serves: ADV-001
None in the database. Process-local: the count of open connections per listener, starting
at zero with the process, increased on accept below the limit and decreased on close.

## Behaviour
Serves: ADV-001
For each listener:

| State | Input | Transition |
|---|---|---|
| Listening | connection arrives, count below limit | accept; count + 1 |
| Listening | connection arrives, count at limit | accept and close at once, nothing sent; count unchanged |
| Listening | two connections arrive at once with one place left | one accepted, one closed; the count never exceeds the limit |
| Connection open | request headers not complete within the header deadline | close; count − 1 |
| Connection open | request body makes no progress for the body deadline | close; count − 1 |
| Connection open | a response write makes no progress for the write deadline | close; count − 1 |
| Connection open | idle for the idle deadline | close; count − 1 |
| Connection open | client closes | count − 1 |
| Listening | limit lowered below the count | no new accepts until the count is below the new limit |
| Connection open | the same client opens a second connection | counted separately; no per-client rule here |
| Starting | a listener's address cannot be bound | the process stops (Fatal), naming the address |

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| at the limit | closed: refuse |
| slow client | closed: the deadlines free the connection |
| bind failure | closed: the process does not start |

## Multi-node invariants
Serves: ADV-001
Nothing here is board state; the counts describe this process's sockets only.

## Audit
Serves: ADV-001
None here; the keys below are audited by configuration as setting changes.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| `http.public_listen` | every address of the host, port 80 | sysop tunable; connectivity setting; an address literal or the wildcard address, and a port from 1 to 65,535 | server | restart | setup tool, runtime configuration tools |
| `http.management_listen` | the loopback address, port 8443 | sysop tunable; connectivity setting; the same validation | server | restart | setup tool, runtime configuration tools |
| `http.connection_limit` | 256 | sysop tunable; at least 1, at most 65,535 (fixed backstops); written at first run and join through configuration v1 `setWithin` | server | live | runtime configuration tools |
| management connection limit | 64 | fixed policy backstop | fixed | n/a | not exposed |
| header deadline | ten seconds | calibration target | fixed | n/a | not exposed |
| body deadline, per write without progress | sixty seconds | calibration target | fixed | n/a | not exposed |
| write deadline, per write without progress | sixty seconds | calibration target | fixed | n/a | not exposed |
| idle deadline | sixty seconds | calibration target | fixed | n/a | not exposed |

Neither listener carries a credential or serves anything that needs one.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| public listener | a flooder | hold every connection | the limit, plus header, body, write and idle deadlines, so a connection is held only by a client that is actually talking | at the limit, refuse |
| management listener | a host on the management network, or the internet if the sysop bound it there | exhaust the process's sockets, or read detailed health | its own fixed limit, the same deadlines, loopback by default; detailed health is further gated by cluster's trusted proxy list | at the limit, refuse |
| any listener | a client relying on a forwarded address | impersonate a trusted address | a listener reports the connection's own peer address to the handler and nothing else; a handler that wants a forwarded address consults a contract that owns that decision | none needed |

## Negative tests
Serves: ADV-001
- Public connections at the limit → the next is accepted and closed with nothing sent; after
  one closes, the next is served.
- Management connections at 64 → the 65th is closed with nothing sent.
- A client that sends no headers → closed at the header deadline; the count drops.
- A client that sends headers and then trickles a body → closed at the body deadline.
- A client that never reads the response → closed at the write deadline.
- The limit lowered below the open count → no accept until the count drops below it.
- A management request from a non-loopback address with the default binding → never arrives.
- A bind failure on either listener → the process does not start and names the address.

## Revision history
- 2026-09-23: created for ADV-001.

# HTTP
Serves: ADV-001

## Purpose
Serves: ADV-001
Each server's HTTP listeners: the public listener that the web surface and the public API will
mount on, and the management listener that serves detailed health to a proxy. The per-server
HTTP connection limit and the deadlines that keep a slow client from holding a connection are
properties of the listener, so they live here, whatever route a request reaches.

## Terms
Serves: ADV-001
- **Public listener**: the listener callers reach. **Management listener**: the listener the
  sysop binds to an address only a proxy or an administrator can reach.
- **Slot**: one accepted connection counted against the limit.

## Contracts
Serves: ADV-001
Provided, **http v1**, to subsystems on the same server:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| mount | listener (`public` or `management`), path prefix, handler; at start-up only | none | Invalid (duplicate prefix; a start-up defect, the process stops) |
| inUse | none | connections currently open on the public listener | none |
| limit | none | the public listener's connection limit | none |

Consumed: configuration v1, for the keys below.

## Data model
Serves: ADV-001
None in the database. Process-local: the count of open public connections, starting at zero
with the process, incremented on accept below the limit and decremented on close.

## Behaviour
Serves: ADV-001
| State | Input | Transition |
|---|---|---|
| Listening | connection arrives, count below limit | accept; count + 1 |
| Listening | connection arrives, count at limit | accept and close at once, nothing sent; count unchanged |
| Connection open | request headers not complete within the header deadline | close; count − 1 |
| Connection open | request body not complete within the body deadline | close; count − 1 |
| Connection open | response not written within the write deadline | close; count − 1 |
| Connection open | idle beyond the idle deadline | close; count − 1 |
| Connection open | client closes | count − 1 |
| Listening | limit lowered below the count | no new accepts until the count is below the new limit |
| Starting | a listener's address cannot be bound | the process stops (Fatal), naming the address |

The management listener has no connection limit and the same deadlines; its default address
is loopback, and the sysop binds it elsewhere only on purpose.

## Failure directions
Serves: ADV-001
| Failure | Direction |
|---|---|
| at the limit | closed: refuse |
| slow client | closed: the deadlines free the slot |
| bind failure | closed: the process does not start |

## Multi-node invariants
Serves: ADV-001
Nothing here is board state; the count describes this process's sockets only.

## Audit
Serves: ADV-001
None here; the keys below are audited by configuration as setting changes.

## Configuration
Serves: ADV-001
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| `http.public_listen` | all interfaces, one port the stack chooses for an unencrypted development listener | sysop tunable | server | restart | setup tool (connectivity), runtime configuration tools |
| `http.management_listen` | loopback, one port | sysop tunable | server | restart | setup tool (connectivity), runtime configuration tools |
| `http.connection_limit` | set at join | sysop tunable | server | live | runtime configuration tools |
| header deadline | ten seconds | calibration target | fixed | | |
| body deadline | sixty seconds | calibration target | fixed | | |
| write deadline | sixty seconds | calibration target | fixed | | |
| idle deadline | sixty seconds | calibration target | fixed | | |

The public listener carries no credential and serves nothing that needs one until the web
caller feature defines its transport security; until then its only route is the minimal
health route cluster mounts.

## Security considerations
Serves: ADV-001
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| public listener | a flooder | hold every slot | the limit, plus header, body, write and idle deadlines, so a slot is held only by a client that is actually talking | at the limit, refuse |
| management listener | an internet client | read detailed health | bound to loopback unless the sysop binds it to a management network; detailed health is further gated by cluster's trusted proxy list | loopback by default |
| any listener | a client relying on a forwarded address | impersonate a trusted address | listeners report the connection's own peer address; forwarded-address headers are not consulted by anything in this document | none needed |

## Negative tests
Serves: ADV-001
- Connections at the limit → the next is accepted and closed with nothing sent; after one
  closes, the next is served.
- A client that sends no headers → closed at the header deadline; the slot is free.
- A client that sends headers and then trickles a body → closed at the body deadline.
- A client that never reads the response → closed at the write deadline.
- The limit lowered below the open count → no accept until the count drops below it.
- A management-listener request from a non-loopback address with the default binding →
  never arrives (the test proves the default binding is loopback).
- A bind failure on either listener → the process does not start and names the address.

## Revision history
- 2026-09-23: created for ADV-001.

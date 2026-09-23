# HTTP
Serves: ADV-001, ADV-002

## Purpose
Serves: ADV-001, ADV-002
Each server's HTTP listeners: the public listener that callers reach, the management
listener that serves detailed health to a proxy, and the admin listener and local endpoint that
carry the Admin API. Connection limits and the deadlines that keep a slow client from holding a
connection are properties of a listener, whatever route a request reaches, so they live here.
It serves no route of its own and decides nothing about what a route may reveal or who a
connection may be.

## Terms
Serves: ADV-001, ADV-002
As the glossary defines them: public listener, management listener, open connection, local
endpoint, host connection, source address; admin-api defines the admin listener and the channel
binding value.

## Contracts
Serves: ADV-001, ADV-002
Provided, **http v1**, to subsystems on the same server:

| Operation | Inputs | Outputs | Errors |
|---|---|---|---|
| mount | listener (`public`, `management`, `admin` or `local`), path prefix, handler; at start-up only | none | Invalid (duplicate prefix; a start-up defect: the process stops with Fatal) |
| admission | at start-up only, for `admin` and `local`: the function called at accept with the peer address (for `local`, the connecting account the operating system reports), before any byte is read, answering close, admit (with the source address and whether it is a host connection), or read; on read, it is called again with up to the first 512 bytes the peer sent, read within the header deadline, answering close or admit | none | Invalid (set twice: Fatal) |
| certificate | at start-up only, for `admin`: the function that gives the chain to present | none | Invalid (set twice: Fatal) |
| channelBinding | a connection on `admin` or `local` | its channel binding value, as admin-api defines it | none |
| inUse | listener | open connections on that listener | none |
| limit | listener | that listener's connection limit | none |

The `admin` listener speaks TLS 1.3 only (RFC 8446) and HTTP/1.1 only, and closes a connection
that offers early data; it runs the admission function after accepting and before the TLS
handshake reads anything, closes when it answers close, and passes the handler the source address and host flag it answered. The
`local` endpoint is one per host, restricted by the operating system to the engine's service
account and the host's administrators, and reports the connecting account; it carries HTTP/1.1
without TLS, runs the admission function the same way, and sets the `Hadv-Channel-Binding`
header on every answer. No listener reads a forwarding header.

Consumed: configuration v1, for the keys below.

## Data model
Serves: ADV-001
None in the database. Process-local: the count of open connections per listener, starting
at zero with the process, increased on accept below the limit and decreased on close.

## Behaviour
Serves: ADV-001, ADV-002
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
| Listening, `admin` or `local` | admission answers close at accept | close with nothing read; count − 1 |
| Listening, `admin` or `local` | admission answers read, then close | close before the TLS handshake; count − 1 |
| Listening, `admin` | the TLS handshake not complete within the handshake deadline, or early data offered | close; count − 1 |
| Listening, `admin` | a client offering TLS 1.2 or lower | the handshake fails; close; count − 1 |
| Listening, `local` | the operating system refuses the connecting account | never accepted |
| Starting | the `admin` listener has no chain from its certificate function | the `admin` listener does not open, the reason is logged; the other listeners and `local` open |

## Failure directions
Serves: ADV-001, ADV-002
| Failure | Direction |
|---|---|
| at the limit | closed: refuse |
| slow client | closed: the deadlines free the connection |
| bind failure | closed: the process does not start |
| no chain for the `admin` listener | closed: the `admin` listener does not open; the others do |
| the admission function errors | closed: the connection is closed |

## Multi-node invariants
Serves: ADV-001
Nothing here is board state; the counts describe this process's sockets only.

## Audit
Serves: ADV-001
None here; the keys below are audited by configuration as setting changes.

## Configuration
Serves: ADV-001, ADV-002
| Key | Default | Kind | Scope | Apply | Exposed by |
|---|---|---|---|---|---|
| `http.public_listen` | every address of the host, port 80 | sysop tunable; connectivity setting; an address literal or the wildcard address, and a port from 1 to 65,535; settings group `listeners` | server | restart | setup tool, runtime configuration tools |
| `http.management_listen` | the loopback address, port 8444 | sysop tunable; connectivity setting; the same validation; settings group `listeners` | server | restart | setup tool, runtime configuration tools |
| `admin_api.listen` | every address of the host, port 8443 (TCP) | sysop tunable; connectivity setting; the same validation; settings group `remote administration`; any change is a loosening, whose finding names the address the Admin API will listen on | server | restart | setup tool, runtime configuration tools |
| `http.connection_limit` | 256 | sysop tunable; at least 1, at most 65,535 (fixed backstops); written at first run and join through configuration v1 `setWithin`; settings group `listeners` | server | live | runtime configuration tools |
| management connection limit | 64 | fixed policy backstop | fixed | n/a | not exposed |
| admin connection limit, local endpoint connection limit | 64 each | fixed policy backstop | fixed | n/a | not exposed |
| TLS handshake deadline on `admin` | ten seconds | calibration target | fixed | n/a | not exposed |
| admission peek | at most 512 bytes | fixed policy backstop | fixed | n/a | not exposed |
| header deadline | ten seconds | calibration target | fixed | n/a | not exposed |
| body deadline, per write without progress | sixty seconds | calibration target | fixed | n/a | not exposed |
| write deadline, per write without progress | sixty seconds | calibration target | fixed | n/a | not exposed |
| idle deadline | sixty seconds | calibration target | fixed | n/a | not exposed |

Neither the public nor the management listener carries a credential or serves anything that
needs one; the admin listener and the local endpoint carry admin-api's. This document declares
the settings group `listeners`, which an automation token may change. The local endpoint's place
on the host is fixed and not a setting.

## Security considerations
Serves: ADV-001, ADV-002
| Surface | Attacker | Abuse | Decision | Fails closed |
|---|---|---|---|---|
| public listener | a flooder | hold every connection | the limit, plus header, body, write and idle deadlines, so a connection is held only by a client that is actually talking | at the limit, refuse |
| management listener | a host on the management network, or the internet if the sysop bound it there | exhaust the process's sockets, or read detailed health | its own fixed limit, the same deadlines, loopback by default; detailed health is further gated by cluster's trusted proxy list | at the limit, refuse |
| any listener | a client relying on a forwarded address | impersonate a trusted address | the public and management listeners report the connection's own peer address and nothing else; the admin listener and the local endpoint report the source address admin-api's admission answered; no listener reads a forwarding header | none needed |
| admin listener | anyone on the internet | reach TLS or HTTP parsing unadmitted | admission runs before any TLS byte is read; TLS 1.3 only, no early data | close |
| local endpoint | a local account that is not the service's or an administrator's | reach the Admin API as the host | the operating system refuses the connection, and admission checks the account it reports | refused, or closed |

## Negative tests
Serves: ADV-001, ADV-002
- Public connections at the limit → the next is accepted and closed with nothing sent; after
  one closes, the next is served.
- Management connections at 64 → the 65th is closed with nothing sent.
- A client that sends no headers → closed at the header deadline; the count drops.
- A client that sends headers and then trickles a body → closed at the body deadline.
- A client that never reads the response → closed at the write deadline.
- The limit lowered below the open count → no accept until the count drops below it.
- A management request from a non-loopback address with the default binding → never arrives.
- A bind failure on either listener → the process does not start and names the address.
- Admin connections at 64 → the 65th is closed with nothing sent.
- An admission function answering close → the connection closed before the handshake reads a
  byte.
- A TLS 1.2 client, or a client offering early data, on the admin listener → closed; no request
  served.
- An admitted client that opens the admin listener and sends nothing → closed at the TLS
  handshake deadline; an unadmitted one → closed at accept with nothing read.
- A local endpoint connection from an account other than the service's or an administrator's →
  never served.
- The default management listener → bound to loopback port 8444, and the admin listener to
  port 8443.

## Revision history
- 2026-09-23: created for ADV-001.
- 2026-09-23: the admin listener and local endpoint for ADV-002; the management listener's
  default port moved to 8444.

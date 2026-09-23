# ADV-001 Servers, nodes and one board

Status: approved. Brainstorm record: https://github.com/HeliosBBS/HeliosDesign/discussions/1

## Purpose

One board, run by as many servers as the sysop wants, on whatever hardware, operating system
and CPU each server happens to be, with every caller seeing the same board no matter which
server they reached. Nodes are numbered once across the whole board, so "node 8" means the
same thing to a user, a sysop and a log line, and the sysop sizes each server to its own
hardware. The board grows by adding a server or by giving a server more nodes, and a server
can die, be upgraded or be removed without the others noticing beyond its callers dropping
off who's-online.

## Behaviour

### Servers and the board

- When a server starts with a valid identity and database connection, the system shall
  register it under its board-wide server ID and display name and admit it to the board.
- When a server's engine version is within one minor version of the board's minimum, the
  system shall admit it; if it is older than the database's minimum version, then the server
  shall refuse to start and state the version required.
- When the sysop changes a board-wide setting on any server, the system shall apply it on
  every server without a restart, or state that a restart is needed where the setting
  requires one.
- When the sysop removes a server, the system shall end that server's sessions, retire its
  node range, and keep its ID unused for ever.
- While any number of servers run on any mix of operating systems and CPU architectures, the
  board shall behave identically for every caller.

### Nodes

- When a server is configured with a node count, the system shall assign it a contiguous
  range of board-wide node numbers following the ranges already assigned, and shall keep that
  range until the sysop re-plans the layout.
- If the sysop re-plans the layout while a caller is on an affected node, then the system
  shall refuse the re-plan and say which nodes are in use.
- When a caller logs in on a server with a free node, the system shall give them the lowest
  free node in that server's range.
- If a caller reaches a server with no free node, then the system shall show the theme's busy
  screen and end the connection.
- When a web caller logs in, the system shall take a node for their session; while a web
  caller is not logged in, they shall occupy no node.
- When a server's HTTP connections reach its HTTP connection limit, the system shall refuse
  further HTTP connections on that server until one closes.

### Liveness

- While a server runs, it shall renew its lease in the database on the lease interval.
- If a server's lease expires, then the system shall free its nodes, end its sessions, and
  remove its callers from who's-online on every server within the lease timeout.
- When any caller or sysop views who's online, the system shall show every caller on every
  server as one board.

### The database

- If the database becomes unreachable from a server, then that server shall refuse new
  callers, end each existing session after its current screen, and resume without operator
  action when the database returns.
- While a server talks to the database, it shall do so over TLS with the database's
  certificate verified; if the database is on the same host and the sysop has explicitly
  allowed it, then plaintext shall be permitted.
- While a server holds per-server settings, they shall live in the database keyed by that
  server; a server's disk shall hold only its identity, its own database credentials and the
  board's key-encryption key, protected by the operating system's best available tier.

### Health

- When a proxy or the sysop asks a server for its health, the system shall report whether
  its lease is live, its nodes in use of its count, and its HTTP connections in use of its
  limit.

## Security decisions

1. **The database wire.** Attacker: anyone on the network between a server and the database.
   Abuse: reading password hashes, messages and session data in transit, or altering them.
   Decision: TLS with the database's certificate verified; plaintext only same-host and by
   explicit sysop choice, visible in the configuration tools. Why: secure by default, with the
   one loosening a single-machine board reasonably wants. Fails closed: a server that cannot
   establish TLS does not start.
2. **The database credentials are the board's root of trust.** Attacker: whoever obtains them.
   Abuse: they are a server, with everything a server can do. Decision: this feature does not
   weaken that; the join feature is the only gate that hands them out, and a server's local
   file holds nothing beyond its identity, its own credentials and the key-encryption key. Why:
   one trust boundary, guarded once. Fails closed: no credentials, no server.
3. **A misbehaving or misconfigured server.** Attacker: a server that lies about its node
   count, renews a lease it should not, or claims nodes outside its range. Abuse: exhausting
   the board's node numbers or evicting another server's callers. Decision: node ranges are
   assigned by the board from configured counts, never claimed by the server; a node is only
   ever taken within the taker's own range, checked atomically in the database; a server can
   only renew its own lease. Why: a server holding credentials is trusted, but mistakes are
   contained to the mistaken server. Fails closed: a node claim outside the range is refused.
4. **Node exhaustion by a caller.** Attacker: an anonymous caller opening many connections.
   Abuse: taking every node on a server, or every HTTP connection, so nobody else gets in.
   Decision: the per-server HTTP connection limit bounds web traffic; a node is taken only at
   login, so unauthenticated traffic never consumes one; per-source connection limits and
   throttling are the Telnet, SSH and web caller features' decisions and are named there. Why:
   the node model must not be the thing that makes a flood cheap. Fails closed: at the limit,
   refuse.
5. **The health endpoint.** Attacker: an anonymous caller timing an attack or mapping the
   board. Abuse: learning exactly how full each server is and when. Decision: health detail is
   served to the sysop and to addresses on the trusted proxy list; to anyone else it says only
   whether the server is up. Why: a load balancer needs the numbers, the public does not.
   Fails closed: no trusted list, no numbers.
6. **Lease timing as a weapon.** Attacker: anyone who can delay a server's database writes.
   Abuse: making a healthy server's lease expire so its callers are dropped. Decision: the
   lease timeout is three missed renewals, a sysop tunable with a calibration target of a few
   seconds, and an expiry ends sessions rather than leaving ghosts, because a wrongly dropped
   caller reconnects while a ghost node stays taken. Why: fail toward freeing capacity, never
   toward holding it. Fails closed: expired means gone.
7. **Audit.** Adding a server, removing one, changing a node count or an HTTP limit,
   re-planning the layout, and allowing plaintext to the database are operator actions, and
   each writes an audit entry with actor, server, and before and after values.

## Limits

| Limit | Kind | Default |
|---|---|---|
| Node count per server | sysop tunable, per server | set at join; no fixed maximum beyond the hardware |
| HTTP connection limit per server | sysop tunable, per server | set at join |
| Lease renewal interval | calibration target | a few seconds |
| Lease timeout | sysop tunable | three missed renewals |
| Version skew between servers | fixed policy backstop | one minor version |
| Plaintext to the database | sysop tunable, off | same-host only |
| Health detail to untrusted callers | fixed policy backstop | up or down, nothing more |

## Non-goals

- Redirecting or handing a caller from a full server to another; a proxy in front of the
  board does that, and a redirect feature may come later.
- Sharding, replication or more than one database; the board has one, and its fault
  tolerance is the proxy's job, documented in the sysop guide.
- Servers with different themes, settings or behaviour; every server is the same board.
- Any degraded mode without the database.
- Joining a server to the board, which is its own feature.

## Repositories and contracts affected

- Engine only. Introduces the health endpoint, which the proxy feature and the load tester
  will consume; it is registered in the contracts register when the design fixes its shape,
  owner-first.
- Nothing in the Door Kit, HeliosDoors, the Portal or the SIP gateway.

## Open questions

None.

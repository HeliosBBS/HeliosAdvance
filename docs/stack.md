# The stack

The technology decisions behind the engine, recorded once here and nowhere in the
specifications. The specifications in `docs/spec/` are language-neutral and must read the
same if this file changed; this file says how each property they state is realised.

## Languages

- **Go** for the engine (`hadv-service`) and every command-line and text-mode utility.
- **Lua** for the scripting layer: theme scripts reach the engine only through the public
  `bbs.*` API.
- **Free Pascal with Lazarus** for the cross-platform graphical utilities, which have feature
  parity with their text-mode counterparts except where a platform makes something
  impossible. They are Admin API clients: HTTP/1.1 over TLS 1.3 through Lazarus's HTTP client
  on OpenSSL 3, with the pin check the Admin API states in place of ordinary certificate
  verification for a `board-signed` board, and JSON through FPC's own units; no database driver
  and no permission logic. The graphical console's device key stores are stated under The Admin
  API below. FPCUnit tests cover the pin check, the
  loosening confirmation flow and the secret handling. The developer writes the forms; a model
  writes only the non-visual Pascal.

## The database

**PostgreSQL 18 or later** is the board's single database: 18 is the floor because the
normalised display name needs the database's Unicode case folding, which arrived in 18. The
development compose file and CI run the current 18 image. How the specifications' database
properties map onto it:

| Property in the specs | Realisation |
|---|---|
| one transaction | a PostgreSQL transaction at the default isolation level unless a spec section says otherwise |
| compare-and-set | an update whose predicate names the expected values, checked by rows affected |
| the cluster mutex | an exclusive row lock on the single board row, taken for the transaction |
| a row locked exclusively / shared | row-level locks on the entity's row |
| the database clock | the transaction's start time as the database reports it |
| a database-generated increasing identifier | a sequence |
| the inter-server bus (a commit-gated, best-effort notification to every connected server) | LISTEN/NOTIFY; a proxy in front of the database must pool in session mode for it to work |
| the encrypted-at-rest fields | encrypted by the engine under the board's key-encryption key before they are written |
| TLS to the database, certificate verified | the connection's TLS mode set to verify the server certificate against the trust anchor in the server's bootstrap record |
| an entity | a table; a field a column; a key a primary key or unique index; a constraint a database constraint wherever the database can express it, else enforced inside the owning transaction |
| a server login | a PostgreSQL role per server, with row-level security policies that bind its direct writes to its own server row and the node rows it owns, and grants that reach nothing else |
| a database-side operation | a `SECURITY DEFINER` function owned by the schema-owning role, granted to the server roles, checking its preconditions before it writes |
| the administrator credential | the schema-owning role's credential, held by no program; `hadv-setup` prompts for it at first run and at an upgrade |
| the normalised display name | `normalize(casefold(normalize(name, NFD)), NFC)` inside the layout operation, so the database's own Unicode tables apply |

Schema changes are numbered, transactional, additive-only migrations that ship with the
engine and are applied by `hadv-setup` under the schema owner at first run and at an
upgrade, never by the engine at start-up; the board's minimum engine version is raised only
by a migration that needs it.

## The Admin API

- **Server**: Go's `crypto/tls` with `MinVersion` and `MaxVersion` at TLS 1.3 and no session
  tickets that permit early data, the channel binding value from
  `ConnectionState().ExportKeyingMaterial`; `net/http` with HTTP/2 disabled; the admission
  function run on the raw `net.Conn` before `tls.Server`, peeking through a buffered reader.
  PROXY protocol v1 and v2 parsing is home-grown (the formats are small, and a dependency would
  sit on the pre-authentication path).
- **Local endpoint**: on Linux a Unix domain socket in the service's runtime directory, mode
  0660 with the group `hadv-admin` that installation creates, in a runtime directory the service
  manager creates for the service at each start, the connecting account read with
  `SO_PEERCRED` and its groups looked up from that user ID, and admitted when it is user 0, the
  service's own user, or a member of `hadv-admin`; the runtime directory is mode 0750, owned by
  the service's user with group `hadv-admin`; the sysop guide says how to add an administrator
  to that group; on
  Windows a named pipe created with `FILE_FLAG_FIRST_PIPE_INSTANCE` and
  `PIPE_REJECT_REMOTE_CLIENTS`, whose security descriptor admits the service account and
  Administrators,
  the connecting account read from the impersonated client token and admitted when it is the
  service account or its enabled groups include Administrators, so only an elevated session is
  the host; the sysop guide says the tools on the host must run elevated.
  The Pascal graphical tools reach the local endpoint and check its serving account the same
  way through the same platform interfaces.
  A tool checks the serving account before it sends anything: on Windows through
  `GetNamedPipeServerProcessId` and that process's token, on Linux through `SO_PEERCRED` on its
  own socket; either must be the service account. Both through `golang.org/x/sys` (BSD).
  The tools use whichever their platform has.
- **DNSSEC**: a validating stub built on `github.com/miekg/dns` (BSD-3-Clause) for message
  encoding and signature primitives; the validation chain is home-grown; the root anchors ship
  with the engine and change only with a release. Its cost-benefit is written in the plan's
  dependency task.
- **Console keys**: ECDSA P-256. Windows: CNG through the Microsoft Platform Crypto Provider
  (the TPM) with export disallowed, else the Microsoft Software Key Storage Provider, whose
  keys the user's DPAPI protects. Linux: the TPM through the kernel resource manager
  (`/dev/tpmrm0`) when the user can open it, through `github.com/google/go-tpm` (Apache-2.0),
  else the Secret Service over D-Bus through `github.com/godbus/dbus` (BSD-2-Clause), else no
  console token. Both are pinned and get their cost-benefit in the plan's dependency task: TPM
  2.0 command marshalling and D-Bus are large protocols where a home-grown implementation would
  be security code with no benefit. The graphical console uses, on Windows, the same two
  CNG providers as the Go console through the platform interface; on Linux, the Secret Service
  through `libsecret` (LGPL-2.1-or-later, dynamically linked as the system library, never bundled or
  modified, its licence audit written in the plan's dependency task), with no TPM tier: a stated
  exception to parity, because a TPM 2.0 client in Pascal would be large security code for a
  tier the Secret Service already covers; where no Secret Service is reachable, no console
  token, and the graphical console signs in at every launch.
- **Canonical JSON** for the confirmation (RFC 8785): home-grown, since the values are the
  engine's own.

## Build and tooling

`make check` is the one definition of green: build, vet, lint, tests (race detector where a C
compiler exists), vulnerability scan, and, where the repository holds a Lazarus project, its
`lazbuild` build and FPCUnit tests. Supported targets: `linux/amd64`, `linux/arm64`,
`windows/amd64`. Builds are reproducible and stamped with the exact commit; releases carry a
build-provenance attestation and a software bill of materials.

## Deferred

Chosen when the feature that needs them is designed, and recorded here then: the HTTP/3
implementation (for the web caller; the Admin API never uses HTTP/3), the SSH implementation, the Lua runtime, the TOML reader for language files,
the terminal-user-interface toolkit, the installer tooling per platform.

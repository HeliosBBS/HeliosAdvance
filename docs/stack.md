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
  impossible. A Lazarus program cannot link the engine's packages, so the graphical runtime
  configuration tool holds the second implementation of database-access v1 and of the
  access-control check that the architecture permits: libpq (the PostgreSQL licence) through
  Lazarus's SQLdb, with the connection's TLS mode set to verify the server certificate against
  the record's trust anchor and the protocol floor at TLS 1.2; the record read at the host's
  tier through the platform's data-protection interface; FPCUnit tests over the same
  negative-test tables the engine's tests use. The developer writes the forms; a model writes
  only the non-visual Pascal.

## The database

**PostgreSQL** (a current major release; the minimum supported version is recorded here when
the first release is cut) is the board's single database. How the specifications' database
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

Schema changes are numbered, transactional, additive-only migrations that ship with the
engine and are applied by `hadv-setup` under the schema owner at first run and at an
upgrade, never by the engine at start-up; the board's minimum engine version is raised only
by a migration that needs it.

## Build and tooling

`make check` is the one definition of green: build, vet, lint, tests (race detector where a C
compiler exists), vulnerability scan, and, where the repository holds a Lazarus project, its
`lazbuild` build and FPCUnit tests. Supported targets: `linux/amd64`, `linux/arm64`,
`windows/amd64`. Builds are reproducible and stamped with the exact commit; releases carry a
build-provenance attestation and a software bill of materials.

## Deferred

Chosen when the feature that needs them is designed, and recorded here then: the HTTP/3
implementation, the SSH implementation, the Lua runtime, the TOML reader for language files,
the terminal-user-interface toolkit, the installer tooling per platform.

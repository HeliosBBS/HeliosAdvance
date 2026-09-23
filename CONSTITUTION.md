# Constitution

The first file every skill, prompt and loop iteration loads, before anything else and in the
same form every time. It is short on purpose. Anything that needs more words than this belongs
in a spec, a skill or the wiki, and cites this file rather than restating it.

## 1. Authority runs from features down

The developer authors and owns feature briefs, in `features/`. Everything else in the design
corpus is derived from them: the architecture, the subsystem specs, the plans, the tests. A
derived document serves features and says which, by ID, section by section. A feature with
nothing implementing it and a section serving no feature are both defects, and tooling finds
them.

When a derived document and a feature disagree, the feature wins, or the developer amends the
feature. Nothing amends a feature except the developer.

Subsystems exist because features demand them, and the developer never has to think in them.
The design skill decides placement, creates a subsystem when features require one, and the
developer may overrule a placement without ever starting from it.

A generic description ("a BBS that supports Telnet and SSH") is the normal entry point. It is
decomposed into candidate features first, each with a purpose and the repositories it touches.
Nothing derived from a generic description enters a spec until that feature has had its own
brainstorm and been approved.

The developer's attention goes where an error costs most: every brief and every plan is read in
full; diffs are spot-checked and reviewed by models. Everything shown to the developer is in
feature terms and in chunks short enough to read.

## 2. Security is designed in, never reviewed in afterwards

Every feature brief carries its threat model: the attacker at each surface, the abuse cases,
and what fails closed. A mechanism is chosen by the developer from concrete shapes offered with
their tradeoffs, the way the node-join pairing code was chosen: a code shown on a separate
channel, fitting the security need exactly.

Access gates fail closed on any error. Auth, RBAC, session handling and event fan-out each have
exactly one implementation. Every state-changing operator action writes an audit entry. Every
permission check has a negative-path test that forces its dependency to fail and asserts denial.
A regression test is verified against the reverted fix before it counts.

## 3. Multi-node from the start

Anything that runs as a service runs as several cooperating nodes against one store, and every
design assumes it:

- identifiers that cannot collide across nodes;
- jobs that are idempotent, because any job may run twice;
- no in-memory truth: what a node remembers, another node cannot see;
- check-then-act is atomic, in one transaction or one compare-and-set;
- every cache and every counter states its invalidation rule.

## 4. The estate and its contracts

Six projects are developed together, and each other's needs are inputs to every feature:

| Project | Role | Owns | Consumes |
|---|---|---|---|
| HeliosAdvance | the BBS engine | the public JSON API and its OpenAPI description | the door wire protocol's host side |
| HeliosDoorKit | wire protocol and SDKs for BBS doors | the door wire protocol | nothing from the engine |
| HeliosPortal | web client with an address book for many boards | its own UI | the public JSON API |
| HeliosSIP | SIP-to-SSH gateway for dial-up over VoIP | its own gateway | SSH or Telnet, nothing more |
| HeliosLoadTest | load-test harness for a running board | its own drivers | the engine's client surfaces |
| HeliosDoors | doors built on the Door Kit | the doors | the Door Kit SDK |

They were carved out on one principle, and it holds for anything else that leaves the engine:
**a separate project's interface to the engine is a protocol, a wire format, or nothing.**

An interface changes in the repository that owns it, with a version. Consumers pin a version. A
change that crosses repositories lands owner-first, with contract tests on both sides. A feature
spanning repositories has one brief, in the repository that owns the user-visible behaviour,
and linked work in the others.

## 5. Spec rules

A spec is a reconstruction contract: a developer or a model builds the software from the corpus
alone, tests included, and specs are detailed enough that Sonnet 5 at high effort builds most
of it with a stronger model reviewing.

- **Self-contained.** Nothing outside the corpus except public standards and the contracts
  other Helios projects publish, cited by name and version. No process files, issue or PR
  numbers, hashes, dated rulings or provenance in a body. A revision history is allowed only
  as the last section: dated, one-line, past-tense entries.
- **Language-agnostic.** The stack is named once, in the architecture, as a decision. No
  language idiom anywhere else.
- **Storage as logical schema plus stated properties**: atomic check-then-act, a cluster
  mutex, error classes, identity and time sources, and a best-effort, commit-gated
  notification bus. One physical PostgreSQL mapping, in the architecture.
- **Every number says its kind**: a fixed policy backstop, a calibration target, or a sysop
  tunable with its default and key. A sysop tunable is a setting the board's operator changes.
- **No language that goes stale.** No self-counts, no "the only exception", no "currently".
- **One corpus template**, so the same thing sits in the same place in every document.
- **Each mechanism stated once, in its owner**, and cited by contract name everywhere else.
- **Changes are deltas.** A spec change is written as ADDED, MODIFIED and REMOVED requirement
  blocks, each with its scenarios, and merges into the spec on acceptance. An edit is always
  surgical and reviewable; a whole-document rewrite happens only as a ruled regeneration.
- **No open questions in a finished spec.**

## 6. Standing exception

The VirtualNET wire format is a separate specification, supplied ahead of the transport's
implementation. Its transport feature depends on that specification existing and is blocked,
not designed around, until it does.

## 7. How this file is used

Loaded first, unchanged, by every skill, every prompt and every loop iteration. A change to it
is a pull request the developer approves, and nothing else edits it.

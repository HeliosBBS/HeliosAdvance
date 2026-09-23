# CLAUDE.md

Read `CONSTITUTION.md` first; the estate's shared constitution arrives through the `helios`
plugin before it. This file is the working rules that follow. Anything local to one machine
lives in the gitignored `CLAUDE.local.md`, never here: this file is public. Both files stay
short: a rule earns a line here only if a hook, a skill or the code cannot carry it.

## Project

Helios Advance BBS is a modern bulletin board system in the spirit of VBBS and VADV. A
scripting layer carries all BBS logic, so a sysop (the operator of a running board) swaps
scripts to change the whole personality without touching engine source. The terminal
experience feels authentically classic; the internals are uncompromisingly modern; the
scripting layer is the bridge. Secure by default and by design.

One developer, a three-to-four-year project, seven repositories under `HeliosBBS` developed
together. Developer time is the scarcest resource: the tooling breaks work down, the model
builds, the developer reviews briefs and plans in full and diffs by sample.

## Layout

| Path | Holds |
|---|---|
| `CONSTITUTION.md` | what is specific to the engine; the shared principles come from the plugin |
| `features/` | feature briefs, one file per feature, developer-owned |
| `docs/spec/` | the derived corpus: `architecture.md` and one file per subsystem, language-neutral |
| `docs/stack.md` | the stack decision (languages, database, physical mapping, tooling); never cited by a spec |
| `docs/sysop/` | the board operator's guide, published to GitHub Pages |
| `cmd/`, `internal/` | the engine's Go source |
| `automation/` | the unattended loop |
| `Makefile` | `make check` runs everything CI runs; `make bootstrap` stands up the dev box |

The skills, hooks and contracts register come from the `HeliosSkills` plugin; the issue form,
labels and reusable workflows from `HeliosBBS/.github`; `work` from `HeliosTools`. The wiki
holds the runbook and learnings, unreviewed and disposable by design. `HeliosDesign` (private)
holds design conversations and brainstorm transcripts.

## The pipeline

`feature-brainstorm` (brief, approved, zero open questions) → `feature-design` (the delta,
clean-room challenge, critic, developer approval section by section) → `feature-plan` (gap
analysis against the code, a checklist a session executes without judgment, the analyze gate,
written into the issue) → `feature-build` (one task per iteration, fresh context, own worktree,
red/green, `make check`, two-stage review, tick, stop) → `compound` (the learning goes where the
next session reads it). Each is a gate the next cannot pass without. Approving an idea approves
nothing that does not exist yet. A feature is done only after verification through its real
surface, never from unit tests alone.

## Work tracking

GitHub Issues are the record; the issue form is the shape; `work` is how agents read and write
them (`refresh`, `next`, `claim`, `tick`, `close`, `lint`). Labels: `P0`–`P3`, `kind:*`,
`claimed`, `blocked`, `human-action-required`, `security-sensitive`, `unattended-loop`. The plan
checklist is a gate: no code until it is in the issue; boxes ticked with a short comment;
closing needs every box ticked or struck with a reason, the PR linked, the write-up last. A
security-sensitive issue describes the work without the exploit path; specifics go in a
private advisory.

## Routing

Sonnet 5 at high effort is the default, not a floor and not a ceiling: every model and effort
level is available and the task's shape picks it. Route down (Haiku, or Sonnet at low) for
mechanical work with one right answer; route up (Opus, or Fable in-session) when reasoning is
left in the task. The plan tags each task's tier. Route-up is decided by code, never by
self-report: tests fail twice with different fixes, the gutter detector fires, an unplanned
security-sensitive path appears, the diff outgrows the plan; then one tier up with the failed
attempt's notes, and a second failure is a human-action item. Review is never downgraded:
Opus or stronger reviews every task, the hostile reviewer anything security-sensitive. A Fable
pin on a subagent can be silently served by Sonnet, so Fable-level work runs in-session and
every pinned dispatch is verified from the transcript.

## Branches and identity

GitFlow, with `main` and `development` as the two long-lived branches. `main` is the default
branch and holds the skeleton and releases only, each a signed SemVer tag; cutting a release
is a human checkpoint and is when the AGPLv3 section 13 source offer attaches, so the exact
commit must exist here. `development` is the integration branch: everything lands through a
pull request that closes its issue, through the merge queue, on green required checks.
`feature/issue-<n>-<slug>` branches come off `development`, live in their own worktree and are
deleted on merge; `release/vX.Y.Z` is cut from `development`, merged into `main` and tagged,
then merged back; `hotfix/vX.Y.Z` comes off `main` and merges both ways. The loop commits as
the organisation's App, never as the developer, so the developer's review of its work is a
real gate. Commit atomically and push as soon as a unit is verified; never end a session with
verified work uncommitted or unpushed.

## Rules

- **Secrets** never enter code, tests, config or CI; push protection is on; a committed secret
  is rotated at the source, not deleted from history.
- **Hooks enforce the mechanical rules.** `features/`, `CONSTITUTION.md` and the licences are
  developer-owned; edits are formatted; a turn does not end on a red `make check`.
- **`make check` is the only definition of green**; the loop, the stop hook and CI all call it.
  A session starts with `make bootstrap` and a green baseline before touching anything.
- **Tests first.** Every change ships with the test that fails without it. Table-driven,
  `t.Parallel()` where independent, real sockets and temp files rather than I/O mocks, the
  race detector in CI. Every permission check has a negative-path test; a regression test is
  proved against the reverted fix.
- **Errors are never swallowed**: checked, wrapped with context, classified at boundaries;
  access gates fail closed.
- **Every I/O takes a context with a deadline**; cancellation is honoured; shutdown drains.
- **Validate at trust boundaries** (user input, the network, sysop scripts, doors, peers),
  trust internal code; least privilege everywhere; parameterised queries only.
- **Observability**: `log/slog` only, structured, with a correlation ID per session or job;
  never log a secret, password, token or code. Every queue, limit and counter is measurable.
- **Config is part of the feature**: defaults in code, overrides from the config file, every
  key documented with its kind; a sysop setting is done only when both configuration tools
  expose it, in the same PR as the code. **Secure by default**: every default is the safe
  setting, and loosening it is the sysop's explicit choice in those tools.
- **Schema changes are additive**, numbered, transactional, `IF NOT EXISTS`; never edit a
  committed migration.
- **Home-grown first.** The ladder decides, in order: does it need to exist, is it already in
  the codebase, does the standard library or the platform do it, does an installed dependency
  do it, can it be one line, then write it. A new dependency needs a written cost-benefit
  (what it saves, what it exposes) in its PR, is pinned, audited for licence, and
  `govulncheck`-clean; CI fails on a flagged vulnerability.
- **Public prose runs through `humanizer`** before it lands: README, sysop guide, release
  notes, issue write-ups, Discussions, and any comment long enough to carry a voice.
- **Builds are reproducible** and stamped with the exact commit; releases carry provenance
  and an SBOM.
- **Lang strings** use named tags (`{TAG_NAME}`), never positional arguments.
- **Refactor on discovering an architectural flaw** rather than building on it.
- **Questions:** one at a time. **Pushback:** with reasoning, never an echo.

## Bug classes to check explicitly

Recurring shapes ordinary review misses; every review prompt names them.

1. Fail-open error handling: a gate that checks the result and ignores the error.
2. A nullable column scanned into a non-pointer field.
3. A string identifier that does not match its source of truth; prefer a constant.
4. Send on a closed channel in fan-out code.
5. A doc comment asserting the opposite of the behaviour.
6. Security-critical logic duplicated across surfaces.
7. A multi-step database operation without a transaction.
8. A state-changing operator action with no audit entry.
9. A regression test that still passes when the fix is reverted.

## Code style

- Go for the engine, Lua for the scripting layer, Free Pascal (Lazarus) for the cross-platform
  GUI tools; `docs/stack.md` is where that is decided, and the specs never say it.
- Allman braces in every language except Go. Names readable without knowing abbreviations
  (`sessionID`, not `sid`); an abbreviation passes only if it is common across C, Pascal and
  Go alike.
- **Comments.** One test per line: does the reader learn something the code cannot tell them?
  No: don't write it. Yes: it is a why (the constraint that forced this shape, an invariant or
  unit, an external gotcha, the source of a magic value), self-contained, naming constructs
  rather than line numbers or filenames, stating the constraint rather than pointing at a spec
  section. Banned: restatement, narration, changelog, reviewer reassurance, the docstring that
  repeats the signature. A complex function may need several lines of why. Comments in code
  you were not asked to touch are not yours to sweep.
- Supported targets: `linux/amd64`, `linux/arm64`, `windows/amd64`; everything builds on all
  three.

## Working method

- State assumptions before coding; if several readings exist, present them.
- Minimum code that solves the problem: no unrequested features, no single-use abstractions.
- Touch only what the request needs; remove what your change made unused; leave pre-existing
  dead code alone and say so.
- Read a file's exports and callers before adding to it. "Looks orthogonal" is the most
  dangerous phrase in this codebase.
- A bug gets four attempts, each a distinct diagnostic phase; after four, stop and raise it.
- Fail loud. "Tests pass" is wrong if any were skipped or a subagent's self-report is the
  only proof.

## Licence

AGPLv3 only, with the Scripting API Exception in `LICENSE.exception`: sysop-authored Lua
scripts and themes using only the public `bbs.*` API are not derivative works. Forks, modified
bindings and anything compiled into the engine remain AGPLv3. Apache-2.0, MIT and BSD
dependencies may be linked; audit every new one. Before changing any `bbs.*` binding, read the
scripting API spec's deprecation contract, which is what keeps that exception's promise.

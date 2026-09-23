# CLAUDE.md

Read `CONSTITUTION.md` first. It is the authority; this file is the working rules that follow
from it. Anything local to one machine (paths, private reference material, credentials' whereabouts)
lives in the gitignored `CLAUDE.local.md`, never here: this file is public.

## Project

Helios Advance BBS is a modern, enterprise-grade BBS in the spirit of VBBS and VADV. A
scripting layer carries all BBS logic, so a sysop (the operator of a running board) swaps
scripts to change the whole personality without touching engine source. The terminal
experience feels authentically classic; the internals are uncompromisingly modern; the
scripting layer is the bridge. Secure by default and by design.

One developer, a three-to-four-year project, six repositories under the `HeliosBBS`
organisation developed together (the constitution lists them). Developer time is the scarcest
resource, so the tooling does the breaking-down, the model does the building, and the
developer reviews in feature terms.

## Layout

| Path | Holds |
|---|---|
| `CONSTITUTION.md` | the principles every skill and loop loads first |
| `features/` | feature briefs, one file per feature, developer-owned |
| `docs/spec/` | the derived corpus: `architecture.md` and one file per subsystem |
| `docs/sysop/` | the board operator's guide, published to GitHub Pages |
| `cmd/`, `internal/` | the engine's Go source |
| `.claude/` | this repository's settings and hooks; the skills come from the shared plugin |
| `automation/` | the unattended loop |
| `Makefile` | `make check` runs everything CI runs; `make bootstrap` stands up the dev box |

Shared across the estate and inherited here: the skills plugin (skills, hooks, the shared
constitution) and the `.github` repository (community health files, issue forms, reusable
workflows, the label set). The wiki holds the operational learnings and runbook: build and
test commands, runner quirks, the loop's signs, recovery steps. It is unreviewed and
disposable by design; the specs are reviewed and are not. `HeliosDesign` (private) holds
design conversations and brainstorm transcripts.

## The feature-first pipeline

Skills, each a gate the next cannot pass without:

1. **`feature-brainstorm`** turns "I want X" or a generic description into an approved feature
   brief with a stable ID. Feature language only, one question at a time. Threat modelling is
   part of the shaping. The brief has zero open questions or it is not finished. The
   transcript goes to `HeliosDesign`.
2. **`feature-design`** derives the delta: placement, contracts, data model, state machine,
   fail directions, multi-node invariants, audit entries, the config-tool footprint, the
   negative tests, and the spec updates as delta blocks with feature-ID traceability. It runs
   a clean-room design challenge and a critic before the developer sees anything.
3. **`feature-plan`** does gap analysis against the code first (never assume something is not
   implemented: search), writes a checklist into the issue that a Sonnet 5 session at high
   effort can execute without judgment, then runs the analyze gate: brief, design, plan and
   constitution checked against each other. No code before the checklist is in the issue.
4. **`feature-build`** takes one task per iteration with fresh context in its own worktree
   from a green baseline: red/green TDD, `make check`, commit, tick the box, note learnings,
   stop. Review is two-stage: against the brief and plan first, then code quality. A feature
   is done only after verification through its real surface (a real Telnet or SSH session, a
   real HTTP call), never from unit tests alone.
5. **`compound`** ends every feature and every loop iteration: what was learned goes where the
   next session reads it (the wiki for operational signs, the plugin for an estate-wide rule,
   this file for a rule that holds here). Work that does not make the next unit easier is not
   finished.

Approving an idea does not approve an artifact that does not exist yet. No implementation
until the brief, the design and the plan for the chosen path are approved, in that order.

## Work tracking

GitHub Issues are the record, across the estate. The issue form enforces the work-order shape:
summary, files, exact change, reason, security-sensitive yes or no, and a `## Plan` section.
Labels carry priority (`P0` to `P3`), status (`blocked`, `human-action-required`, `claimed`),
`security-sensitive`, `unattended-loop` and `kind:*`; one label set, synced to every
repository. Milestones, sub-issues and issue dependencies express structure and cross
repositories; the organisation's Projects board is the developer's remote view.

Agents never page the API. `work` refreshes a gitignored `issues.jsonl` mirror in one call;
`work next` applies the mechanical selection (own claimed item, else the first open item by
priority then age, skipping blocked, human-action and deferred); `work claim`, `work tick` and
`work close` do the writes; `work lint` enforces the shape in CI.

The plan checklist is a gate. Boxes are ticked with a short comment (commit, what the test
proved, learnings) as tasks land. A plan change is an edit with a reason. Closing needs every
box ticked or struck with a reason, the PR linked, and the write-up as the final comment.

A security-sensitive issue describes the work without the exploit path. Specifics go in a
private security advisory.

## Routing

Sonnet 5 at high effort is the default, to stretch the usage cap. It is not a ceiling. Tasks
route on shape, not file location, and route up on triggers decided by code, never by
self-report: tests fail twice with different fixes, the gutter detector fires, an unplanned
security-sensitive path appears, or the diff outgrows the plan. Then Opus at high, with the
failed attempt's notes; a second failure is a human-action item.

Review is never downgraded. Opus or Fable reviews every task; the hostile reviewer takes
anything security-sensitive. A Fable pin on a subagent can be silently served by Sonnet, so
Fable-level work runs in-session and every pinned dispatch is verified from the transcript.

## Branches and merging

- **`main`** is the default branch and holds the skeleton and releases only, each release a
  SemVer tag. Cutting a release is a human checkpoint and is when the AGPLv3 section 13
  source-offer obligation attaches: the running service must point at the exact commit it was
  built from, so that commit must exist here. The few files GitHub reads from the default
  branch point at `development` explicitly.
- **`development`** is the integration branch. Everything lands here through a pull request
  that closes its issue, through the merge queue, on green required checks.
- **Work branches** are one per issue, named `issue-<n>-<slug>`, in their own worktree, deleted
  on merge.
- **Identity.** The unattended loop commits and opens pull requests as the organisation's
  GitHub App, never as the developer, so the developer's review of its work is a real gate.

Commit atomically and push as soon as a unit of work is verified; unpushed work is work a
crash forces someone to redo. Stage only the files you changed, named explicitly. Never end a
session with verified work uncommitted or unpushed.

## Mandatory rules

- **Secrets.** Never commit a credential, key or token, in code, tests, config or CI. Push
  protection is on; a committed secret is rotated at the source, not deleted from history.
- **Hooks enforce the mechanical rules**; prose does not. Edits to `features/`,
  `CONSTITUTION.md` and the licence files are denied outside a developer-driven brainstorm;
  edits are formatted; a turn does not end on a red `make check`.
- **`make check` is the only definition of green.** The loop's backpressure, the stop hook and
  CI all call it. A session starts with `make bootstrap` and a smoke check before touching
  anything.
- **Schema migrations** are numbered, transactional, additive only, `IF NOT EXISTS`
  everywhere. Never edit a committed migration; write a new one.
- **Third-party dependencies** are weighed against writing the code natively. Run
  `govulncheck ./...` before adding one; CI fails on a flagged vulnerability.
- **Lang strings** use named replacement tags (`{TAG_NAME}`), never positional arguments.
- **Config is part of the feature.** A sysop-facing setting is done only when the setup and
  runtime configuration tools both expose it, in the same PR as the code and tests.
- **Refactor on discovering an architectural flaw** rather than building on it.
- **Questions:** one at a time. **Pushback:** with reasoning, never an echo.

## Bug classes to check explicitly

Recurring shapes ordinary review misses. Every review prompt names them.

1. Fail-open error handling: a gate that checks the result and ignores the error.
2. A nullable column scanned into a non-pointer field.
3. A string identifier that does not match its source of truth; prefer a constant.
4. Send on a closed channel in fan-out code.
5. A doc comment asserting the opposite of the behaviour.
6. Security-critical logic duplicated across surfaces.
7. A multi-step store operation without a transaction.
8. A state-changing operator action with no audit entry.
9. A regression test that still passes when the fix is reverted.

## Code style

- Languages: Go for the engine, Lua for the scripting layer, Free Pascal (Lazarus) for the
  cross-platform GUI tools. The architecture names the stack once; specs never do.
- Allman braces in every language except Go.
- Names readable without knowing abbreviations: `sessionID`, not `sid`. An abbreviation
  passes only if it is common across C, Pascal and Go alike.
- A comment is the exception. It explains a why the code cannot show, is self-contained, and
  names constructs, never line numbers or filenames.
- Go tests: standard `testing`, table-driven, `t.Parallel()` where independent, real sockets
  and temp files rather than I/O mocks. Every permission check gets a negative-path test.
- `log/slog` only. Never log a secret, password, session token or code at any level.
- Supported targets: `linux/amd64`, `linux/arm64`, `windows/amd64`. Everything builds on all
  three.

## Working method

- State assumptions before coding; if several readings exist, present them.
- Minimum code that solves the problem: no unrequested features, no single-use abstractions.
- Touch only what the request needs. Remove what your change made unused; leave pre-existing
  dead code alone and mention it.
- Read a file's exports and callers before adding to it. "Looks orthogonal" is the most
  dangerous phrase in this codebase.
- A bug gets four attempts, each a distinct diagnostic phase; after four, stop and raise it.
- Fail loud. "Tests pass" is wrong if any were skipped or if a subagent's self-report is the
  only proof.

## Licence

AGPLv3 only, with the Scripting API Exception in `LICENSE.exception`: sysop-authored Lua
scripts and themes using only the public `bbs.*` API are not derivative works. Forks, modified
bindings and anything compiled into the engine remain AGPLv3. Apache-2.0, MIT and BSD
dependencies may be linked; audit every new one. Before changing any `bbs.*` binding, read the
scripting API spec's deprecation contract, which is what keeps that exception's promise.

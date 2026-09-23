# Helios Advance BBS

A modern, enterprise-grade bulletin board system in the spirit of VBBS and VADV.

The terminal experience is meant to feel authentically classic. The internals are
uncompromisingly modern. A scripting layer sits between the two and carries all of the BBS
logic, so a sysop changes the whole personality of a board by swapping scripts rather than by
touching engine source.

Secure by default and by design.

## Status: pre-release, built in the open

No version has been released and no tag exists. `main` holds releases only; work lands on
`development` through pull requests, and the issues and the project board show what is being
worked on now.

The project is designed feature-first: the developer writes a brief for each feature in
`features/`, and the architecture and subsystem specifications in `docs/spec/` are derived
from those briefs, with every section naming the features it serves. `CONSTITUTION.md` holds
the principles the whole system works from.

## The estate

| Project | What it is | Licence |
|---|---|---|
| [HeliosDoorKit](https://github.com/HeliosBBS/HeliosDoorKit) | Wire protocol and multi-language SDK for BBS doors. Not tied to this BBS. | Apache-2.0 |
| [HeliosPortal](https://github.com/HeliosBBS/HeliosPortal) | Progressive web app with an address book for many Helios Advance boards. | AGPLv3-only |
| [HeliosSIP](https://github.com/HeliosBBS/HeliosSIP) | SIP-to-SSH gateway, so a caller with a modem and a VoIP line can reach any SSH or Telnet host. | AGPLv3-only |
| HeliosDoors | Doors built on the Door Kit. | to be decided |
| HeliosLoadTest | Load-test harness for a running board. Private, because it is a load generator. | AGPLv3-only |

Each project's interface to the engine is a protocol, a wire format, or nothing at all.

## Licence

**GNU Affero General Public License, version 3 only** (not "or later") **with one additional
permission**.

- `LICENSE` is the AGPLv3.
- `LICENSE.exception` is the **Helios Advance BBS Scripting API Exception**, an additional
  permission under AGPLv3 section 7: sysop-authored Lua scripts and themes that use the engine
  solely through the public `bbs.*` API are not derivative works of the engine, and may be
  licensed on any terms or kept entirely private.

Forks of the engine, modified `bbs.*` bindings, and anything compiled into the engine binary
remain under the AGPLv3. Section 13 applies to anyone running this as a network service: a
running instance must be able to offer its users the corresponding source for the exact
version they are talking to.

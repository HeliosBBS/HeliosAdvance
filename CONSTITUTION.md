# Constitution

The estate's shared constitution, in the `helios` plugin, is loaded first in every session and
holds the principles: authority from features down, security designed in, multi-node from the
start, the estate and its contracts, the spec rules. This file adds only what is specific to
the engine, and is loaded right after it, unchanged.

## Standing exception

The VirtualNET wire format is a separate specification, supplied ahead of the transport's
implementation. Its transport feature depends on that specification existing and is blocked,
not designed around, until it does.

## How this file is used

Loaded after the shared constitution by every skill, every prompt and every loop iteration. A
change to it is a pull request the developer approves, and nothing else edits it.

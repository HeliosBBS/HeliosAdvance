# Frequently asked questions

**Why write new BBS software in 2026?**
It's been a dream of mine to write my own BBS going back to the '90s, so even if no one else
uses it, I'm fulfilling my dream. Additionally, in a world of modern social media burnout, I
miss long-form discussions. I would love for BBSes to be that new long-form discussion
platform.

**With social media burnout, why include social media-like features?**
We have a few generations that have never been on a BBS or a forum. I hope to create a
familiar experience.

**What is your background in BBSes?**
During the '90s and early 2000s, I ran a BBS using many different software packages.
VBBS/VADV was my favorite for its ease of customization and its broad BBS network support.
It's for that reason that Helios Advance is inspired by it, and I hope to achieve those same
goals.

**What were your BBSes called?**
The River Styx, Cataclysm BBS, and Genocide BBS.

**Which BBS software packages have you used?**
WWIV, Renegade, VBBS, VADV, Oblivion/2, RemoteAccess, and Mystic.

**Who wrote the code?**
It is a mix of myself and Anthropic's Claude.

**Why use AI for coding?**
Go is a new language to me, and I'm learning it as I write it, so I'm going to make mistakes.
Claude catches them. Claude also lets me put more development hours into the project than my
life would otherwise allow, since it can code while I'm at work, asleep, or spending time with
family. I still control the inputs and shapes. I also review everything it writes, and it
AI-reviews everything I write and helps with design decisions and bugs. It's a collaborative
endeavor.

**Is this vibe coded?**
No, not in the sense of typing prompts into a chat and letting the AI run in a feedback loop.
AI is one of many tools in this project, and the project follows a strict discipline. Every
feature starts as a brief in my own words: what it does, for whom, what must never happen, and
its threat model. From the approved brief, the architecture and subsystem specifications are
derived, put through an independent design challenge and a critic, and then reviewed and
approved by me section by section. From the specifications comes a plan of small tasks, each
with the test it must write first; I read every brief and every plan in full. Then the code:
sometimes Claude writes it, sometimes I write the foundation and Claude polishes it. Every
task is reviewed twice, once against the brief and plan and once for code quality, by a
stronger model than the one that wrote it, with a hostile review of anything
security-sensitive, and I review the result. All production code must satisfy the
specification and pass its tests, and a feature counts as done only when it has been driven
through its real surface, not just its unit tests. When a review finds a flaw in the design,
the specification is corrected first; where I missed something in the bigger picture, a
subsystem is rearchitected rather than patched.

**Why write tests before code?**
When you write your tests after the code, you tend to write them so that the code passes. If
you do it in reverse, you tend to do the opposite. I don't have an independent QA engineer
writing tests, so it's a safeguard.

**Why disclose that you're using AI?**
People have a lot of strong feelings about GenAI/LLMs. It's not just about the risk of
creating slop, but also the environmental and cultural impacts, all of which are worthy of
discussion. I want to be honest with people so they can make an informed decision on whether
to use this software based on their own convictions.

**Why Go?**
Its feature set just felt like a natural fit for what a modern BBS needs to do. I also wanted
to learn a new language.

**Why Lua?**
It is easier for new programmers to learn than JavaScript, but I have not ruled out adding
JavaScript as a secondary engine.

**Why Pascal?**
It is easier for new programmers to learn than C++ or C#. Plus, Pascal is my favorite
language.

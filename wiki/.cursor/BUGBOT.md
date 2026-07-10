# Bugbot — wiki/ (prose review)

These are prose pages: ADRs, analyses, patterns, connections, sources, the index and log.
They exist to make a *reader* understand — a colleague six months from now, not a linter.
Review them as prose with that goal, not as code. `wiki/schema.md` is the house-style
authority; this file says what to weight.

## What matters most (big picture, in order)

1. **Factual consistency across the corpus.** A page that contradicts an accepted ADR, or
   restates a fact that lives authoritatively on another page, is the real defect. A fact
   lives in exactly one place (`wiki/schema.md`, single-fact-per-page). Flag: a claim that
   conflicts with an `accepted` decision; the same fact asserted on two pages; a page
   describing a decision as "accepted" that the index or log does not ratify.
2. **The page does what its type promises.** A `decision` states Context → Decision →
   Consequences and carries a real trade-off, not a summary. An `analysis` reaches a
   finding. A `connection` describes a boundary both sides can act on. A page that is the
   wrong type for its content is a structural problem worth raising.
3. **Citations back non-draft claims.** Any authoritative factual claim — a weight, a cut,
   a scale range, a comparability judgment — needs a source. "The registry says X" is not a
   source; the state technical report is. This mirrors the repo rule that a non-`draft`
   record carries `provenance.source_citation`.
4. **Cross-references resolve.** `[[page-slug]]` links point at pages that exist; new pages
   are added to `wiki/index.md` and appear in `wiki/log.md` (reverse-chronological, newest
   on top); no orphans.

## Style: consistency and illustrative depth, not minutiae

The goal of these pages is to *illustrate for the reader*. Judge the writing against that
goal, and against the voice already established across the wiki — one consistent register,
PR to PR, not each author's own.

- **Short, choppy paragraphs are a defect here, not a virtue.** When the goal is to bring a
  reader along, a wall of one- and two-sentence paragraphs reads as an outline, not an
  explanation. Flag a page that is mostly paragraphs of ≤ 3 sentences: it almost always
  means the reasoning connecting the facts was left out. The fix is to *develop* the point,
  not to merge lines mechanically.
- **A claim should carry its "why."** The established voice explains *why* a thing is true
  or was decided, not only that it is. A page that asserts without reasoning is thinner than
  the corpus around it, even when every sentence is correct.
- **One voice.** Register, terminology, and structure should match the surrounding pages
  (compare an existing accepted ADR). Flag drift into a markedly different tone — bullet
  fragments where the corpus writes prose, or marketing gloss where it writes plainly.
- **Terminology is exact and consistent.** The same concept keeps the same name across
  pages (`administration`, `content_area`, `enrolled_grades_tested`, `axis rule`). A new
  synonym for an existing term is a real cost — flag it.

## Not worth a comment

Single-word choices, Oxford commas, em-dash vs colon, British/American spelling, sentence
length in isolation, and reordering that changes nothing. Prefer one substantive note about
structure or a missing "why" over ten line-level nits. If the only findings are typographic,
say the page reads well and stop.

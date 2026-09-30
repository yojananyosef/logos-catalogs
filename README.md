# logos-catalogs

Content for the Logos engine: the module format contract, the licensing gate that decides
what may ship, and the tooling that builds and validates modules.

This is a **separate repository from the engine** on purpose. Content changes on licence
timelines, code changes on release cadence, and the two must be able to move independently.

## Why the gate is a build step

The chosen Spanish text, the Biblia Platense, is **not in public domain until
1 January 2027** (Straubinger d. 1956; life+70 under Ley 17.336 art. 10 in Chile, Spain
and the EU; 2043 in the United States). That single fact is why the catalog is decoupled
from the application — and why the licensing check lives in the build rather than in a
document. A checklist is not a control.

```
dart pub get
dart run tool/validate_catalog.dart catalog/catalog.json --jurisdiction=CL
```

Today that exits non-zero, naming the date. On 2027-01-01 it passes:

```
# today
BLOCKED — 1 violation(s):
  [release-date] PLATENSE: not distributable until 2027-01-01 (copyright still in force)

# with --now=2027-01-01
OK — catalog may be distributed.
```

`--now` exists so a build can be checked against a future date, and so the release can be
verified before its licence actually expires.

## Rules the gate enforces

| Rule | Why it exists |
|---|---|
| unresolved licence | The status cannot be established, so the resource cannot ship |
| missing attribution | CC BY obliges the redistributor to carry it |
| non-commercial in a commercial build | CC BY-NC forbids the use |
| share-alike in a closed target | The obligation is contagious across derived data |
| release date not reached | The work is still under copyright |
| jurisdiction not cleared | A licence may only be clear in some territories |
| no recorded basis for a public-domain claim | Distinguishes a documented claim from an assumption |
| missing sha256 | Distribution integrity cannot be verified |

Each rule traces to a specific finding during the licensing audit, not to a generic policy.

## Layout

```
format/          the AMF contract + CatalogGate (published as a Dart package)
lib/             catalog reading, validation, USFM extraction
tool/            CLI entry points
catalog/         catalog.json — the index, reviewable as text
```

## The integrity check

`ModuleIntegrityGate` verifies that every chapter is contiguous `1..N` with no duplicates
and no gaps. It exists because the upstream catalog had no such check.

Reading the artefacts found **two** distinct defects, not one:

**Lost first verse — KJV and ASV, 260 chapters each.** `John 1:1` returns zero rows. The
cause was an off-by-one in the SWORD RawText reader, which indexed a chapter's lines as
`lines[verse - 1]` when verse N lives at `lines[N]`. The upstream end-to-end test read
**Genesis 1:1** — Old Testament, unaffected — and passed.

**Merged verses, `verseEnd` never populated — WEB, 4 chapters.** `Luke 17:36` and three
others return zero rows, but the text is *present*: USFM writes several verses as one run
under a range marker, and the ETL stored that run under the first verse number alone. Every
chapter still starts at verse 1, so checking only for that reports WEB as sound — an earlier
note here called it "clean (0 missing)", which was wrong.

`lib/usfm_extractor.dart` fixes both: it keeps the first verse of every chapter and now
records `verseEnd` from the range marker instead of discarding the tail. Both defects are
pinned by `test/usfm_extractor_test.dart`, and the engine's reader is taught to honour
`verseEnd` so a rebuilt module actually resolves.

## Adding a resource

1. Add an entry to `catalog/catalog.json` with a licence, an attribution string when
   required, a source URL, a recorded basis, and a release date.
2. Run the validator. It will refuse to ship an entry that cannot be justified.
3. Record anything excluded, with the reason, in the `excluded` array. The exclusions in
   the current catalog are the interesting part: RVR1960 (copyrighted and trademarked),
   Robinson's codes (share-alike), Open Scriptures' Strong's file (GPL on data), Robertson's
   Word Pictures (renewed), and the absence of any public-domain Spanish commentary.

## Tests

```
cd format && dart test     # licence gate
dart test                  # USFM extraction, including the verse-1 regression
```

# mkfs.pdxfs — architecture

**Wave:** R53 tool (design/tooling/volume-tooling-ux.md §2.1 + §3 + §9.1)
**Repo:** github.com/paideia-os/mkfs.pdxfs
**Upstream design:** `design/tooling/volume-tooling-ux.md` §3 (CLI spec)
+ §9.1 (milestone breakdown) and
`design/filesystem/volume-fs-substrate.md` §2.1 (PDXB superblock
layout, needed from M2 onward) in
[paideia-os](https://github.com/paideia-os/paideia-os).

This document describes the internal shape of `mkfs.pdxfs`. It does not
repeat the wave-level rationale from the paideia-os plan doc; read that
first for why volume tooling needs three CLIs plus one shared library
(`libpdx-volume`) and for the R52/R53 boundary (R52 = in-kernel
substrate, R53 = user-facing path to format/mount/unmount).

## 1. What this tool is

`mkfs.pdxfs` is a standalone ring-3 ELF — a `_start`-based executable,
**not** a shared library like `libpdx-volume` or `libpdx-audit`. It
performs its own syscalls directly (self-contained inlined-syscall
pattern), matching the `src/user/true.pdx` / `cat.pdx` / `mkdir.pdx`
convention in the paideia-os monorepo, rather than delegating every
kernel touch to a linked library. The one library it will link,
`libpdx-volume`, supplies the PDXB wire-format codec and the signing
helper — not process lifecycle, argv, or output.

`mkfs.pdxfs` writes a fresh PDXB v1 superblock + empty allocator bitmap
+ empty journal ring + a single root-inode entry onto a target, per
`design/tooling/volume-tooling-ux.md` §3. The target is either a
filesystem path (dev workflow) or a `cap:blkdev:` cap URI (production
workflow).

## 2. Module split

Four source files, one per major concern (matches `libpdx-volume`'s and
`libpdx-audit`'s own "one module per public-entry-point family"
granularity):

- **`src/main.pdx`** (`Main`) — `_start`. Wires argv parsing → target
  classification → the M1 dry-run emit path, or falls through to a
  `not yet implemented` diagnostic. Owns the `ParsedArgv` scratch
  struct's storage (`mkfs_argv_out`, `.bss`) and the two fd-2
  diagnostic message literals.
- **`src/argv.pdx`** (`Argv`) — the long-flag CLI parser (`argv_parse`)
  plus three pure-leaf helpers it calls (`argv_streq`,
  `argv_prefix_match`, `argv_parse_u64_dec`). Owns the `ParsedArgv`
  out-struct layout constants (`PA_OFF_*`, `PA_FLAG_*`) and every flag
  literal.
- **`src/target.pdx`** (`Target`) — `target_classify`, an M1
  byte-prefix classifier distinguishing a file path from a
  `cap:blkdev:` URI from an invalid prefix. Deliberately narrow: it
  never opens a cap or calls a syscall (see §5 below for the scope
  boundary this issue draws).
- **`src/format_record.pdx`** (`FormatRecord`) — `format_record_emit_
  dry_run`, the M1 `PdxFsFormatRecord@0.1` line-based text emitter,
  plus its own private `format_record_strlen` helper.

Kept as four separate files rather than one `main.pdx` monolith because
each has a distinct, independently-testable contract (argv parsing,
target classification, and record emission are three different
problems that M2/M3 will each grow independently — target.pdx grows a
real cap-resolution body at M2-001, format_record.pdx grows the full
14-field semantic-pipe emit at M3-003, argv.pdx potentially gets
replaced wholesale by a `libpdx-argv`-backed rewrite — none of which
should require touching the other three files).

## 3. `libpdx-argv` availability — confirmed absent, minimal parser shipped instead

Issue #2's own instruction was to check whether `libpdx-argv` exists
(either in the paideia-os monorepo or under `paideia-satellites/`) and
wire against it if so. A `grep -rl libpdx-argv` across both trees at
this landing's time finds **zero implementation files** — only
design-doc *mentions* of a planned library
(`design/tooling/r49-r50-plan.md` §3.2 in paideia-os, which lists
`libpdx-argv` as one of five R49-wave shared libraries but does not
itself contain or reference any source). No repo named
`libpdx-argv` exists under `paideia-satellites/` (as of this landing,
the only repos there are `libpdx-audit`, `libpdx-volume`, and this one).

Per issue #2's own fallback instruction, `src/argv.pdx` therefore
implements a **minimal long-flag parser inline**: `Argv::argv_parse`
takes `(argc, argv, out_ptr)` and returns a status code, writing a
40-byte `ParsedArgv` struct (five u64-aligned slots: `flags`,
`label_ptr`, `journal_size`, `sig_key_ptr`, `target_ptr`) to `out_ptr`.
This is deliberately the same shape a future `libpdx-argv`-backed
rewrite would present (argc/argv in, a parsed-fields out-pointer, a u64
status code out) — swapping `argv_parse`'s body for a call into a real
`libpdx-argv` library, once one is bootstrapped, would not require
`main.pdx` to change at its one call site.

The parser supports exactly the six flags/positional argv.pdx's own
module header documents (`--force`, `--label=`, `--journal-size=`,
`--dry-run`, `--verbose`, `--sig-key=`, `<target>`), via two shared
compare subroutines (`argv_streq` for exact boolean-flag matches,
`argv_prefix_match` for value-flag prefix matches) and one decimal
parser (`argv_parse_u64_dec`, adapted from `src/user/dispatch.pdx`'s
`dec_parse` in the paideia-os monorepo). It does not implement short
flags, flag clustering, or the 9-flag "standard vocabulary" (`--help`,
`--version`, `--json`, `--schema`, `--quiet`, `--color=`,
`--no-cap:<name>`) `design/tooling/r49-r50-plan.md` §3.3 describes for
the eventual `libpdx-argv` — those are out of scope for this issue's
"minimal" instruction and would be inherited for free from a real
`libpdx-argv` link once one exists.

## 4. `PdxFsFormatRecord@0.1` — what M1 actually prints

`design/tooling/volume-tooling-ux.md` §3.5 defines the full 14-field
schema (`target_kind`, `target_uri`, `block_size`, `total_blocks`,
`journal_blocks`, `itable_blocks`, `data_blocks`, `uuid`, `label`,
`sig_key_hash`, `signed`, `invoker_user`, `ts_ns`, `dry_run`,
`refused_gates`). Issue #3's own acceptance text asks for a much
smaller slice:

```
PdxFsFormatRecord@0.1 { target: <path>, label: <label>,
                        journal_size: <N>, dry_run: true }
```

`src/format_record.pdx`'s `format_record_emit_dry_run` prints exactly
this four-field line, via a fixed sequence of `sys_write(1, ...)` calls
(literal chunk, then dynamic value, repeated) — no schema-registry
binding, no `KIND_IPC_ENDPOINT` framing. Every field printed is the
caller's real argument (the actual target string, the actual label
string or nothing if unset, a real decimal conversion of the actual
`journal_size` u64) — this is a genuine implementation of the four-field
slice, not a fixed placeholder value standing in for a future real
body. What is deferred to `mkfs.pdxfs.M3-003` is the remaining ten
schema fields (most of which need substrate this repo does not have at
M1: a real `stat` of the target for `total_blocks`/`itable_blocks`/
`data_blocks`, a `KIND_USER` lookup for `invoker_user`, a clock read for
`ts_ns`) and the semantic-pipe binary framing itself, per
`design/tooling/r49-r50-plan.md` §3.2's description of a semantic pipe
as "a subclass of `KIND_IPC_ENDPOINT` (base kind 5) carrying a schema
handle alongside the byte stream."

## 5. `target.pdx`'s M1 scope — classify, not resolve

`design/tooling/volume-tooling-ux.md` §3.2 describes a "target-taxonomy
resolver" that inspects `<target>`, and on the file-backed path opens
(and if absent, creates + truncates) a real `KIND_PDXFS_FILE` cap; on
the device-cap path, resolves a `KIND_BLOCK_DEVICE` cap from the
invoker's environment and — if needed — invokes `libpdx-elevate`. None
of that exists at M1: this issue's own scaffold instruction scopes
`target.pdx` as a "STUB for M1, real body at M2-001."

`Target::target_classify` implements the narrowest possible stub that
still lets `mkfs.pdxfs.M1-003`'s acceptance criterion work: it inspects
only the first byte (for `/`, `~`, `.`) and, failing those, the first
11 bytes (for the literal `cap:blkdev:`) of the raw argv string, and
returns one of `TARGET_FILE` / `TARGET_DEVICE_CAP` / `TARGET_INVALID`.
It never calls `sys_open`, never mints a cap, never touches the
filesystem. `main.pdx`'s only use of this classification is to decide
which of two print branches to take on `--dry-run` — it is not (yet)
used to authorize anything. The real resolver — opening/creating/
truncating a `KIND_PDXFS_FILE`, or resolving + narrowing a device cap
— is `mkfs.pdxfs.M2-001`, unchanged from the design doc's own scoping.

## 6. `KIND_BLOCK_DEVICE` naming gap (flagged for main)

`caps.decl` documents this in full; summarized here for visibility.
`design/tooling/volume-tooling-ux.md` names the device-cap kind
`KIND_BLOCK_DEVICE` at a `0x198..0x19F` ordinal band "per §12
coordination point 1 (osarch, R51)" — i.e. a kind that has not yet
landed kernel-side under that name. The kernel tree as of this landing
already has a **different**, already-landed kind at
`src/kernel/core/cap/kind_blkdev.pdx`: `KIND_BLKDEV = 0x42`. This
repo's `caps.decl` declares the design doc's own placeholder name
(`KIND_BLOCK_DEVICE`) rather than silently substituting the existing
`KIND_BLKDEV`, since the two kinds' tail shapes and rights bands have
not been audited against each other and may not be interchangeable.
**Confirm with osarch before `mkfs.pdxfs.M3-001`** (device-cap target
path) implements a real mint/narrow call against either kind — this
mirrors the exact shape of the `KIND_PDXFS_MOUNT_TABLE` discrepancy
`libpdx-volume`'s own `design/architecture.md` §4 flags for main.

## 7. Register-preservation discipline (a correctness note, not upstream-sourced)

Every public entry point in this repo that repurposes a SysV
callee-save register (`rbx`, `r12`-`r15`) for cross-syscall or
cross-nested-call state now explicitly `push`es it on entry and `pop`s
it (in reverse order) immediately before its `ret` —
`Argv::argv_parse` (5 registers) and
`FormatRecord::format_record_emit_dry_run` (3 registers) both do this.
This matters because a first draft of both functions repurposed those
registers without saving them, which happened to still produce correct
output at this landing's one call graph (`main.pdx`'s `_start` does not
need any of its own `rbx`/`r12`-`r15` values preserved across either
call site) but would silently corrupt a *different* future caller's
state — the same ABI hazard `libpdx-audit`'s `audit_send_record`
avoids via its own `push r12; push r13` pair. Every pure-leaf helper in
this repo (`argv_streq`, `argv_prefix_match`, `argv_parse_u64_dec`,
`target_classify`, `format_record_strlen`) touches only caller-save
registers and needs no push/pop.

## 8. What M1 explicitly does not do

Called out here so a reader of M1 code does not mistake absence for
bug:

- No real target resolution — `target_classify` only inspects a byte
  prefix (§5).
- No superblock encode/write, no allocator-bitmap zeroing, no journal
  init, no root-inode write — all `mkfs.pdxfs.M2`.
- No non-blank refusal gate (§3.3 of the upstream design) — `mkfs.pdxfs.M2-004`.
- No device-cap resolution, no signing, no `libpdx-elevate` call — all
  `mkfs.pdxfs.M3`.
- No `libpdx-audit` journaling — `mkfs.pdxfs.M3-004`. M1's `--dry-run`
  path writes directly to stdout with no audit-first gate; this is
  acceptable at M1 since the D3 audit-first discipline's whole point is
  to gate *user-visible output of a real operation's result*, and M1
  performs no real operation.
- No semantic-pipe binary framing — only the four-field text line (§4)
  — `mkfs.pdxfs.M3-003`.
- No `libpdx-volume` link yet. `libpdx-volume.M1` has landed
  (`pdxb_encode_superblock` / `pdxb_parse_superblock` /
  `pdxb_sign_superblock` all exist as stubs or are not yet present —
  see that repo's own `STATUS.md`), but nothing in this repo calls into
  it at M1; the real superblock write at `mkfs.pdxfs.M2-002` is this
  tool's first `libpdx-volume` link.

## 9. What M2/M3 need before they can open

- `mkfs.pdxfs.M2-002` (superblock write) needs `libpdx-volume.M2`'s
  real `pdxb_encode_superblock` body — the M1 stub returns `PDXB_OK`
  without writing anything, which is not sufficient for a real mkfs.
- `mkfs.pdxfs.M3-001` (device-cap target) needs the `KIND_BLOCK_DEVICE`
  naming gap (§6) resolved with osarch.
- `mkfs.pdxfs.M3-002` (signing) needs the paideia-as `mldsa65_sign`
  intrinsic reachable through `libpdx-volume.M3-001`.
- `mkfs.pdxfs.M3-005` (elevate) needs a `libpdx-elevate` implementation
  to exist — as of this landing, `libpdx-elevate` has the same
  "design-doc-mentioned, not yet bootstrapped" status `libpdx-argv` had
  per §3 above; confirm before M3-005 opens whether it should also ship
  a minimal inline fallback.

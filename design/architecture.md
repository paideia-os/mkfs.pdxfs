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
kernel touch to a linked library. As of M3 it links four satellite
libraries by bare cross-repo `call` (§9.6's mechanism): `libpdx-volume`
(PDXB wire-format codec + ML-DSA-65 superblock signing, both real) and
`libpdx-audit` (real journal-record open/commit calls, though the
daemon dispatch behind them is stubbed). Two more are DELIBERATELY NOT
linked despite being available: `libpdx-semantic-pipe` (real, released,
but its schema-name resolution is inert — §11.3) and `libpdx-elevate`
(real, mature, but this repo has no broker-endpoint cap to call its
real API with — §11.5). See §11 for the full M3 write-up.

`mkfs.pdxfs` writes a fresh PDXB v1 superblock + empty allocator bitmap
+ empty journal ring + a single root-inode entry onto a target, per
`design/tooling/volume-tooling-ux.md` §3. The target is either a
filesystem path (dev workflow) or a `cap:blkdev:` cap URI (production
workflow).

## 2. Module split

Ten source files as of M3, one per major concern (matches
`libpdx-volume`'s and `libpdx-audit`'s own "one module per
public-entry-point family" granularity). The six from M1/M2:

- **`src/main.pdx`** (`Main`) — `_start`. Wires argv parsing → target
  classification → (on `--dry-run`) the M1 preview emit path, OR (on a
  real invocation) the M2 write pipeline, or falls through to a
  `not yet implemented` diagnostic for a device-cap/invalid target.
  Owns the `ParsedArgv` scratch struct's storage (`mkfs_argv_out`,
  `.bss`) and the two fd-2 diagnostic message literals.
- **`src/argv.pdx`** (`Argv`) — the long-flag CLI parser (`argv_parse`)
  plus three pure-leaf helpers it calls (`argv_streq`,
  `argv_prefix_match`, `argv_parse_u64_dec`). Owns the `ParsedArgv`
  out-struct layout constants (`PA_OFF_*`, `PA_FLAG_*`) and every flag
  literal.
- **`src/target.pdx`** (`Target`) — `target_classify`, a byte-prefix
  classifier distinguishing a file path from a `cap:blkdev:` URI from
  an invalid prefix. Its OWN logic is unchanged since M1 (it was
  already real, not a stub); what changed at M2 is that `main.pdx` now
  uses a `TARGET_FILE` result to authorize `format.pdx`'s real write
  pipeline, not just to pick a print branch (see §5).
- **`src/format.pdx`** (`Format`, new at M2) — `mkfs_format_run`, the
  real file-target write pipeline (open, superblock encode+write,
  inode-table/bitmap/journal zeroing, root-inode write, close), plus
  its private helpers `mkfs_format_write_zeros`,
  `mkfs_format_build_superblock`, `mkfs_format_encode_root_inode`. See
  §9.
- **`src/refusal.pdx`** (`Refusal`, new at M2) — `mkfs_refuse_check`,
  the non-blank-target refusal gate `format.pdx`'s pipeline runs first.
  See §9.
- **`src/format_record.pdx`** (`FormatRecord`) — two emitters now:
  `format_record_emit_dry_run` (M1, UNCHANGED, the four-field preview
  line) and `format_record_emit_result` (M2, new — the `result_code`-
  shaped record every real-write outcome emits), plus the shared
  `format_record_strlen` helper and a second private helper,
  `format_record_write_u64_dec`, `format_record_emit_result`'s own
  decimal-errno printer.

Kept as separate files rather than a `main.pdx` monolith because each
has a distinct, independently-testable contract. `argv.pdx` potentially
gets replaced wholesale by a `libpdx-argv`-backed rewrite — which
should not require touching the other files.

Four new files at M3 (see §11 for the full write-up of each):

- **`src/pipe_wire.pdx`** (`PipeWire`, #10) — `mkfs_sp_emit_dry_run` /
  `mkfs_sp_emit_result`, thin wrappers around `FormatRecord`'s two
  emitters that print a documented deferral header first (see §11.3
  for why `libpdx-semantic-pipe` is not linked). `main.pdx` and
  `format.pdx` now call ONLY these wrappers, never `FormatRecord`
  directly.
- **`src/audit_wire.pdx`** (`AuditWire`, #11) — `mkfs_audit_begin` /
  `mkfs_audit_commit`, wrapping `libpdx-audit`'s real
  `AuditClient::audit_begin`/`audit_commit` in a forgiving, non-fatal
  posture. `main.pdx`'s `_start` calls these around every dispatch
  branch.
- **`src/elevate_wire.pdx`** (`ElevateWire`, #12) — `mkfs_elev_require_
  device_write`, a documented fail-closed stub (always DENY) for the
  device-target elevation gate — see §11.5 for why a real call cannot
  be honestly constructed yet.
- `target.pdx` gains `mkfs_dev_parse_slot` (#8, a real hex-slot parser)
  and `format.pdx` gains `mkfs_format_run_device` (#8, a documented
  stub) and superblock signing inside `mkfs_format_run` (#9) — these
  are extensions of existing files, not new ones, since each was
  already the natural owner of that concern.

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

## 5. `target.pdx` scope — classify (M1), now used to authorize (M2)

`design/tooling/volume-tooling-ux.md` §3.2 describes a "target-taxonomy
resolver" that inspects `<target>`, and on the file-backed path opens
(and if absent, creates + truncates) a real `KIND_PDXFS_FILE` cap; on
the device-cap path, resolves a `KIND_BLOCK_DEVICE` cap from the
invoker's environment and — if needed — invokes `libpdx-elevate`. None
of that exists at M1: this issue's own scaffold instruction scopes
`target.pdx` as a "STUB for M1, real body at M2-001."

`Target::target_classify` inspects only the first byte (for `/`, `~`,
`.`) and, failing those, the first 11 bytes (for the literal
`cap:blkdev:`) of the raw argv string, and returns one of
`TARGET_FILE` / `TARGET_DEVICE_CAP` / `TARGET_INVALID`. This was
already a REAL, complete implementation of the classification contract
at M1 — not a placeholder returning a fixed value — and its logic is
UNCHANGED at M2. It still never calls `sys_open`, never mints a cap.

What changed at M2 (`mkfs.pdxfs.M2-001`, issue #4): `main.pdx` now uses
a `TARGET_FILE` result to AUTHORIZE `format.pdx`'s real write pipeline
(`mkfs_format_run`) whenever `--dry-run` is not set — no longer "only
used to pick a print branch." A `TARGET_DEVICE_CAP` or `TARGET_INVALID`
result still falls through to "not yet implemented" (exit 1)
unconditionally (regardless of `--dry-run`) — the real device-cap
resolver (opening/narrowing a `KIND_BLOCK_DEVICE` cap, invoking
`libpdx-elevate`, mandatory signing) is still `mkfs.pdxfs.M3-001`,
unchanged from the M1 scoping.

Issue #4's own task-brief text restates the classifier more narrowly
than the design doc ("If path starts with `/` → file target ... Any
other prefix → TARGET_INVALID", omitting `~` and `.`). This repo reads
that restatement as shorthand for the same three-way split
`target_classify` already implements, not as a deliberate narrowing of
`design/tooling/volume-tooling-ux.md` §3.2's own broader "begins with
`/`, `~`, or `.`" acceptance text — the design doc is this repo's
upstream source of truth, and `target_classify`'s existing M1 body
already satisfies it exactly. **Flagged for main**: if the narrower
`/`-only reading was intentional, `target_classify`'s two extra branches
(`~`, `.`) should be removed in a follow-up; this landing keeps them.

## 6. `KIND_BLOCK_DEVICE` naming gap — RESOLVED at M3

`caps.decl` documents this in full; summarized here for visibility.
`design/tooling/volume-tooling-ux.md` names the device-cap kind
`KIND_BLOCK_DEVICE` at a `0x198..0x19F` ordinal band "per §12
coordination point 1 (osarch, R51)". At M1/M2 this repo flagged that as
possibly a *different* kind from the already-landed
`src/kernel/core/cap/kind_blkdev.pdx`'s `KIND_BLKDEV = 0x42`, needing
osarch confirmation before minting/narrowing against either.

**Resolved at M3** (§11.1 has the full write-up): `design/hardware/
nvme-ahci-tail-milestones.md` §3.1 (paideia-os) confirms `KIND_BLOCK_
DEVICE` is purely a doc-readability alias for `KIND_BLKDEV = 0x42` —
there is no separate kind at the `0x198..0x19F` band; `design/tooling/
volume-tooling-ux.md`'s own `0x198..0x19F` wording is superseded and
stale. What remains unresolved is NOT the name but the absence of any
cap-introspection or cap-narrowing primitive to act on a `KIND_BLKDEV`
cap from ring-3 — see §11.1.

## 7. Register-preservation discipline (a correctness note, not upstream-sourced)

Every public entry point in this repo that repurposes a SysV
callee-save register (`rbx`, `r12`-`r15`) for cross-syscall or
cross-nested-call state explicitly `push`es it on entry and `pop`s it
(in reverse order) immediately before its `ret` — `Argv::argv_parse`
(5 registers), `FormatRecord::format_record_emit_dry_run` (3
registers), and, new at M2, `FormatRecord::format_record_emit_result`
(3 registers), `FormatRecord::format_record_write_u64_dec` (2
registers), `Format::mkfs_format_run` (5 registers),
`Format::mkfs_format_write_zeros` (2 registers), and
`Refusal::mkfs_refuse_check` (1 register) all do this. This matters
because a first draft of the M1 functions repurposed those registers
without saving them, which happened to still produce correct output at
that landing's one call graph but would silently corrupt a *different*
future caller's state — the same ABI hazard `libpdx-audit`'s
`audit_send_record` avoids via its own `push r12; push r13` pair. Every
pure-leaf helper in this repo (`argv_streq`, `argv_prefix_match`,
`argv_parse_u64_dec`, `target_classify`, `format_record_strlen`,
`Format::mkfs_format_build_superblock`,
`Format::mkfs_format_encode_root_inode`) touches only caller-save
registers and needs no push/pop.

One M2-specific wrinkle this section did not need at M1: the kernel's
#743 info-leak hardening zeroes every CALLER-save register
(`rdi`/`rsi`/`rdx`/`r8`/`r9`/`r10`) — not just the usual `rcx`/`r11`
SYSCALL clobbers — before every `sysret` (`format_record_emit_dry_run`'s
own justification text already notes this). `mkfs_refuse_check` holds
its open fd in `r12` rather than a caller-save register like `r8` for
exactly this reason: an fd stashed in `r8` across the `sys_read`
between `sys_open` and `sys_close` would be zeroed the moment
`sys_read`'s `sysret` fires.

## 8. What M1 left open (M2 closed four of these; M3 still owns the rest)

Called out here so a reader does not mistake an absence for a bug, and
so it is clear which M1 gaps M2 actually closed:

- ~~No real target resolution~~ — CLOSED at M2 for the file-backed
  path (`main.pdx` now acts on `TARGET_FILE`, §5); the device-cap path
  is still unresolved, `mkfs.pdxfs.M3-001`.
- ~~No superblock encode/write, no allocator-bitmap zeroing, no journal
  init, no root-inode write~~ — CLOSED at M2 for a file-backed target,
  §9. Still open for a device-cap target (needs M3-001 first).
- ~~No non-blank refusal gate~~ — CLOSED at M2 (`src/refusal.pdx`), with
  two documented simplifications vs. the upstream design doc's full
  text — see §9.
- No device-cap resolution, no signing, no `libpdx-elevate` call — all
  still `mkfs.pdxfs.M3`.
- No `libpdx-audit` journaling — still `mkfs.pdxfs.M3-004`. This is now
  a slightly bigger gap than at M1: M2's real write pipeline performs
  actual destructive I/O (and `--force` can override the refusal gate)
  with no audit trail at all yet, whereas M1's `--dry-run`-only path
  performed no real operation. The design doc's D3 audit-first
  discipline is explicit that `--force` bypassing a refusal must still
  leave an audit trace (`REFUSED_OVERRIDDEN`, §3.3) — M2 does not
  produce one; `mkfs.pdxfs.M3-004` must backfill it.
- No semantic-pipe binary framing — both `format_record.pdx` emitters
  are still line-based text (§4, §9) — `mkfs.pdxfs.M3-003`.

## 9. M2 landing — write pipeline, layout, and the gaps it leaves open

### 9.1 On-disk layout this M2 landing chooses

`design/filesystem/volume-fs-substrate.md` §2.1's superblock fields
(`itable_lba`, `itable_bcount`, `alloc_lba`, `alloc_bcount`,
`journal_lba`, `journal_bcount`, `data_lba`, `data_bcount`) are all in
**4096-byte BLOCK units** — `itable_lba` names a starting BLOCK number,
not a byte offset. Issue #5's own task-brief text is byte-offset-shaped
instead ("`inode_table_offset = 4096`", "`bitmap_bytes = 1024`",
"`journal_offset = bitmap_offset + bitmap_bytes`" — the last of which,
taken literally, is not even block-aligned: `36864 + 1024 = 37888`,
which is `9.25 * 4096`). `src/format.pdx` reconciles this by treating
the task brief as describing INTENT (small, fixed defaults) rather than
literal wire values, and re-derives a block-aligned layout with the
same sizes:

| Region        | LBA (block) | Blocks | Bytes that matter                  |
|---------------|------------:|-------:|-------------------------------------|
| Superblock    | 0           | 1      | 4096 (the whole block)              |
| Inode table   | 1           | 8      | 256 × 128 B = 32768 B (exact fit)   |
| Alloc bitmap  | 9           | 1      | 1024 B (of the 4096-B block; rest padding) |
| Journal ring  | 10          | N      | N × 4096 B, N = `--journal-size` (blocks) |

`total_blocks` is set to `journal_lba + journal_bcount` (`10 + N`) —
this M2 landing allocates **no data region** (`data_lba`/`data_bcount`
stay 0). There is no `--size=` flag in `src/argv.pdx`'s M1 surface to
size a real data region against, and inventing one was out of scope for
issues #4-#7. **Flagged for main**: a `--size=` flag (or an equivalent)
and real `data_lba`/`data_bcount` computation are needed before a
`mount.pdxfs` counterpart could do anything useful with a volume this
tool formats — this is a real functional gap, not just a documentation
one.

### 9.2 `--journal-size` units: blocks, not bytes

Issue #5's task brief says `journal_bytes = argv-provided journal_size
(default 65536)`. But `src/argv.pdx` (landed at M1, unit
already-frozen) documents `ParsedArgv.journal_size` as "u64 block
count... defaults to 1024 (4 MiB at the frozen 4096-byte block size)" —
matching `design/tooling/volume-tooling-ux.md` §3.1's own
`--journal-size=<n_blocks>` wording exactly. `src/format.pdx` keeps
the M1 unit (blocks, default 1024) rather than reinterpreting the
already-shipped argv default as bytes; it converts to a byte count only
at the point it needs one (the zero-fill length), via `shl reg, 12`
(`× 4096`). **Flagged for main**: if the task brief's `65536` default
was meant as a literal spec change, that is a `src/argv.pdx` change
(`ARGV_DEFAULT_JOURNAL_SIZE`), which this landing did not make since
issues #4-#7 do not touch `argv.pdx` and the two defaults are not
obviously reconcilable (1024 blocks = 4 MiB either way `65536` is read).

### 9.3 No `lseek` — sequential writes only

`design/user/syscall-table.md` (paideia-os, refreshed through sysno 95)
has no `lseek` entry at any number. Issue #6's task brief describes
writing the zeroed inode table, then seeking back to inode #1's offset
to patch in the real root inode — impossible on this kernel.
`mkfs_format_run` instead writes the inode-table region as three
SEQUENTIAL `sys_write` calls in final on-disk order (128 zero bytes for
inode 0 → 128 bytes for the real inode 1 → 32512 zero bytes for inodes
2..255), relying only on the fd cursor auto-advancing after each write
— the same mechanism the overall pipeline already uses for the
superblock → inode table → bitmap → journal sequence. Byte-identical
result to a seek-and-patch approach; **flagged for main** only as a
"here is why the code does not look like the task brief" note, not as
an open gap.

### 9.4 Root inode #1: real wire layout, not the task brief's vocabulary

Issue #6's task brief describes the root inode with fields
("mode=DIR, size=0, link_count=2, timestamp=0, block_ptrs=all-zero")
that do not exist under those names anywhere in this codebase.
`design/filesystem/volume-fs-substrate.md` §2.3 is the authoritative
128-byte on-disk inode layout, and `mkfs_format_encode_root_inode`
encodes that REAL layout (so a future `mount.pdxfs`/`fsck.pdxfs` reads
back something valid), mapping the brief's intent onto it:

| Task brief field | Real §2.3 field(s)                              | Value written |
|-------------------|--------------------------------------------------|---------------|
| mode=DIR          | `header` bits `[55:48]` (`file_type`)             | `PDX_INODE_FT_DIR = 1` (see below) |
| —                  | `header` bits `[63:56]` (`in_use`)                | `1`           |
| —                  | `header` bits `[15:0]` (`mode_bits`)              | `0755` (`0x1ED`) |
| size=0             | `byte_len`                                        | `0`           |
| link_count=2       | `refcount` ("on-disk hardlink count", §2.3's own row) | `2`       |
| timestamp=0        | `created_ns`, `mtime_ns`                          | `0`, `0`      |
| block_ptrs=all-zero| `root_block`                                      | `0`           |
| (unmentioned)      | `cow_gen`, `content_hash`, `sig_prefix`, `sig_hash` | all `0` (unsigned, no CoW writes yet) |

`PDX_INODE_FT_DIR = 1` is a **local placeholder constant** (only
referenced as a bare immediate inside `mkfs_format_encode_root_inode`'s
header-packing math, not declared as a named `pub let` anywhere) — no
canonical `file_type` value registry exists anywhere in the tree yet.
**Flagged for main / libpdx-volume**: this repo's own `inode_encoders`
gap (below) should also land a canonical `file_type` enum so a future
`fsck.pdxfs` and this repo agree on what `1` means.

There is no `libpdx-volume.inode_encoders` module (issue #6's own task
brief flags this absence too, and a repo-tree grep at this landing
confirms it: `libpdx-volume/src/` has no file with "inode" in its
name). `mkfs_format_encode_root_inode` therefore encodes the 128 bytes
inline, following the same style (an explicit whole-buffer zero-fill
pass via a scale-8 SIB store loop, then targeted field overlays) this
repo's own `mkfs_format_build_superblock` and libpdx-volume's own
`pdxb_encode_superblock` already use. **Flagged for main / libpdx-volume**:
a real `pdxb_encode_inode` / `pdxb_parse_inode` pair belongs in
`libpdx-volume`, matching its superblock codec's own shape, so this
inline encoding does not need to be duplicated by a future
`fsck.pdxfs` or by `mount.pdxfs`'s own inode-write paths.

### 9.5 Refusal gate simplifications vs. the full §3.3 text

`design/tooling/volume-tooling-ux.md` §3.3 describes reading "the first
4096 bytes" of the target and, on a non-blank/non-PDXB/non-PDXL
mismatch, hex-dumping the first 32 bytes for the operator. Issue #7's
own task brief narrows this to reading and inspecting only the first 4
bytes — the same four bytes the PDXB/PDXL magic checks already need —
with no hex-dump. `src/refusal.pdx` implements the narrower,
explicitly-specified 4-byte version. **Flagged for main**: a full
4096-byte scan (and the 32-byte hex-dump on `NON_BLANK`) is a real gap
vs. the upstream design doc's own §3.3 text, not just vs. a stricter
reading of the task brief — worth a follow-up issue if the fuller
diagnostic matters before M3.

Two more `mkfs_refuse_check` simplifications, both documented in that
file's own header and repeated here for visibility: (1) a failed
`sys_open` (most commonly `ENOENT` — target does not exist yet) is
treated as "proceed", with no attempt to distinguish that from a
different open failure (e.g. `EACCES`) that arguably deserves its own
diagnostic; the subsequent real `sys_open` in `mkfs_format_run` (with
`O_CREAT|O_WRONLY|O_TRUNC`) will surface a real permission problem as
its own `FAIL` record regardless. (2) A failed `sys_read` past a
successful open is handled the same way (proceed) rather than refusing
or failing outright. Both are reasonable M2 defaults but are scope
calls, not upstream-mandated behavior — flagged for main to revisit if
a stricter refusal-gate contract turns out to matter.

Separately: `--force` bypasses the ENTIRE gate with **no audit trace**
at M2 (§8's audit-journaling note above covers why — `libpdx-audit`
isn't linked yet). The design doc's own text is explicit that this is
supposed to be impossible ("`--force` bypasses the refusal but never
the audit trail", §3.3) — `mkfs.pdxfs.M3-004` inherits this as a
concrete, named gap to close, not just "add auditing eventually."

### 9.6 Cross-repo call: `pdxb_encode_superblock`

`Format::mkfs_format_run` calls `pdxb_encode_superblock` (defined in
the separate `libpdx-volume` repo) via a bare `call pdxb_encode_superblock;`
— no `extern`/import declaration of any kind. This is not a special
mechanism: `paideia-as` has no `extern` keyword at all (confirmed by
grepping `tools/paideia-as`'s own Rust source and design docs for the
token — zero hits as a language construct; every prose "extern" hit
elsewhere in this tree is a comment, not syntax). This repo's own
`tools/build.sh` already demonstrates the underlying mechanism WITHIN
one repo: it compiles every `src/*.pdx` file into an INDEPENDENT `.o`
with no multi-file compilation unit, yet `main.pdx` already calls
`argv_parse` / `target_classify` / `format_record_emit_dry_run` — each
defined in a different file/object — by bare label name. A `call
<label>` where `<label>` is not defined in the current compilation unit
becomes an ordinary undefined-global-symbol ELF relocation, resolved
whenever something finally links this repo's `.o` files together with
`libpdx-volume`'s (the same "once built and linked into a runnable
image" step `README.md` already flags as outside `build.sh`'s own
scope — `build.sh` compiles, it does not link). A cross-REPO call is
therefore syntactically and mechanically IDENTICAL to a cross-FILE call
within one repo: both are just "a label this compilation unit does not
define," resolved by whatever final link step assembles the runnable
image. No new build-system work was needed to make this call; `format.pdx`
simply relies on the same mechanism `main.pdx` already exercised at M1.

## 10. What M3 needed before it opened (historical — M3 has now landed)

This section originally listed M3's prerequisites; kept for history.
All five sub-issues landed (see §11 for the full write-up of each):
`libpdx-elevate` turned out to exist (contrary to this section's guess
that it might not) but with an API shape too different from this
issue's assumption to call for real (§11.5); `libpdx-semantic-pipe`
also exists and is released, but its schema-registry dependency is
inert (§11.3); `libpdx-volume`'s `pdxb_sign_superblock` landed exactly
as this section anticipated and is now wired for real (§11.2). Two
items this section flagged as "separate from M3 proper" remain OPEN
after M3 (see §11.6 for the current status of both): the `--size=`
data-region gap, and the bare-syscall-vs-`KIND_PDXFS_FILE`-cap
question.

## 11. M3 landing (#8-#12) — device target, signing, semantic-pipe,
audit, elevate

### 11.1 `mkfs.pdxfs.M3-001` (#8) — device-cap target: one real piece,
two confirmed-absent primitives

The naming gap §6 flagged is resolved (`KIND_BLOCK_DEVICE` = `KIND_
BLKDEV` = `0x42`, per `design/hardware/nvme-ahci-tail-milestones.md`
§3.1). What blocks a full device-target implementation is not the name
but two primitives a fresh grep confirms do not exist anywhere in this
kernel:

- **Cap introspection.** `sys_cap_query` was PLANNED at R13 (`design/
  milestones/r13-preflight.md`, `design/audit/entries/r13-m5-003-
  syscall-table.md`: "no cap_query symbol; R13-m2 milestone-gated") but
  never implemented — `design/user/syscall-table.md` (refreshed
  through sysno 95) has no `cap_query`/`cap_info` entry at any number.
  There is no syscall this repo could call to validate that a
  `cap:blkdev:0xNN` slot actually holds a `KIND_BLKDEV` cap.
- **Cap narrowing.** No `cap_narrow`/`sys_cap_narrow`/`cap_restrict`
  primitive exists in `src/kernel/` either. The closest real mechanism
  is MINT-TIME rights reduction (e.g. `blkdev_cap_mint(controller_idx,
  nsid, rights)`) — `design/tooling/volume-lifecycle-mechanism.md`
  calls this "the standard cap-narrowing discipline, no new
  mechanism". But minting a fresh, narrower `blkdev_cap` needs a
  `(controller_idx, nsid)` or `(bus, devfn)` pair, not the SLOT number
  a `cap:blkdev:0xNN` URI names (per `volume-tooling-ux.md` §3.2, `NN`
  is a slot in the invoker's own cap table) — even the mint-a-
  narrower-child-cap path is not constructible from what this repo has.

`src/target.pdx`'s new `mkfs_dev_parse_slot` is therefore the one REAL
piece of this issue: a working hex-slot parser (with an optional
`0x`/`0X` lead), following the same "malformed input silently yields a
partial/zero result" contract `argv_parse_u64_dec` already established.
`src/format.pdx`'s new `mkfs_format_run_device` calls it, then
immediately emits `PdxFsFormatRecord@0.1 { result_code:
DEVICE_TARGET_STUB }` — no write of any kind is attempted, since (per
this issue's own fallback instruction) a grep of `design/user/syscall-
table.md` finds only `blkdev_cap_request` (sysno 74, cap-MINTING) and
no block-granularity `sys_blkdev_write`/`sys_blkdev_read`-shaped
syscall at all.

### 11.2 `mkfs.pdxfs.M3-002` (#9) — superblock signing, real call +
placeholder seed

`libpdx-volume`'s M3 landing (commit `6f18957`) ships a real
`pdxb_sign_superblock(sb_ptr, seed_ptr, out_sig_ptr, out_sig_len) ->
u64`. Two things this repo's own M2-era anticipation got slightly
wrong, both now corrected in `src/format.pdx`'s module header:

- The signing argument is `seed_ptr` (a raw 32-byte-seed pointer), NOT
  `sig_key_slot` (a `KIND_SIG_KEY` cap slot) — `libpdx-volume`'s own
  module header explains the rename: `KIND_SIG_KEY` as landed is a
  PUBLIC-key handle, and no kernel capability kind anywhere holds a
  private ML-DSA-65 signing seed. `mkfs.pdxfs` therefore never
  dereferences `KIND_SIG_KEY` (still an untouched M1 placeholder).
- The call signs bytes `[0,696)` of the FULL 4096-byte encoded
  superblock (not the 176-byte `PdxbSuperblockSummary`) and writes its
  3309-byte output wherever `out_sig_ptr` points — `mkfs_format_run`
  passes `&mkfs_format_sb_encoded + 696` so the signature lands exactly
  at this issue's own instruction, `sb_ptr[696..696+3309)`, in place,
  before the buffer is written to the target.

**Seed-key strategy**: every superblock is signed with a PLACEHOLDER
all-zero 32-byte seed (`mkfs_sign_seed_zero`), regardless of whether
`--sig-key` was given — real seed-loading needs a `libpdx-key`-
equivalent library that does not exist anywhere in
`paideia-satellites/` as of this landing (the same "design-doc-
mentioned, not yet bootstrapped" status `libpdx-argv` had at M1). This
produces a well-FORMED ML-DSA-65 signature (real intrinsic, real
696-byte message) that will NOT verify against any real public key —
cryptographically inert, not merely absent. **Flagged for main**: this
is loud and deliberate per this issue's own acceptance text ("use a
placeholder seed... and document"), not a silent regression; the fix
is a real seed-loading path landing in a future library. Every
file-target success record now reads `result_code: SIGNED_OK`
(`FR_RESULT_SIGNED_OK = 8`) rather than M2's `OK = 0`.

### 11.3 `mkfs.pdxfs.M3-003` (#10) — semantic-pipe: real library, inert
registry, documented fallback

`libpdx-semantic-pipe` (github.com/paideia-os/libpdx-semantic-pipe) is
real and released (v1.0.0, wave R49, M1-M5 landed) with a working
`Send::send_record(fd, rec_ptr, rec_len)` framing entry point. But
schema-NAME resolution — `Registry::bind_by_name(fd, name_ptr,
name_len)`, the piece this repo would need to bind
`"PdxFsFormatRecord"` to a hash two independently-built tools can agree
on — is confirmed INERT via GitHub issue **paideia-os#2000** ("R90-
XREPO.006 Stand up libpdx-schema-registry service"): the backing
`svc.schema-registry` service does not exist, so `bind_by_name` always
returns 304 (LOOKUP_FAIL). The one real adopter, `ls`, works around
this by hand-imprinting a placeholder hash meaningful only to itself —
a pattern this repo's `src/pipe_wire.pdx` module header explicitly
declines to copy, since `mkfs.pdxfs` has no reader in this monorepo to
agree on such a hash with, and doing so would look real without being
real.

Per this issue's own fallback instruction, `mkfs.pdxfs` does not link
`libpdx-semantic-pipe` at M3. `src/pipe_wire.pdx`'s two wrappers
(`mkfs_sp_emit_dry_run`, `mkfs_sp_emit_result`) print one documented
deferral header line ("semantic-pipe emit deferred
(svc.schema-registry not yet live, paideia-os#2000)...") immediately
before delegating, unchanged, to `FormatRecord`'s existing line-based
emitters. `src/main.pdx` and `src/format.pdx` now call ONLY these
wrappers — the only call sites that will need to change once
`libpdx-schema-registry` lands and #2000 closes.

### 11.4 `mkfs.pdxfs.M3-004` (#11) — `libpdx-audit`: real calls, no
retain-forever kind, forgiving posture

`src/audit_wire.pdx` wraps `libpdx-audit`'s (@0.2, commit `bfc63a5`)
real `AuditClient::audit_begin`/`audit_commit` around EVERY `_start`
dispatch branch — file dry-run, file real-write, device-target
grant/deny, and "not yet implemented" all now open and commit an audit
record.

This issue's own task text asked for "a retain-forever `UEJ_KIND`" —
a full grep of `libpdx-audit`'s tree for "retain" (and for any kind
resembling "forever"/"permanent"/"vol_format") finds NOTHING. The only
`UEJ_KIND_*` constants that exist are `UEJ_KIND_TOOL_INVOKE = 130`,
`UEJ_KIND_TOOL_OUTPUT = 132`, `UEJ_KIND_TOOL_EXIT = 133` — none
caller-selectable; `audit_begin` takes only `(op_name_ptr,
op_args_ptr)`, no kind parameter at all. **Flagged for main**: if
retain-forever semantics matter specifically for volume-formatting
audit records, that is a `libpdx-audit` feature request. This repo
instead encodes the one real signal it can — `op_name` is
`"mkfs.pdxfs.format"` or `"mkfs.pdxfs.format.force"` depending on
`--force` — and `op_args` is the real `<target>` string.

Every outcome is treated as non-fatal, per this issue's own
instruction: `mkfs_audit_begin` never examines `audit_begin`'s return
value (0 on failure is a valid "did not audit" sentinel threaded
through unexamined); `mkfs_audit_commit` skips the call entirely when
`audit_id == 0` and discards `audit_commit`'s return value otherwise.
This matches libpdx-audit's own STATUS.md, which confirms the
audit-journal daemon's broker dispatch is still stubbed
(`audit_journal_broker_dispatch` returns `AJB_DISPATCH_STUB`) — a
real call getting back a quick no-op is expected, not an error.
`FormatRecord::FR_RESULT_AUDIT_FAIL` is defined for a future stricter
mode but is unreachable from this landing's forgiving posture.

### 11.5 `mkfs.pdxfs.M3-005` (#12) — `libpdx-elevate`: real library,
wrong assumed API, fail-closed stub

This issue's assumed API — `elevate_client_require(RESOURCE_KIND=
KIND_BLOCK_DEVICE, action=WRITE, target=<dev_slot>)` — does not exist
anywhere in `libpdx-elevate`'s real (4844 LOC, mature) source. Its
actual model is a capability-BITMASK `row_id` handle:
`elevate_client_acquire(caps, dur, req_buf, reply_ep_id, reply_buf,
mint_ctx_buf) -> row_id`, which REQUIRES the caller to already hold a
`KIND_IPC_ENDPOINT` cap over the elevate broker at a `parent_ep_slot`
— a prerequisite `libpdx-elevate`'s own README calls "declared by
whatever the caller links this library into, not by libpdx-elevate."
`mkfs.pdxfs`'s own `caps.decl` still carries `KIND_ELEVATE_CHANNEL =
0x191` as the M1 PLACEHOLDER it always was — no osarch coordination
has minted this repo a real broker-endpoint cap, and this M3 landing
does not change that.

Rather than fabricate a plausible-looking `elevate_client_acquire`/
`elevate_client_require` sequence against fields this repo cannot
honestly populate (`target_cap_kind`/`target_cap_rights` are opaque to
`libpdx-elevate` itself — no coordinated `KIND_BLKDEV`-write value
exists to pass), `src/elevate_wire.pdx`'s `mkfs_elev_require_device_
write` always returns `MKFS_ELEV_DENY`. This is deliberately
fail-closed, not a fabricated denial of a request that was never sent:
"cannot prove GRANT" and "DENY" are the same externally observable
outcome given the missing prerequisite. `src/main.pdx`'s
`mkfs_main_device_grant` arm (and `src/format.pdx`'s
`mkfs_format_run_device`) are real, wired code kept for the day a
broker-endpoint cap and a resolved `target_cap_kind`/`target_cap_rights`
pair exist — at which point only `mkfs_elev_require_device_write`'s
body needs to change, not any caller.

### 11.6 What remains open after M3

- The `--size=`-equivalent flag and real `data_lba`/`data_bcount`
  computation §9.1 flagged are STILL open — M3's five issues did not
  touch this.
- The bare-syscall-vs-`KIND_PDXFS_FILE`-cap question (`caps.decl`) is
  STILL open for the same reason.
- Device-target support end-to-end needs, in order: (1) a
  `sys_cap_query`-equivalent (§11.1), (2) a real block-granularity
  write syscall (§11.1), (3) `mkfs.pdxfs` acquiring a real
  `KIND_ELEVATE_CHANNEL` broker-endpoint cap and a coordinated
  `KIND_BLKDEV`-write `target_cap_kind`/`target_cap_rights` value with
  osarch (§11.5) — none of which is close to landing as of this M3.
- Real seed-key loading for signing (§11.2) needs a `libpdx-key`-
  equivalent library.
- `libpdx-schema-registry` (GitHub paideia-os#2000) needs to land
  before `src/pipe_wire.pdx` can bind a real schema by name (§11.3).

# mkfs.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M2 (core implementation) — **landed**
**Version:** unreleased (pre-1.0.0)

See `design/tooling/volume-tooling-ux.md` §9.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
full 18-issue breakdown this checklist mirrors.

## Milestone checklist

### M1 — Design + skeleton

- [x] **M1-001** — scaffold + `caps.decl` (`KIND_USER` + `KIND_PDXFS_FILE`
      + `KIND_BLOCK_DEVICE` placeholder + `KIND_SIG_KEY` placeholder):
      landed. Four source files (`src/main.pdx`, `src/argv.pdx`,
      `src/target.pdx`, `src/format_record.pdx`), `caps.decl`,
      `design/architecture.md`. `caps.decl` flags a naming gap between
      the design doc's aspirational `KIND_BLOCK_DEVICE` (0x198..0x19F
      band, not yet landed) and the kernel's existing `KIND_BLKDEV =
      0x42` — confirm with osarch before M3-001 mints against either.
- [x] **M1-002** — argv surface (`--force`, `--label`, `--journal-size`,
      `--dry-run`, `--verbose`, `--sig-key`, `<target>`): landed.
      `libpdx-argv` does not exist anywhere in the paideia-os monorepo
      or under `paideia-satellites/` as of this landing (confirmed via
      `grep`) — `src/argv.pdx` implements a minimal long-flag parser
      inline instead of blocking on that library. See
      `design/architecture.md` §3 for the deferral note; a future
      `libpdx-argv` integration can replace `Argv::argv_parse`'s body
      without an ABI change (same argc/argv-in, out-struct-pointer/
      status-code-out shape).
- [x] **M1-003** — first runnable: `mkfs.pdxfs --dry-run /tmp/foo.img`
      prints the `PdxFsFormatRecord@0.1` line it would emit: landed.
      `src/main.pdx`'s `_start` wires `Argv::argv_parse` →
      `Target::target_classify` → `FormatRecord::format_record_emit_
      dry_run`. The dry-run happy path is scoped to file targets only
      (per this issue's own acceptance text); a `--dry-run` against a
      `cap:blkdev:` target, or any invocation without `--dry-run`,
      falls through to a `not yet implemented` diagnostic + exit 1 (the
      real write path is M2/M3). The printed record is a REAL rendering
      of the caller's actual target/label/journal_size arguments, not a
      placeholder-value stub — see `src/format_record.pdx`'s module
      header for exactly which of the full 14-field
      `PdxFsFormatRecord@0.1` schema this M1 slice covers (four fields:
      `target`, `label`, `journal_size`, `dry_run`) and which are
      deferred to M3-003 along with the semantic-pipe binary framing
      itself.

### M2 — Core implementation

- [x] **M2-001** (#4) — target-taxonomy resolver: `target_classify`
      itself is unchanged from M1 (it was already a real, complete
      three-way byte-prefix classifier matching
      `design/tooling/volume-tooling-ux.md` §3.2 in full — not a
      placeholder). What changed: `src/main.pdx` now uses a
      `TARGET_FILE` classification to AUTHORIZE the real write pipeline
      (`src/format.pdx`'s `mkfs_format_run`), not just to pick a print
      branch. `TARGET_DEVICE_CAP` / `TARGET_INVALID` still fall through
      to "not yet implemented" (exit 1) regardless of `--dry-run` — the
      real device-cap resolver (minting a `KIND_BLOCK_DEVICE` cap,
      `libpdx-elevate`, mandatory signing) remains `mkfs.pdxfs.M3-001`.
      See `design/architecture.md` §9 for the full write-up, including
      why this repo did not narrow `target_classify`'s accepted file
      prefixes down to `/`-only (the design doc's own §3.2 names `/`,
      `~`, and `.`; #4's own restatement is read as shorthand for that
      three-way split, not a spec change).
- [x] **M2-002** (#5) — `src/format.pdx` (new): `mkfs_format_run` opens
      (create+truncate) the file-backed target, builds + encodes a real
      PDXB v1 superblock via `libpdx-volume.pdxb_encode_superblock`
      (cross-repo call, no `extern` keyword needed — see
      design/architecture.md §9), writes it at offset 0, then zeroes the
      inode table / allocator bitmap / journal ring via a chunked
      `mkfs_format_write_zeros` helper (no `lseek` syscall exists in this
      kernel — see the same §9 write-up for why the layout is instead
      produced via purely sequential writes). `--dry-run` is UNCHANGED
      from M1 and still short-circuits before any of this runs.
- [x] **M2-003** (#6) — root inode #1 (empty directory) is encoded
      inline by `src/format.pdx`'s `mkfs_format_encode_root_inode`,
      following the REAL 128-byte on-disk inode layout from
      `design/filesystem/volume-fs-substrate.md` §2.3 (not the looser
      mode/size/link_count/timestamp/block_ptrs vocabulary the issue
      text uses — see design/architecture.md §9 for the field-by-field
      mapping). `libpdx-volume` has no `inode_encoders` module yet;
      this is flagged there as a follow-up for that library.
- [x] **M2-004** (#7) — `src/refusal.pdx` (new): `mkfs_refuse_check`
      reads the target's first 4 bytes (when it exists and `--force` is
      not set) and refuses on a `"PDXB"` or `"PDXL"` magic match or any
      other non-zero content; a zero-filled or nonexistent target
      proceeds. `--force` bypasses the whole gate with no audit trace
      yet (the design doc's `REFUSED_OVERRIDDEN` audit sub-record needs
      `libpdx-audit`, linked at `mkfs.pdxfs.M3-004`). `format_record.pdx`
      grew a second emitter, `format_record_emit_result`, for the
      `result_code`-shaped record this gate (and every M2 write outcome)
      needs — the M1 `format_record_emit_dry_run` slice is untouched.

### M3 — Device-target + signing + semantic-pipe + audit + elevate (pending)

- [ ] **M3-001** — device-cap target path + `KIND_BLOCK_DEVICE(write)`
      narrowing.
- [ ] **M3-002** — superblock signing via
      `libpdx-volume.pdxb_sign_superblock` (mandatory on device
      targets).
- [ ] **M3-003** — semantic-pipe: `PdxFsFormatRecord@0.1` schema bind +
      emit (full 14-field record, replacing M1's 4-field text line).
- [ ] **M3-004** — `libpdx-audit`: pre-write journal record
      (retain-forever `UEJ_KIND_VOL_FORMAT`).
- [ ] **M3-005** — `libpdx-elevate`: `KIND_BLOCK_DEVICE(write, <dev>)`
      request when invoker lacks it.

### M4 — Tests + smoke (pending)

- [ ] **M4-001** — file-target happy path smoke.
- [ ] **M4-002** — non-blank refusal matrix + `--force` override +
      audit-trail assertion.
- [ ] **M4-003** — device-target smoke against QEMU virtio disk.
- [ ] **M4-004** — `--upgrade` path: PDXL → PDXB rewrite.

### M5 — Signed release (pending)

- [ ] **M5-001** — dual-signed `manifest.pdxsig` + CHANGELOG-1.0 +
      `.pdxdoc` for `doc mkfs.pdxfs`.
- [ ] **M5-002** — mirror push to `pkgs.paideia-os`.

## Next milestone

M3 opens once `mkfs.pdxfs.M2` closes. It needs: (1) the
`KIND_BLOCK_DEVICE` naming gap (`caps.decl`, `design/architecture.md`
§6) resolved with osarch before `M3-001` mints against either candidate
kind; (2) `libpdx-volume.pdxb_sign_superblock` (landed at
`libpdx-volume` commit `052cbac` per M3 there, ML-DSA-65-based) for
`M3-002` — mkfs.pdxfs.M2 deliberately leaves every superblock unsigned
(the `sig` region stays zeroed), matching the design doc's "file-backed
target, no `--sig-key`" discipline; (3) `libpdx-audit` linked for
`M3-004`'s pre-write journal record, which will also need to backfill
the `REFUSED_OVERRIDDEN` audit sub-record `M2-004`'s `--force` bypass
currently has no trace of at all.

## Upstream design

`design/tooling/volume-tooling-ux.md` §3 + §9.1 and
`design/filesystem/volume-fs-substrate.md` §2.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.

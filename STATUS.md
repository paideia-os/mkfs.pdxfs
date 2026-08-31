# mkfs.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M1 (design + skeleton) — **landed**
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

### M2 — Core implementation (pending)

- [ ] **M2-001** — target-taxonomy resolver: file path vs `cap:blkdev:`
      URI dispatch, real cap resolution (beyond `target.pdx`'s M1
      byte-prefix classifier).
- [ ] **M2-002** — write superblock + zero allocator bitmap + init
      journal ring (file-backed target only).
- [ ] **M2-003** — write root inode #1 as empty directory (uses
      `libpdx-volume` inode encoders).
- [ ] **M2-004** — non-blank refusal gate (§3.3): PDXB / PDXL /
      other-content diagnostics.

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

M2 opens once `mkfs.pdxfs.M1` closes and `libpdx-volume.M2`
(`pdxb_encode_superblock` real body) lands — M2-002's superblock write
links that function directly. `libpdx-volume.M1` has landed as of this
repo's M1 (see
[`libpdx-volume`](https://github.com/paideia-os/libpdx-volume)), but
its `pdxb_encode_superblock` is still a stub at M1 (returns
`PDXB_OK` without writing anything) — main should confirm
`libpdx-volume.M2` timing before opening `mkfs.pdxfs.M2-002`.

## Upstream design

`design/tooling/volume-tooling-ux.md` §3 + §9.1 and
`design/filesystem/volume-fs-substrate.md` §2.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.

# tests/ — mkfs.pdxfs test suite (M4)

**Milestone lineage.** M4 in `design/tooling/volume-tooling-ux.md` §9.1
(paideia-os). Four issues under this milestone in the
`paideia-os/mkfs.pdxfs` repo:

- **#13 — M4-001** file-target happy-path smoke.
- **#14 — M4-002** non-blank refusal matrix + `--force` override +
  audit-trail wiring.
- **#15 — M4-003** device-target smoke, STUB with a documented
  deferral.
- **#16 — M4-004** `--upgrade` (PDXL -> PDXB rewrite) path, STUB with a
  documented deferral.

All four landed at M4.

## Files

- `test_file_target_happy.pdx` — M4-001 driver. Exports
  `TestFileTargetHappy::run() -> u64`. Calls `PipeWire::
  mkfs_sp_emit_dry_run` and `Format::mkfs_format_run`
  (`src/pipe_wire.pdx`, `src/format.pdx`) directly against two real
  scratch paths under `/tmp`, driving a fresh-target write, a
  without-`--force` refusal against the now-formatted target, and a
  `--force` override rewrite. Returns 0 on all four phases passing, or
  the 1-based phase number of the first mismatch (1..4).
- `test_refusal_matrix.pdx` — M4-002 driver. Exports
  `TestRefusalMatrix::run() -> u64`. Writes three real 4-byte fixture
  files (`"PDXB"`, `"PDXL"`, `"XYZQ"`) and calls `Refusal::
  mkfs_refuse_check` (`src/refusal.pdx`) against each, plus a
  best-effort-unlinked blank target and a `--force` override against the
  PDXB fixture -- five comparable phases -- then exercises (without
  asserting a return code against, since neither has one) `AuditWire::
  mkfs_audit_begin`/`mkfs_audit_commit` (`src/audit_wire.pdx`) once per
  `force_flag` value. Returns 0 on all five comparable phases passing,
  1..5 for the first mismatched phase, or 9 if a fixture file could not
  be created (an environment failure, not a refusal-gate bug).
- `test_device_target_smoke.pdx` — M4-003 driver, **a documented STUB**.
  Exports `TestDeviceTargetSmoke::run() -> u64`. Calls `Format::
  mkfs_format_run_device` (`src/format.pdx`, M3-001) directly against a
  syntactically valid `cap:blkdev:` URI and asserts its return equals
  `MKFS_EXIT_DEVICE_STUB` (4). This is NOT an end-to-end write-then-
  readback smoke against a real QEMU virtio disk -- see the file's own
  header for the full repo-wide substrate gap (no `sys_cap_query`-
  equivalent, no block-granularity write syscall, no real
  `KIND_ELEVATE_CHANNEL` broker cap) that blocks one. Returns 0 if the
  stub's sentinel matched, 1 otherwise.
- `test_upgrade_stub.pdx` — M4-004 driver, **a documented STUB**.
  Exports `TestUpgradeStub::run() -> u64`. Builds a synthetic 3-element
  `argv[]` containing `--upgrade` and calls `Argv::argv_parse`
  (`src/argv.pdx`) to verify the new `PA_FLAG_UPGRADE` bit parses, then
  calls `Upgrade::mkfs_upgrade_run` (`src/upgrade.pdx`, new at M4-004)
  directly and asserts it returns `MKFS_EXIT_UPGRADE_NOT_IMPLEMENTED`
  (7). `src/main.pdx`'s own dispatch does not branch on
  `PA_FLAG_UPGRADE` yet -- see `src/upgrade.pdx`'s own module header.
  Returns 0 if both phases passed, 1..3 for the first mismatch.

## Return-code convention

Every M4 test driver in this tree returns a `u64` where `0` means "every
phase passed" and any nonzero value identifies which phase failed first
(see each file's own header for its exact nonzero-code table). This
mirrors the convention `libpdx-volume`'s and `libpdx-audit`'s own M4
test drivers use (this org's other satellite repos) — see
`libpdx-volume/tests/README.md` for the fuller rationale.

A test harness (in a future consumer tool) walks the driver list and
reports each nonzero return using the table in that driver's own file
header; the process exits 0 iff every driver returned 0.

## Why these drivers issue REAL syscalls, unlike libpdx-volume's

`libpdx-volume` is a shared library that issues zero syscalls anywhere
in its own call graph (its `tests/README.md` documents this in full),
so its M4 drivers are pure `.bss`/pointer fixtures. `mkfs.pdxfs` is
different: it is a standalone ring-3 ELF that performs REAL
`sys_open`/`sys_read`/`sys_write`/`sys_close`/`sys_unlink` calls against
bare filesystem paths (`src/format.pdx` and `src/refusal.pdx`'s own
module headers — no `KIND_PDXFS_FILE` cap is minted or consumed
anywhere in this repo's call graph, per `caps.decl`'s own note). A
"smoke test" of `mkfs_format_run` or `mkfs_refuse_check` therefore
cannot be a hermetic fuzz driver the way `libpdx-volume`'s
`pdxb_encode_superblock` round-trip driver is — `test_file_target_happy.
pdx` and `test_refusal_matrix.pdx` both perform real, destructive I/O
against scratch paths under `/tmp` when linked and run under a real
QEMU boot with a writable mount. Both drivers are written to be
idempotent across repeated runs (best-effort `sys_unlink` before any
assertion that depends on a target's prior absence).

`test_device_target_smoke.pdx` and `test_upgrade_stub.pdx` are the two
exceptions inherited from this milestone's own two STUB issues (#15,
#16) — see each file's own header for why a real end-to-end exercise is
not yet constructible, and what substrate has to land first.

## What a full QEMU smoke matrix still needs

- **M4-001 / M4-002** are runnable today against any writable
  filesystem this driver's consumer links and executes under — a real
  QEMU boot with `/tmp` writable is the only thing missing before these
  run for real (this milestone does not itself build or boot anything —
  see the top-level task instructions this landing was scoped under).
- **M4-003** additionally needs, in order: a `sys_cap_query`-equivalent
  syscall, a real block-granularity write syscall, and a real
  `KIND_ELEVATE_CHANNEL` broker-endpoint capability coordinated with
  osarch — see `test_device_target_smoke.pdx`'s own header and
  `design/architecture.md` §11.6 in this repo.
- **M4-004** additionally needs a real PDXL on-disk layout decoder (no
  `pdxl_*` module exists anywhere in `libpdx-volume` as of this
  landing) and a `src/main.pdx` dispatch decision for where `--upgrade`
  short-circuits relative to the existing refusal gate — see
  `src/upgrade.pdx`'s own module header.

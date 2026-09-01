# mkfs.pdxfs — CHANGELOG

## Unreleased

- **ELF-linking phase** for `tools/build.sh`, part of wiring this repo
  into paideia-os's boot-time `/bin` seeding pipeline
  (paideia-os#1976/#1977). Adds `link.ld` (the `PT_LOAD`/`text`+`data`
  pattern from paideia-os's `src/user/true.ld`, `.data`/`.bss`
  contiguous per paideia-os#1595) and a link step that runs `ld
  -nostdlib --warn-common --fatal-warnings -T link.ld` over this
  repo's own `src/*.o` objects (not `tests/*.o`) once compilation
  succeeds, producing `build-out/mkfs.pdxfs.elf` (plus a matching
  `.bin` via `objcopy`). `tools/build.sh` now also accepts one or more
  repeatable `--extra-obj-dir DIR` flags to fold in pre-built
  dependency objects (e.g. `libpdx-volume`, `libpdx-audit`) at link
  time; a missing or empty `DIR` is not an error.

## 1.0.0 — 2026-08-31 (R53 wave close, M5)

**First release.** Manifest scaffolded for a future dual-signed
(Ed25519 + ML-DSA-65) release per
`design/02-development-environment.md` §1140 (paideia-os); the actual
dual-sign + mirror-push run is deferred (see "Known deferred substrate"
below). Ships `.pdxdoc` for `doc mkfs.pdxfs` and a release manifest
source form targeting `https://pkgs.paideia-os/main/mkfs.pdxfs/1.0.0/`
per `release/RELEASE-1.0.0.md`.

### Landed

- **M1-001..M1-003** scaffold + `caps.decl` + argv surface + first
  runnable `--dry-run` preview against a file target.
- **M2-001..M2-004** the real file-target write pipeline: superblock
  encode + write, zeroed inode table with a real root-directory inode
  at slot 1, zeroed allocator bitmap, zeroed journal ring, and the
  non-blank refusal gate (`PDXB`/`PDXL`/other-non-blank), bypassable
  only by `--force`.
- **M3-001** device-cap target path: a real hex-slot parser
  (`mkfs_dev_parse_slot`); kind validation and cap-narrowing remain
  documented stubs (no `sys_cap_query`/`cap_narrow`-equivalent
  primitive exists in this kernel).
- **M3-002** superblock signing: every file-target write is now signed
  via `libpdx-volume`'s real `pdxb_sign_superblock`, using a
  PLACEHOLDER all-zero 32-byte seed (real seed-loading needs a
  `libpdx-key`-equivalent that does not exist yet). Success records now
  read `result_code: SIGNED_OK`.
- **M3-003** semantic-pipe emission wrappers (`src/pipe_wire.pdx`) —
  `libpdx-semantic-pipe` v1.0.0 is real and released but its
  schema-registry dependency is inert (paideia-os#2000); every record
  stays the line-based `sys_write` rendering, now preceded by a
  documented deferral header.
- **M3-004** `libpdx-audit` integration (`src/audit_wire.pdx`) — every
  `_start` dispatch branch now opens and commits a real audit record
  (the daemon-side dispatch is itself confirmed stubbed).
- **M3-005** `libpdx-elevate` wiring (`src/elevate_wire.pdx`) — a
  documented fail-closed stub (always DENY); this repo holds no
  `KIND_ELEVATE_CHANNEL` broker-endpoint capability to call the
  library's real API with.
- **M4-001** (#13) file-target happy-path smoke
  (`tests/test_file_target_happy.pdx`) — dry-run structural check plus
  a real fresh-write / without-force-refusal / --force-override round
  trip against a scratch target.
- **M4-002** (#14) non-blank refusal matrix + `--force` override +
  audit-trail wiring (`tests/test_refusal_matrix.pdx`) — real
  fixture files stamped `PDXB`/`PDXL`/other-non-blank, plus a blank
  target and a force-override case.
- **M4-003** (#15) device-target smoke, a documented STUB
  (`tests/test_device_target_smoke.pdx`) — asserts
  `mkfs_format_run_device`'s stub return code; a real QEMU-virtio
  smoke needs a `sys_cap_query`-equivalent, a real block-write
  syscall, and a real elevate broker cap, none of which exist yet.
- **M4-004** (#16) `--upgrade` flag + stub (`src/argv.pdx`'s
  `PA_FLAG_UPGRADE`, new `src/upgrade.pdx`'s `mkfs_upgrade_run`,
  `tests/test_upgrade_stub.pdx`) — minimal-effort wiring per this
  issue's own fallback instruction; not yet reachable from `_start`'s
  own dispatch.
- **M5** (#17, #18) dual-signed release scaffold + `.pdxdoc` +
  mirror-push documentation. Ships `doc/mkfs.pdxfs.pdxdoc` source
  form, `release/manifest.pdxsig.txt` release-manifest source (every
  hash and signature slot a documented placeholder), and
  `release/RELEASE-1.0.0.md` operator runbook + release note +
  distribution section (documents, but does not perform, the
  `pkgs.paideia-os` mirror push). Actual dual-sign + mirror-push
  deferred — see "Known deferred substrate" below.

### Known deferred substrate

- **Device-target write path.** Fully stubbed at the write-attempt
  layer (no block-granularity write syscall exists) and unreachable in
  practice regardless (elevation always denies first, since this repo
  holds no broker-endpoint capability). Needs, in order: a
  `sys_cap_query`-equivalent syscall, a real block-write syscall, and a
  real `KIND_ELEVATE_CHANNEL` broker cap coordinated with osarch.
- **Signing uses a placeholder all-zero seed.** Every signature this
  tool produces is well-formed but verifies against no real key. A
  `libpdx-key`-equivalent (or an inline `--sig-key` loader) is needed
  before signed superblocks are meaningfully verifiable.
- **No retain-forever `UEJ_KIND`** exists in `libpdx-audit`@0.2 — a
  `libpdx-audit` feature request, not something this repo can wire
  against today. The `REFUSED_OVERRIDDEN` audit sub-record for a
  `--force` bypass also has no dedicated wire shape in that library's
  real API.
- **`libpdx-semantic-pipe` linking is deferred** until
  `svc.schema-registry` (paideia-os#2000) lands and
  `Registry::bind_by_name` stops being inert.
- **`--upgrade` has no real rewrite body and no dispatch wiring.** No
  PDXL on-disk decoder exists anywhere in `libpdx-volume`, and
  `src/main.pdx`'s own dispatch does not branch on
  `PA_FLAG_UPGRADE` yet.
- **No `--size=`-equivalent flag / real data-region sizing.** Every
  volume this tool formats has a zero-sized data region.
- **Dual-sign + mirror-push run.** Repo-side scaffolding at M5 is
  complete. The signed build + HTTP-PUT to
  `pkgs.paideia-os/main/mkfs.pdxfs/1.0.0/` requires: (a) the
  paideia-as ≥ 0.24.0-mldsa65-sign toolchain reachable in CI, (b) the
  `pkgs.paideia-os` mirror endpoint standing (does not exist as of
  R53 close), (c) a live release-line ML-DSA-65 seed key
  (hardware-backed custody, never repo-resident), and (d) an actual
  link pass against `libpdx-volume`'s and `libpdx-audit`'s compiled
  objects (`tools/build.sh` compiles but does not link). Until all
  four go green, `release/manifest.pdxsig.txt` ships with the
  placeholder value `SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN` in every
  signature slot; see `release/RELEASE-1.0.0.md` §3.
- **`doc` M2 compile pass.** The `.pdxdoc` compiled binary form ships
  once `doc`.M2 lands. Until then consumers render the source form
  verbatim.

### Semver policy

- **Major** — argv-surface removal, exit-code renumber, on-disk layout
  change, or record-shape removal.
- **Minor** — additive surface (e.g. a real `--upgrade` rewrite body, a
  real device-target write path, real `--sig-key` seed loading, a
  `--size=` flag).
- **Patch** — correctness fixes, constant tuning, the deferred
  dual-sign + mirror-push run itself (no repo-side code change).

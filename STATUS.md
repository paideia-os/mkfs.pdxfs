# mkfs.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M5 (dual-signed release) — **landed**
**Version:** 1.0.0

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

### M3 — Device-target + signing + semantic-pipe + audit + elevate

- [x] **M3-001** (#8) — device-cap target path: `src/target.pdx` gains a
      REAL `mkfs_dev_parse_slot` (hex-slot parser for `cap:blkdev:0xNN`,
      with an optional `0x`/`0X` lead). `KIND_BLOCK_DEVICE(write)`
      NARROWING and kind VALIDATION are documented STUBs -- confirmed
      via grep that no `sys_cap_query`/`cap_narrow` (or equivalent)
      primitive exists anywhere in this kernel (R13 planned
      `sys_cap_query`, never implemented). `src/format.pdx`'s new
      `mkfs_format_run_device` therefore parses the slot then emits
      `PdxFsFormatRecord@0.1 { result_code: DEVICE_TARGET_STUB }`
      without attempting any write (no block-granularity write syscall
      exists either -- only the cap-minting `blkdev_cap_request`,
      sysno 74). The `KIND_BLOCK_DEVICE`/`KIND_BLKDEV` naming gap M1/M2
      flagged is RESOLVED: `design/hardware/nvme-ahci-tail-
      milestones.md` §3.1 confirms `KIND_BLOCK_DEVICE` is a
      doc-readability alias for the landed `KIND_BLKDEV = 0x42`.
- [x] **M3-002** (#9) — superblock signing: `src/format.pdx`'s
      `mkfs_format_run` now calls `libpdx-volume.pdxb_sign_superblock`
      (real, landed at libpdx-volume commit `6f18957`) on EVERY
      file-target write, before the superblock is written, signing
      bytes `[0,696)` and overwriting `sb_ptr[696..696+3309)` with the
      result. Seed strategy: a PLACEHOLDER all-zero 32-byte seed
      (`mkfs_sign_seed_zero`) -- real seed-loading needs a `libpdx-key`
      -equivalent that does not exist yet, so this signature is
      well-FORMED but not verifiable against any real key. The
      terminal success record is now `result_code: SIGNED_OK`
      (`FormatRecord::FR_RESULT_SIGNED_OK`), replacing M2's `OK`.
- [x] **M3-003** (#10) — semantic-pipe: `src/pipe_wire.pdx` (new).
      `libpdx-semantic-pipe` v1.0.0 is real and released, but its
      `Registry::bind_by_name` is confirmed INERT (GitHub
      paideia-os#2000: the backing `svc.schema-registry` service does
      not exist, `bind_by_name` always returns 304). Per this issue's
      own fallback instruction, this repo does NOT link the library --
      every `PdxFsFormatRecord@0.1` this repo emits stays the M1/M2
      line-based `sys_write(1, ...)` rendering, now preceded by one
      documented deferral header line. `src/main.pdx` and
      `src/format.pdx` now call ONLY `pipe_wire.pdx`'s two wrappers,
      never `FormatRecord`'s emitters directly.
- [x] **M3-004** (#11) — `libpdx-audit` (@0.2, commit `bfc63a5`):
      `src/audit_wire.pdx` (new) wraps EVERY `_start` dispatch branch
      (file dry-run, file real-write, device-target grant/deny, and
      "not yet implemented") in a real `AuditClient::audit_begin` /
      `audit_commit` pair. No retain-forever `UEJ_KIND` exists in
      libpdx-audit @0.2 (grepped, confirmed absent) -- `audit_begin`
      has no caller-selectable "kind" parameter at all, only a fixed
      internal mapping to `UEJ_KIND_TOOL_INVOKE`; flagged for main.
      The audit-journal daemon dispatch is confirmed stubbed
      (libpdx-audit's own STATUS.md: `AJB_DISPATCH_STUB`), matching
      this issue's own forgiving-posture instruction -- every outcome
      is treated as non-fatal.
- [x] **M3-005** (#12) — `libpdx-elevate` (4844 LOC, mature):
      `src/elevate_wire.pdx` (new). This issue's assumed API shape
      (`elevate_client_require(RESOURCE_KIND=..., action=WRITE,
      target=<slot>)`) does not exist in the real library -- its actual
      model is a capability-bitmask `row_id` handle requiring a
      `parent_ep_slot` broker-endpoint cap this repo does not hold
      (`KIND_ELEVATE_CHANNEL` is still the M1 placeholder). Rather than
      fabricate a plausible-looking call against fields this repo
      cannot honestly populate, `mkfs_elev_require_device_write` is a
      documented, fail-closed stub that always returns DENY. The GRANT
      arm of `src/main.pdx`'s dispatch (and `mkfs_format_run_device`)
      is real, wired code -- unreachable at this landing, live the
      moment a real broker cap exists.

### M4 — Tests + smoke

- [x] **M4-001** (#13) — file-target happy path smoke:
      `tests/test_file_target_happy.pdx`. Calls `mkfs_sp_emit_dry_run`
      and `mkfs_format_run` directly against real scratch paths under
      `/tmp` (unlike libpdx-volume's own M4 drivers, this repo issues
      real syscalls -- no `KIND_PDXFS_FILE` cap exists to mock against
      instead, see `caps.decl`). Four phases: dry-run leaves no file
      behind, a fresh-target write returns `MKFS_EXIT_OK`, a repeat
      without `--force` returns `MKFS_EXIT_REFUSED`, and a repeat with
      `--force` returns `MKFS_EXIT_OK` again.
- [x] **M4-002** (#14) — non-blank refusal matrix + `--force` override +
      audit-trail wiring: `tests/test_refusal_matrix.pdx`. Writes real
      4-byte fixture files (`"PDXB"`, `"PDXL"`, `"XYZQ"`) and calls
      `mkfs_refuse_check` against each, plus a blank/nonexistent target
      and a `--force` override against the PDXB fixture -- five
      comparable phases -- then exercises (without a return-code
      assertion, since neither call has one) `mkfs_audit_begin`/
      `mkfs_audit_commit` once per `force_flag` value.
- [x] **M4-003** (#15) — device-target smoke, **a documented STUB**:
      `tests/test_device_target_smoke.pdx`. Calls
      `mkfs_format_run_device` directly and asserts
      `MKFS_EXIT_DEVICE_STUB`. NOT a real QEMU-virtio write-then-
      readback smoke -- no `sys_cap_query`-equivalent syscall, no
      block-granularity write syscall, and no real
      `KIND_ELEVATE_CHANNEL` broker cap exist to build one against (see
      `design/architecture.md` §11.1/§11.6 and the test file's own
      module header).
- [x] **M4-004** (#16) — `--upgrade` path, **a documented STUB**:
      `src/argv.pdx` gained `PA_FLAG_UPGRADE` (0x40, exact-match
      `--upgrade`); new `src/upgrade.pdx` (`Upgrade::mkfs_upgrade_run`)
      emits `PdxFsFormatRecord@0.1 { result_code:
      UPGRADE_NOT_IMPLEMENTED }` and returns
      `MKFS_EXIT_UPGRADE_NOT_IMPLEMENTED` (7); `src/format_record.pdx`
      gained the matching `FR_RESULT_UPGRADE_NOT_IMPLEMENTED` (9) code
      and literal. `tests/test_upgrade_stub.pdx` verifies both the argv
      wiring and the stub return code. `src/main.pdx`'s own dispatch
      does NOT branch on `PA_FLAG_UPGRADE` yet -- flagged for main in
      `src/upgrade.pdx`'s own module header (no PDXL on-disk decoder
      exists anywhere in `libpdx-volume` to rewrite from, and no design
      decision has been made about where `--upgrade` should
      short-circuit relative to the existing refusal gate).

### M5 — Signed release

- [x] **M5** (#17, #18) — dual-signed `manifest.pdxsig` + CHANGELOG-1.0
      + `.pdxdoc` for `doc mkfs.pdxfs`, plus distribution
      documentation. `release/manifest.pdxsig.txt` (every hash and
      signature slot a documented `SIGNATURE_PLACEHOLDER_PENDING_LIVE_
      SIGN`/`<BLAKE3-*>` placeholder), `release/RELEASE-1.0.0.md`
      (operator runbook + release note + §5 distribution section
      documenting, but not performing, the `pkgs.paideia-os` mirror
      push per #18's own scope), `doc/mkfs.pdxfs.pdxdoc` (source-form
      user-facing doc), `CHANGELOG.md` (the `## 1.0.0` entry). Actual
      dual-sign, link, and mirror push are all out of scope for this
      milestone -- see `release/RELEASE-1.0.0.md` §3 for the four
      substrate items still needed (toolchain, mirror endpoint, live
      seed key, an actual link pass).

## Next milestone

R53's own five-milestone mkfs.pdxfs scope (M1..M5) is now closed. What
remains is substrate this repo cannot manufacture on its own -- see
`release/RELEASE-1.0.0.md` §2/§3 for the full list. The concrete gaps
M3 left open, still true at M5 close:

1. **Device-target write path is fully stubbed** (§ M3-001, M3-005):
   no `sys_cap_query`/`cap_narrow`-equivalent primitive exists in this
   kernel, and no block-granularity write syscall exists either (only
   the cap-minting `blkdev_cap_request`). A `cap:blkdev:` target always
   produces `ELEVATION_DENIED` (fail-closed, since `libpdx-elevate`
   needs a broker-endpoint cap this repo does not hold) before ever
   reaching the `DEVICE_TARGET_STUB` write attempt. M4-003's own
   "device-target smoke against QEMU virtio disk" needs at minimum a
   real `KIND_ELEVATE_CHANNEL` broker cap for mkfs.pdxfs to acquire
   from, plus a real block-write syscall, before it can exercise
   anything beyond the DENY path.
2. **Signing uses a placeholder all-zero seed** (§ M3-002): every
   signature this landing produces is well-formed but verifies against
   no real key. A `libpdx-key`-equivalent (or an inline `--sig-key`
   loader) is needed before signed superblocks are meaningfully
   verifiable.
3. **No retain-forever `UEJ_KIND`** exists in `libpdx-audit` @0.2 (§
   M3-004) -- if volume-formatting operations specifically need
   retain-forever semantics, that is a `libpdx-audit` feature request,
   not something this repo can wire against today. Also still open
   from M2: the `REFUSED_OVERRIDDEN` audit sub-record for a `--force`
   bypass has no dedicated wire shape in libpdx-audit's real API
   (`audit_begin`'s two-string `op_name`/`op_args` distinguishes a
   forced invocation only informally, via `mkfs.pdxfs.format.force` as
   `op_name`).
4. **`libpdx-semantic-pipe` linking is deferred** (§ M3-003) until
   GitHub paideia-os#2000 (`svc.schema-registry`) lands and
   `Registry::bind_by_name` stops being inert.

## Upstream design

`design/tooling/volume-tooling-ux.md` §3 + §9.1 and
`design/filesystem/volume-fs-substrate.md` §2.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.

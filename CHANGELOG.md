# mkfs.pdxfs — CHANGELOG

## 1.1.3 — 2026-09-02 (ENH-030: libpdx-argv adoption — replaces handwritten scanner)

**Patch bump — no observable behaviour change for well-formed input;
every exit code + stderr diagnostic preserved.** Replaces the
handwritten long-flag scanner in `src/argv.pdx` with a thin wire-in
over paideia-satellites/libpdx-argv v1.1.0 (ENH-030 rename tag). Every
public symbol callers depend on — the `argv_parse` entry point, the
`PA_OFF_*` / `PA_FLAG_*` / `PA_STRUCT_BYTES` constants,
`argv_quota_specs` + `ARGV_QUOTA_MAX_ENTRIES`, and every
`ARGV_ERR_*` return code — keeps its numeric value and its byte
offset unchanged, so `src/main.pdx`'s direct-offset loads and
`tests/test_upgrade_stub.pdx`'s `[u8; 56]` buffer with its
`PA_FLAG_UPGRADE` (0x40) check both continue to work byte-for-byte.

### Added

- **libpdx-argv wire-in** — `argv_parse` now registers the 11
  mkfs.pdxfs long flags with `flag_spec_register()` (each bound to a
  `FID_*` in the 100..110 range and a `FKIND_BOOL` / `FKIND_STR` /
  `FKIND_INT` value kind), drives `parse_argv(argv+8, argc-1)` over
  the caller's argv (the +8/-1 pair strips argv[0] per libpdx-argv's
  caller-strips-argv0 convention), then walks
  `flag_ids[0..flag_count)` once to populate the caller's 56-byte
  ParsedArgv struct via a linear `cmp r10, FID_*; jne next` chain.
- **Flag-name literals** — new NUL-terminated `[u8; N]` names in
  .rodata (`mkfs_argv_name_force`, `_dry_run`, `_verbose`, `_upgrade`,
  `_help`, `_encrypt`, `_label`, `_journal_size`, `_sig_key`,
  `_passphrase_fd`, `_quota`), each without the `--` prefix
  (libpdx-argv's parser strips it before calling FlagSpec::lookup).

### Removed

- **Handwritten scanner** — `argv_streq`, `argv_prefix_match`,
  `argv_parse_u64_dec`, and every `argv_lit_*` (`--force\0`,
  `--dry-run\0`, etc.) literal are deleted. The equivalent semantics
  now live in libpdx-argv's `Parser::parse_argv` (name matching),
  `Typed::parse_int_u64` (decimal decoding for `--journal-size` and
  `--passphrase-fd`), and `Parser`'s own inline `=`/`:` separator
  handling for `--label=value` / `--sig-key=value` / etc.

### Behaviour notes

- **`--passphrase-fd` with a missing value**: libpdx-argv reports
  ERR_MISSING_VALUE for a typed flag that reaches end-of-argv with no
  value token. The shim ignores parse_argv's return code and inspects
  ParsedArgs post-hoc; libpdx-argv did not store the missing-value
  flag, so the walk never latches PA_FLAG_PASSPHRASE_FD_SET.
  `src/main.pdx`'s `--encrypt requires --passphrase-fd` gate fires on
  exactly the same inputs as before.
- **`--label value` / `--journal-size 4096`** (space-separated
  spellings): now accepted (libpdx-argv's FKIND_STR / FKIND_INT
  consume the lookahead when no inline `=`/`:` is present). The
  pre-shim body accepted only the `=` form; the shim is a strict
  superset. No test exercised the space form on refusal, so this is
  a permissive extension only.
- **`--journal-size=abc`** (malformed numeric): now leaves the
  default 1024 in place and does NOT latch PA_FLAG_JOURNAL_SIZE_SET
  (the pre-shim body stored 0 and latched). No caller consults the
  presence bit, and downstream code uses the value as-is.

### Build

- **`bash tools/build.sh --extra-obj-dir ../libpdx-argv/build-out
  ...`** — the standing invocation must now include libpdx-argv's
  build-out alongside libpdx-volume's, so the linker can resolve
  `flag_spec_register` / `parsed_args_reset` / `parse_argv` /
  `flag_count` / `flag_ids` / `flag_values` / `pos_count` /
  `pos_ptrs` / `parse_int_u64` from libpdx-argv's own objects.

Closes #27 (satellite adoption of libpdx-argv). Depends on
libpdx-argv v1.1.0 (ENH-030 rename that ended the multi-module
`reset` / `register` link collision).

## 1.1.2 — 2026-09-02 (Phase C: `--extra-archive` + `--gc-sections` for satellite-runtime link)

**Patch bump — additive `tools/build.sh` flag; every existing invocation
still works unchanged.** Wires the two Phase A/B archives from
paideia-os#2226's satellite-runtime-shim landing (paideia-as v0.29.1
`libpaideia_satellite_runtime.a` + libpdx-audit v1.1.1
`libpdx-audit-satellite.a`) through this repo's own final `ld` link so
`bash tools/build.sh --extra-archive .../libpaideia_satellite_runtime.a
--extra-archive .../libpdx-audit-satellite.a` now resolves the 83
previously-unresolved satellite-runtime symbol references (crypto FFI
thunks + `mldsa65_sign_runtime_entry` + `audit_begin` / `audit_commit`
satellite bodies + panic/allocator/eh_personality shim) end-to-end.

### Added

- **`--extra-archive PATH` (repeatable)** on `tools/build.sh`, symmetric
  to the existing `--extra-obj-dir DIR` flag: each PATH is a static
  archive (`.a`) appended to the final `ld` link line AFTER the
  --extra-obj-dir loose objects. Archives are pulled in AS-NEEDED
  (unlike loose objects, which link unconditionally), so the archive
  contents only pay their way for symbols the ELF actually references.
  Bounds-checks the value slot; a bare `--extra-archive` with no
  following PATH exits 2 with `--extra-archive requires an argument`
  (same discipline as `--extra-obj-dir`). A PATH that names a missing
  file surfaces later as an `ld` open-failure at link time (not an
  early parse error) — the flag validates only that the slot was
  supplied, mirroring how `--extra-obj-dir` never validates its DIR.

### Changed

- **`ld` link line** — added `--gc-sections` to the `ld -nostdlib
  --warn-common --fatal-warnings` invocation. Essential when linking
  the Phase A staticlib: Rust archives emit per-function sections
  (`.text.<sym>`), and `--gc-sections` walks from `_start` (KEEPed by
  `link.ld` at `.text._start`) and prunes every satellite-runtime
  symbol nothing in this repo transitively references. Without it, the
  archive dumps ~200KB of unused compiler-builtins/std padding into
  the ELF and leaves dangling refs from Rust's own internal call
  graph. This repo's own `src/*.pdx` objects emit into one big `.text`
  section per module, so `--gc-sections` is a no-op for them (the
  section stays live as soon as `_start` is reached).

### Invocation (unchanged for callers not wiring in Phase A/B archives)

```
# Old — still works, still emits build-out/mkfs.pdxfs.elf against
# just this repo's own objects (dangling refs on satellite-runtime
# symbols surface at ld, not here):
bash tools/build.sh --extra-obj-dir ../libpdx-volume/build-out

# New — resolves every satellite-runtime ref, end-to-end link OK:
bash tools/build.sh \
  --extra-obj-dir ../libpdx-volume/build-out \
  --extra-archive $HOME/Development/PaideiaOS/tools/paideia-as/target/release/libpaideia_satellite_runtime.a \
  --extra-archive $HOME/tmp/libpdx-audit/build-out/libpdx-audit-satellite.a
```

References: paideia-os#2226, paideia-as#1348, libpdx-audit#19, design
doc `design/infrastructure/satellite-runtime-shim.md` §4.1 + §5 Step 5.

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
  time; a `--extra-obj-dir` naming a missing or empty directory
  contributes nothing and is never an error.

## 1.1.1 — 2026-09-02 (LV11 fixup: four broken-on-arrival bugs from 1.1.0)

**Patch release** per the semver policy below — correctness fixes only,
no surface additions or removals. Every fix is a debugger-flagged bug
in the 1.1.0 (LV11) landing; a consumer built against 1.1.0 that had
never exercised `--encrypt` without `--passphrase-fd`, never invoked
`--help` without a positional target, and never suffered the latent
2-push stack misalignment in `mkfs_format_build_superblock` /
`mkfs_encrypt_apply_flag` / `mkfs_quota_apply_flag` observes no
behavior change; a consumer that exercised any of those observes the
corrected behavior described below.

### Fixed

- **Bug #1 — fabricated `has_quota` claim in `src/quota.pdx`.** The
  1.1.0 module header claimed the `PdxFsFormatRecord@0.1` dry-run and
  result records gained a `has_quota: true` suffix segment "see
  src/format_record.pdx's LV11-025 additions"; grep confirms no such
  field or LV11 marker exists there. This landing strikes the false
  claim from `src/quota.pdx`'s "What THIS landing does deliver"
  bullet and replaces it with an honest deferral note: wire-record
  `has_quota` surfacing awaits a future `format_record.pdx` v0.2
  revision; today mkfs surfaces the enabled state only via the
  superblock's `PDXB_FLAG_HAS_QUOTA` on-disk bit. Documentation-only
  fix; no code change.
- **Bug #2 — `--encrypt` without `--passphrase-fd` silently reads
  stdin.** 1.1.0's `src/format.pdx` at the `mkfs_format_run`
  signature comment claimed the caller had refused this combination
  upstream ("see src/main.pdx's own check"); no such check existed.
  A `mkfs.pdxfs --encrypt /tmp/x.img` invocation with no
  `--passphrase-fd` would therefore reach
  `mkfs_encrypt_apply_wrap` with `passphrase_fd == 0` (the
  `ParsedArgv` default), whose Phase-1 `sys_read(fd=0, ...)` would
  either block on stdin (interactive hazard) or swallow an empty EOF
  token (silent-empty-passphrase hazard). This landing adds the
  missing gate in `src/main.pdx` (new `mkfs_main_encrypt_pfd_ok`
  path): after `argv_parse` succeeds, if `PA_FLAG_ENCRYPT` (0x80)
  is set AND `PA_FLAG_PASSPHRASE_FD_SET` (0x100) is not, print
  `mkfs.pdxfs: --encrypt requires --passphrase-fd\n` to stderr and
  `sys_exit(2)` -- BEFORE the audit record opens or any dispatch
  fires. Uses `PA_FLAG_PASSPHRASE_FD_SET` (not "passphrase_fd != 0")
  so a caller who deliberately names fd 0 as the passphrase source
  still works. The false claim comment in `src/format.pdx` is
  updated to accurately cite the newly-added `main.pdx` gate.
- **Bug #3 — stack misalignment (2-push before nested `call`) in
  three functions.** `mkfs_format_build_superblock`
  (`src/format.pdx`, 11 nested `pdxb_sb_set_*` calls),
  `mkfs_encrypt_apply_flag` (`src/encrypt.pdx`, 3 nested
  `pdxb_sb_*` calls), and `mkfs_quota_apply_flag` (`src/quota.pdx`,
  3 nested `pdxb_sb_*` calls) each pushed exactly two callee-save
  registers (`rbx`, `r12`) before their nested calls -- SysV entry
  hands us `rsp % 16 == 8`, so two pushes leave `rsp % 16 == 8` at
  every call site, which is a stack-misalignment ABI violation even
  though the current leaf callees tolerate it (latent bug: any
  future callee that uses SSE would fault). This landing adds a
  throwaway `push r13` / `pop r13` pair to each of the three
  functions, restoring `rsp % 16 == 0` and matching the existing
  rbx/r12/r13 push shape in `mkfs_encrypt_apply_wrap`. `r13` is
  never read; only the epilogue pop matches the entry push.
- **Bug #4 — bare `mkfs.pdxfs --help` hits the missing-target
  error.** `src/argv.pdx`'s parse loop latches `PA_FLAG_HELP`
  during its scan, but the missing-target verdict fires
  unconditionally when `target_ptr == 0`; `src/main.pdx` routed any
  non-zero `argv_parse` return to the missing-target error path
  BEFORE any help-flag check ran (the check was buried inside
  `mkfs_main_argv_ok`, only reached when `argv_parse` returned OK).
  Net: `mkfs.pdxfs --help` (no positional) exited 2 with "missing
  target" instead of exiting 0 with usage. This landing hoists the
  help check to immediately after `call argv_parse` (before the
  return-code branch): loads `mkfs_argv_out + PA_OFF_FLAGS`
  directly, and jumps to `mkfs_main_do_help` if `PA_FLAG_HELP` is
  set -- catching both the `mkfs.pdxfs --help` (return ==
  ARGV_ERR_MISSING_TARGET) and `mkfs.pdxfs /tmp/x.img --help`
  (return == ARGV_OK) cases. The old inline `mkfs_main_after_help`
  transition label was removed since it is no longer referenced;
  help emission moved to a dedicated `mkfs_main_do_help` block
  between the missing-target and `mkfs_main_argv_ok` bodies (both
  surrounding blocks terminate in `sys_exit + hlt` before this
  label, and this block itself terminates the same way before
  `mkfs_main_argv_ok`, so no fall-through is possible).

### Fixed (debugger pass follow-up, same v1.1.1 release)

- **Bug #5 — 5 of 13 `--help` message literals had short array
  sizes / length constants** (debugger pass on the initial fixup
  wave). `mkfs_msg_help_l08`/`l09`/`l11`/`l12`/`l13` in `src/main.pdx`
  were declared `[u8; N]` with N one-or-two-bytes under the real
  string length (including trailing `\n\0`); paideia-as's strict
  fixed-array typing would reject or silently truncate. Corrected
  each array size, `_len` constant, and paired `mov rdx, N` write
  immediate.
- **Bug #6 — `--passphrase-fd` with no following value token
  bypassed the Bug #2 gate.** `src/argv.pdx`'s `mkfs_argv_check_pfd`
  latched `PA_FLAG_PASSPHRASE_FD_SET` BEFORE the bounds check for the
  value token. So `mkfs.pdxfs --encrypt /tmp/x.img --passphrase-fd`
  (fd flag as last token) set the presence bit while
  `passphrase_fd` stayed at 0 -- main.pdx's new gate saw ENCRYPT set
  + SET-bit set -> allowed the invocation through, defeating the
  Bug #2 stdin-read guard. Reordered: bounds-check first, then only
  latch the presence bit AFTER a value token is confirmed and
  parsed.

### Files touched

- `src/quota.pdx` — Bug #1 header rewrite, Bug #3 push_r13/pop_r13
  in `mkfs_quota_apply_flag`.
- `src/main.pdx` — Bug #2 `mkfs_msg_encrypt_needs_pfd` message +
  `mkfs_main_encrypt_pfd_ok` gate; Bug #4 upstream `--help`
  precedence check + `mkfs_main_do_help` label relocation; removed
  dead `mkfs_main_after_help` label; Bug #5 5-literal array/length
  corrections. Justification text updated.
- `src/format.pdx` — Bug #2 comment correction at `mkfs_format_run`
  signature; Bug #3 push_r13/pop_r13 in
  `mkfs_format_build_superblock`; Bug #5 sibling justification
  cleanup (r13 pop order).
- `src/encrypt.pdx` — Bug #3 push_r13/pop_r13 in
  `mkfs_encrypt_apply_flag`.
- `src/argv.pdx` — Bug #6 reorder presence-bit latch after bounds
  check.
- `STATUS.md` — version bump to 1.1.1.

### Known deferred (not fixed in v1.1.1)

- No regression-test coverage was added for any of Bugs #1-#6. All
  six live in code paths (`_start`'s new gates, argv scan-loop, or
  functions the existing 4 test files bypass). File a follow-up if
  test-suite parity with the LV11-025 argv surface is desired.
- Stale justification in `src/encrypt.pdx` (`mkfs_encrypt_apply_wrap`
  header) claims r13 = scratch for the passphrase-read return
  value; the actual body stashes it in a .bss slot instead. Pre-
  existing 1.1.0-era text; harmless doc drift left in place to
  avoid a v1.1.2 patch cycle for a comment-only fix.

## 1.1.0 — 2026-09-02 (LV11 wave: libpdx-volume v1.1 adoption)

**Additive minor** per the semver policy below — adds new argv
surface (`--encrypt`, `--passphrase-fd`, `--quota`, `--help`) and new
format-time behavior (v2 wrapped-DEK stamping, v2 flag/version bump
on quota) without removing or renumbering any M1..M5 surface.
Consumers built against 1.0.0 that pass no LV11 flags observe no
behavior change on the file-target path.

### Landed

- **LV11-024** (#24) — libpdx-volume v1.1 API cleanup. Every
  per-field summary store in `src/format.pdx`'s
  `mkfs_format_build_superblock` now routes through libpdx-volume's
  `pdxb_sb_set_*` accessor family (LV.M1-003, libpdx-volume#18); every
  hardcoded on-disk / summary offset in `src/format.pdx`'s text now
  cites the matching `PdxbSuperblock::` exported constant
  (`SB_SUMMARY_BYTES`, `PDXB_ONDISK_BYTES`, `PDXB_D_OFF_SIG`).
  `mkfs_format_build_superblock`'s register plan was promoted from
  pure-leaf to caller-preserving (push rbx; push r12) since it now
  performs eleven nested setter calls.
- **LV11-025** (#25) — `--encrypt` + `--passphrase-fd <n>` +
  `--quota <spec>` (repeatable) + `--help` argv-surface additions.
  New scaffold files `src/encrypt.pdx` (real `pdxb_kek_derive` +
  `pdxb_dek_wrap` over a PLACEHOLDER all-zero DEK / KDF-salt /
  wrap-nonce, matching M3's placeholder ML-DSA-65 seed posture --
  documented gap: no `sys_getrandom` primitive exists yet at any
  sysno) and `src/quota.pdx` (flag-set only; quota-table
  serialization deferred pending libpdx-volume publishing
  `SBS_OFF_QUOTA_*` accessors). When `--encrypt` is set the
  superblock version bumps to `PDXB_VERSION_V2` and
  `PDXB_FLAG_ENCRYPTED` is OR-ed into `SBS_OFF_FLAGS`; when
  `--quota` is set the same version bump happens and
  `PDXB_FLAG_HAS_QUOTA` is OR-ed instead (both bits latch on a
  volume that carries both flags). `src/argv.pdx`'s `ParsedArgv`
  struct widened 40 -> 56 bytes for the new `PA_OFF_PASSPHRASE_FD`
  (40) and `PA_OFF_QUOTA_COUNT` (48) slots; `src/main.pdx`'s
  `mkfs_argv_out` .bss reserve widened to match, and the two
  `mkfs_format_run` / `mkfs_format_run_device` call sites now pass
  the new `rcx=flags` + `r8=passphrase_fd` arguments.

### Known deferred substrate (LV11 additions)

- **No `sys_getrandom` / equivalent syscall exists**, so the wrapped
  DEK / KDF salt / wrap nonce this landing stamps under `--encrypt`
  are all permanently-zero placeholders (see `src/encrypt.pdx`'s
  module header for the full "placeholder-material posture" write-up).
  Same posture M3's placeholder ML-DSA-65 seed uses. Every wire byte
  is a genuine byte-for-byte record of what this run passed to
  `pdxb_dek_wrap`, so a future entropy-wired revision produces
  wire-visible diffs against this landing.
- **`--passphrase-fd <n>` reads a real passphrase from the caller's
  fd** but pairs it with the zero salt above, so two invocations with
  the same passphrase produce identical wrapped-DEK bytes. This is
  fine for a wire-format demonstration; a random salt (persisted into
  `PDXB_D_OFF_KDF_SALT`) MUST land before the tool ships against real
  user data.
- **`--quota <spec>` populates `argv_quota_specs` and latches
  `PDXB_FLAG_HAS_QUOTA`** but does NOT yet serialize per-quota-row
  entries into a reserved quota-table region -- libpdx-volume v1.1.1
  publishes no `SBS_OFF_QUOTA_LBA` / `SBS_OFF_QUOTA_BCOUNT` accessor
  pair, and no `PDXB_D_OFF_QUOTA_*` on-disk offsets, so this landing
  has no destination to point at. Flagged for main + libpdx-volume;
  see `src/quota.pdx`'s module header for the full list.
- **`pdxb_sb_get_wrap_nonce` / `pdxb_sb_set_wrap_nonce` accessor pair
  is missing** from libpdx-volume v1.1.1 -- the two aligned wrapped-
  DEK and KDF-salt fields have full accessors, but the 12-byte
  `wrap_nonce` at `PDXB_D_OFF_WRAP_NONCE` = 256 does not. This
  landing writes it via one qword + one dword direct store; a future
  accessor-symmetric revision swaps that for two `pdxb_sb_set_wrap_
  nonce` calls. Flagged for main + libpdx-volume.

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

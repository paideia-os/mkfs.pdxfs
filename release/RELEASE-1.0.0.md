# mkfs.pdxfs v1.0.0 — release note + mirror-push workflow (M5)

**Repo:** github.com/paideia-os/mkfs.pdxfs
**Wave:** R53 tool (design/tooling/volume-tooling-ux.md §2.1 + §3 + §9.1)
**Version at first release:** 1.0.0
**Upstream policy:** `design/tooling/plan.md` §6.3 (paideia-os) —
package repository layout; `design/02-development-environment.md`
§1140 + §1164 (paideia-os) — hybrid Ed25519+ML-DSA-65 signing,
release-line key custody; `design/tooling/volume-tooling-ux.md` §9.1
(paideia-os) — M5 scope (issues #17, #18).

This document is both the **release note** for what v1.0.0 ships and
the operator runbook for cutting the signed release and pushing it to
the paideia-os package mirror at
`https://pkgs.paideia-os/main/mkfs.pdxfs/1.0.0/`. The workflow mirrors
`libpdx-volume`'s own `release/RELEASE-1.0.0.md` (this org's other
R53-wave satellite repo, first through M5) — see that file for the
worked template this one follows, and see §5 below for the one
structural difference: mkfs.pdxfs is a **runnable CLI tool**, not a
library, so its mirror layout carries a `/bin/` entry libpdx-volume's
own layout has none of.

The actual `git tag v1.0.0` + `git push` is a **manual step main
performs separately from this milestone** — see §6. This document
describes exactly what that tag would contain so a future operator (or
main, later) can cut it without re-deriving scope from STATUS.md and
five milestones of design-doc flags.

---

## 1. What v1.0.0 ships

Everything landed at M1..M5 (see `CHANGELOG.md` for the itemised list,
`STATUS.md` for the per-issue checklist):

- **The full argv surface** (`Argv::argv_parse`) — `--force`,
  `--label=`, `--journal-size=`, `--dry-run`, `--verbose`, `--sig-key=`,
  `--upgrade` (M4-004, stub-wired), `<target>`.
- **`Target::target_classify` / `mkfs_dev_parse_slot`** — the real
  three-way target-taxonomy classifier plus a real hex device-cap-slot
  parser.
- **`Format::mkfs_format_run`** — the real file-target write pipeline:
  superblock encode + ML-DSA-65 sign (real intrinsic call, placeholder
  all-zero seed — see §2) + write, zeroed inode table with a real root
  inode at slot 1, zeroed allocator bitmap, zeroed journal ring.
- **`Refusal::mkfs_refuse_check`** — the non-blank-target refusal gate
  (`PDXB`/`PDXL`/other-non-blank/blank), bypassable only by `--force`.
- **`Format::mkfs_format_run_device`** — a documented STUB for
  device-cap targets (parses the slot for real, emits
  `DEVICE_TARGET_STUB`, performs no write — no block-granularity write
  syscall exists in this kernel).
- **`ElevateWire::mkfs_elev_require_device_write`** — a documented
  fail-closed STUB (always DENY — this repo holds no
  `KIND_ELEVATE_CHANNEL` broker-endpoint cap).
- **`AuditWire::mkfs_audit_begin`/`mkfs_audit_commit`** — real
  `libpdx-audit` calls wrapping every `_start` dispatch branch (the
  daemon-side dispatch is itself confirmed stubbed).
- **`PipeWire::mkfs_sp_emit_dry_run`/`mkfs_sp_emit_result`** — the
  semantic-pipe-shaped emission wrappers, currently falling back to a
  documented line-based `sys_write` rendering (`libpdx-semantic-pipe`'s
  schema-registry dependency is inert, paideia-os#2000).
- **`Upgrade::mkfs_upgrade_run`** (M4-004, new) — a documented STUB for
  a future PDXL->PDXB `--upgrade` rewrite.
- **Four test drivers** (`tests/test_file_target_happy.pdx`,
  `tests/test_refusal_matrix.pdx`, `tests/test_device_target_smoke.pdx`,
  `tests/test_upgrade_stub.pdx`) exercising every real (non-stub) body
  above plus both documented stubs' own sentinel contracts.
- **`doc/mkfs.pdxfs.pdxdoc`** — the source-form user-facing
  documentation this milestone adds.

## 2. What v1.0.0 explicitly does NOT ship (deferred)

Consumers relying on this tool at v1.0.0 must know these gaps are real
and by design, not oversights:

- **Device-target writes are fully stubbed.** No `sys_cap_query`-
  equivalent primitive exists to validate a `cap:blkdev:` slot's kind,
  and no block-granularity write syscall exists at any sysno
  (`design/architecture.md` §11.1). A `cap:blkdev:` target always
  produces `ELEVATION_DENIED` before ever reaching the write-stub arm,
  since `libpdx-elevate` cannot be called for real either (§11.5).
- **Superblock signatures use a placeholder all-zero seed.** Every
  signature this tool produces is well-formed (a real ML-DSA-65
  intrinsic call, over the correct 696-byte message) but verifies
  against no real key — a `libpdx-key`-equivalent seed-loading library
  does not exist anywhere in `paideia-satellites/` yet
  (`design/architecture.md` §11.2).
- **`libpdx-semantic-pipe` is not linked.** Every `PdxFsFormatRecord@0.1`
  this tool emits stays the M1/M2 line-based `sys_write(1, ...)`
  rendering, preceded by a documented deferral header, until
  `svc.schema-registry` lands (paideia-os#2000) and
  `Registry::bind_by_name` stops being inert (`design/architecture.md`
  §11.3).
- **No retain-forever audit `UEJ_KIND`.** `libpdx-audit`@0.2 has no
  caller-selectable audit-record kind at all; if volume-formatting
  operations need retain-forever semantics, that is a `libpdx-audit`
  feature request (`design/architecture.md` §11.4).
- **`--upgrade` is a stub.** The flag parses into `PA_FLAG_UPGRADE`
  and a callable `mkfs_upgrade_run` exists, but `src/main.pdx`'s
  dispatch does not branch on it — no PDXL on-disk decoder exists
  anywhere in `libpdx-volume` to rewrite from (`src/upgrade.pdx`'s own
  module header).
- **No `--size=`-equivalent flag / real data-region sizing.** Every
  volume this tool formats has `data_lba`/`data_bcount` = 0
  (`design/architecture.md` §9.1, still open per §11.6).
- **Device-target smoke coverage is a sentinel check, not a real
  write-then-readback round trip** — see `tests/
  test_device_target_smoke.pdx`'s own header for the three-item
  substrate chain this needs first.
- **Dual-signed `manifest.pdxsig` + mirror push** — see §3/§4 below;
  this is the one item this milestone (M5) lands the *source form* of
  but does not execute.

## 3. Substrate readiness (blocking the actual signed release)

**S1 — paideia-as toolchain ≥ 0.24.0-mldsa65-sign reachable.** The
release build invokes `paideia-as build` to compile `src/*.pdx` and
`tests/*.pdx`, and `paideia-pq-sign::sign_release_artifact` for the
dual-signature step. `MlDsa65::sign` (the intrinsic
`pdxb_sign_superblock` calls, transitively, via `libpdx-volume`)
already ships at v0.24.0.

**S2 — `pkgs.paideia-os` mirror endpoint reachable.** Same mirror,
same non-existent-as-of-R53-close status `libpdx-volume`'s and
`libpdx-audit`'s own runbooks document. Until it stands, the release is
"cut but not mirrored" — the signed `manifest.pdxsig` still lands in
the GitHub release attachment set for out-of-band consumers.

**S3 — a live ML-DSA-65 release-line seed key.** `manifest.pdxsig` is
left with the `SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN` sentinel in
every signature slot precisely because that key material is
release-line custody (hardware-backed TPM 2.0 / cloud KMS per
`design/02-development-environment.md` §1164), never repo-resident —
the SAME discipline `src/format.pdx`'s own `mkfs_sign_seed_zero`
placeholder documents one layer down, for the superblocks this tool
itself signs.

**S4 — `doc` M2 reachable.** The compiled `.pdxdoc` at
`/pkgs/mkfs.pdxfs-1.0.0/doc/mkfs.pdxfs.pdxdoc` is produced by the `doc
compile` subcommand of the `doc` tool at doc.M2 (not landed as of this
milestone). The source form at `doc/mkfs.pdxfs.pdxdoc` in this repo is
the input; consumers render it verbatim until then.

**S5 — link step.** Unlike `libpdx-volume`/`libpdx-audit` (also
libraries at this stage), mkfs.pdxfs is meant to ship as a runnable
`/bin/mkfs.pdxfs` ELF — `tools/build.sh` compiles every `src/*.pdx`
into an independent `.o` with **no link step** (this repo's own
README.md and every module header's "cross-repo call" note flag this
explicitly). Producing the actual runnable binary needs a link pass
against `libpdx-volume`'s and `libpdx-audit`'s own compiled objects,
which is itself outside `tools/build.sh`'s documented scope and outside
this milestone.

---

## 4. Cut-a-release procedure

Identical shape to `libpdx-volume`'s and `libpdx-audit`'s own runbooks
(same tooling, same release-line key custody). Reproduced here with
this repo's own artifact names.

**Pre-flight.**

    git fetch origin
    git switch main
    git pull --ff-only
    git status                    # MUST be clean
    gh issue list --milestone M5 --state open --repo paideia-os/mkfs.pdxfs
                                  # MUST be empty

**Step 1 — Version bump + CHANGELOG close.** Already done at M5 —
`CHANGELOG.md`'s `## 1.0.0` entry is the one a future tag points at.

**Step 2 — Tag.** (Manual, main-performed — see §6; NOT run as part of
this milestone.)

    git tag -a v1.0.0 -m "mkfs.pdxfs v1.0.0 — R53 M1..M5 close"
    git push origin v1.0.0

**Step 3 — Build + link the compiled artifact set.**

    paideia-as build src/main.pdx           -o build/main.o
    paideia-as build src/argv.pdx           -o build/argv.o
    paideia-as build src/target.pdx         -o build/target.o
    paideia-as build src/format.pdx         -o build/format.o
    paideia-as build src/format_record.pdx  -o build/format_record.o
    paideia-as build src/refusal.pdx        -o build/refusal.o
    paideia-as build src/pipe_wire.pdx      -o build/pipe_wire.o
    paideia-as build src/audit_wire.pdx     -o build/audit_wire.o
    paideia-as build src/elevate_wire.pdx   -o build/elevate_wire.o
    paideia-as build src/upgrade.pdx        -o build/upgrade.o
    paideia-as link  build/*.o \
        --with libpdx-volume.so --with libpdx-audit.so \
        -o build/mkfs.pdxfs
    doc compile        doc/mkfs.pdxfs.pdxdoc -o build/mkfs.pdxfs.pdxdoc

**Step 4 — Recompute the manifest.**

    paideia-release fill-manifest \
        --source release/manifest.pdxsig.txt \
        --tree   . \
        --tag    v1.0.0 \
        --output build/manifest.pdxsig.filled.txt

**Step 5 — Dual-sign.**

    paideia-release sign \
        --manifest build/manifest.pdxsig.filled.txt \
        --key-ed25519  release-line-ed25519.sk \
        --key-ml-dsa65 release-line-ml-dsa-65.sk \
        --output   build/manifest.pdxsig

**Step 6 — Mirror push.** This is the part issue #18 scopes as
"document what would be pushed", NOT "actually push" — see §5 for the
full expected layout and the explicit out-of-scope note.

    paideia-release mirror-push \
        --repo   https://pkgs.paideia-os/main/ \
        --pkg    mkfs.pdxfs \
        --version 1.0.0 \
        --files  build/mkfs.pdxfs \
                 build/mkfs.pdxfs.pdxdoc \
                 caps.decl \
                 build/manifest.pdxsig

**Step 7 — Update `index.pdxsig`.** Atomic as part of Step 6, per
`libpdx-volume`'s and `libpdx-audit`'s own runbooks.

**Step 8 — GitHub release.**

    gh release create v1.0.0 \
        --title "mkfs.pdxfs v1.0.0" \
        --notes-file CHANGELOG.md \
        build/manifest.pdxsig \
        build/mkfs.pdxfs \
        build/mkfs.pdxfs.pdxdoc \
        caps.decl

---

## 5. Distribution — what would be pushed to `pkgs.paideia-os` (#18)

**Scope note:** this section documents the mirror-push target layout
and contents for a future operator to execute against a real
`pkgs.paideia-os` endpoint (S2 above — does not exist yet). Per issue
#18's own instruction, **no actual push happens as part of this
milestone, and no `pkgs.paideia-os` artifacts are created by this
landing** — main handles the real push once S1..S5 above are green.

Expected mirror layout after a real Step 6 push:

    /pkgs/mkfs.pdxfs-1.0.0/
        bin/mkfs.pdxfs              # the linked, runnable ELF (Step 3)
        doc/mkfs.pdxfs.pdxdoc       # compiled .pdxdoc (Step 3)
        caps.decl                  # this repo's capability declaration
        manifest.pdxsig            # dual-signed binary manifest (Step 5)
    /bin/mkfs.pdxfs -> /pkgs/mkfs.pdxfs-1.0.0/bin/mkfs.pdxfs
                                    # the package tool's own symlink
                                    # convention for a runnable CLI
                                    # package's PATH entry -- THIS is
                                    # the one structural difference from
                                    # libpdx-volume's own mirror layout
                                    # ("no /bin/ entry -- a library, not
                                    # a tool", that repo's own §5)

`[depends-on]` in `manifest.pdxsig.txt` (§ above) declares this
package's own two real cross-repo links (`libpdx-volume >= 1.0.0`,
`libpdx-audit >= 0.2.0`) — the consumer-side `pkg install mkfs.pdxfs`
tool resolves and verifies both are already installed (or installs
them transitively) before accepting this package, per
`design/tooling/plan.md` §6.3's dependency-resolution contract. The
`[not-linked]` section documents, for the record, that
`libpdx-semantic-pipe` and `libpdx-elevate` are named in `caps.decl`
but never actually called by any function in this repo at v1.0.0 — a
consumer-side installer should NOT treat either as a hard dependency.

## 6. Verification (consumer side)

    pkg install mkfs.pdxfs --verify-only     # dry run, no install
    pkg keys show paideia-release-line        # inspect the signer

AND-semantics per the hybrid scheme: both Ed25519 and ML-DSA-65 MUST
verify; either failure REJECTS the package. Not runnable until the
placeholder signature block in `manifest.pdxsig` is replaced by a real
dual-sign pass per §3/§4 above.

---

## 7. What lands at M5 (this milestone)

Repo-side, M5 lands the source form of the release:

- `CHANGELOG.md` — v1.0.0 entry summarising M1..M5.
- `doc/mkfs.pdxfs.pdxdoc` — source-form `.pdxdoc` for `doc mkfs.pdxfs`.
- `release/manifest.pdxsig.txt` — release manifest source form, every
  hash and every signature slot a documented placeholder.
- `release/RELEASE-1.0.0.md` — this document, including the
  distribution section (#18) documenting the future mirror-push target
  without performing it.
- `STATUS.md` — M4 and M5 marked landed, version header bumped to
  v1.0.0.
- `tests/test_file_target_happy.pdx`, `tests/test_refusal_matrix.pdx`,
  `tests/test_device_target_smoke.pdx`, `tests/test_upgrade_stub.pdx`,
  `tests/README.md` — the M4 test suite (#13-#16), landed in the same
  pass as this M5 release scaffold per this task's own combined scope.
- `src/upgrade.pdx` (new) + `src/argv.pdx`/`src/format_record.pdx`
  extensions — the minimal `--upgrade` stub wiring M4-004 (#16) itself
  asked for.

**Not performed at this milestone:** the git tag itself (main's manual
step, once this landing is reviewed), the actual `paideia-as build` +
link compile pass, the dual-sign pass (no live seed key in this repo —
see §3 S3 above), and the mirror push (mirror endpoint does not exist
yet — S2 above, and out of scope per issue #18 regardless).

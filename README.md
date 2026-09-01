# mkfs.pdxfs

paideia-os PdxFS-on-block volume formatter — writes a fresh PDXB
superblock + empty WAL journal ring + zeroed allocator bitmap + a single
root-inode entry onto a filesystem-path image or a `KIND_BLOCK_DEVICE`
cap URI.

## Purpose

`mkfs.pdxfs` is the second of three actions that bring a blank disk (or
image file) online for PdxFS v1: **format** (this tool), then **mount**
(`mount.pdxfs`), with `umount.pdxfs` as the reversal. It is invoked as:

```
mkfs.pdxfs [--force] [--label=<str>] [--journal-size=<n_blocks>]
           [--dry-run] [--verbose] [--sig-key=<key-cap-uri>] <target>
```

`<target>` is either a filesystem path (dev workflow, no root, no
signing required) or a `cap:blkdev:` cap URI (production workflow,
elevate-required, signing mandatory). See
[`design/architecture.md`](design/architecture.md) for the full
argv/target-taxonomy write-up and
`design/tooling/volume-tooling-ux.md` §3 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
upstream CLI spec this tool implements.

## Status

**v1.0.0 — M1..M5 landed.** Real file-target write pipeline (superblock
encode + sign + write, zeroed inode table + root inode #1, zeroed
allocator bitmap, zeroed journal ring, non-blank refusal gate),
device-target and `--upgrade` paths as documented stubs, a four-driver
test suite, and a dual-signed-release scaffold. See
[`STATUS.md`](STATUS.md) for the per-issue checklist,
[`CHANGELOG.md`](CHANGELOG.md) for the release note, and
`design/tooling/volume-tooling-ux.md` §9.1 in paideia-os for the full
M1..M5 milestone breakdown (18 issues).

Try it (once built and linked into a runnable image):

```
mkfs.pdxfs --dry-run --label=data --journal-size=2048 /tmp/foo.img
```

prints:

```
PdxFsFormatRecord@0.1 { target: /tmp/foo.img, label: data, journal_size: 2048, dry_run: true }
```

and exits 0 without writing anything. Drop `--dry-run` against the same
file target and it now really formats it:

```
mkfs.pdxfs /tmp/foo.img
```

prints `PdxFsFormatRecord@0.1 { target: /tmp/foo.img, result_code: OK }`
and exits 0, having written a real, ML-DSA-65-signed PDXB v1
superblock (`result_code: SIGNED_OK`), a zeroed inode table (with a
real root-directory inode at slot 1), a zeroed allocator bitmap, and a
zeroed journal ring. Re-running it against the same target without
`--force` refuses (`result_code: REFUSED_ALREADY_PDXB`, exit 5); with
`--force` it rewrites unconditionally. A `cap:blkdev:` target exits 6
(`ELEVATION_DENIED`) — this repo holds no broker-endpoint capability
to prove real elevation with (see `design/architecture.md` §11.5).

## Depends on

- **`libpdx-volume`** (`paideia-os/libpdx-volume`) — M1-M5 landed. This
  repo links its real superblock codec (`pdxb_encode_superblock`) and
  its real signer (`pdxb_sign_superblock`, called on every file-target
  write with a placeholder all-zero seed — see `design/architecture.md`
  §11.2). See `design/architecture.md` §9.6 for the cross-repo call
  mechanism.
- **`libpdx-audit`** (`paideia-os/libpdx-audit`, @0.2) — wraps every
  `_start` dispatch branch in a real (though daemon-side-stubbed)
  audit-journal open/commit pair (`src/audit_wire.pdx`).
- **paideia-as ≥ 0.21.0** (build toolchain; ≥ 0.24.0-mldsa65-sign for
  the signing intrinsic `libpdx-volume` calls transitively).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M1 | Scaffold, caps.decl, argv surface, first runnable `--dry-run` | **Landed** |
| M2 | Real superblock write, non-blank refusal gate, root inode | **Landed** |
| M3 | Device-cap target, signing, semantic-pipe emit, audit, elevate | **Landed** |
| M4 | Tests + smoke | **Landed** |
| M5 | Signed release | **Landed** |

## License

MIT — see [`LICENSE`](LICENSE).

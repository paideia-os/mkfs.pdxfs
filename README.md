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

**M1 landed** (scaffold + caps.decl, argv surface, first runnable
`--dry-run` against a file target). See
[`STATUS.md`](STATUS.md) for the per-issue checklist and
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

and exits 0 without writing anything. Any invocation without
`--dry-run`, or a `--dry-run` against a `cap:blkdev:` target, currently
prints `mkfs.pdxfs: not yet implemented` to stderr and exits 1 — the
real write path (superblock encode + write, device-cap resolution,
signing) lands at M2/M3.

## Depends on

- **`libpdx-volume`** (`paideia-os/libpdx-volume`) — M1 landed. Will
  supply the real superblock codec (`pdxb_encode_superblock`,
  `pdxb_parse_superblock`) and signing helper
  (`pdxb_sign_superblock`) this tool's M2/M3 link against. Not yet
  linked by any M1 code in this repo — see `design/architecture.md` §2
  for the dependency-wiring plan.
- **paideia-as ≥ 0.21.0** (build toolchain).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M1 | Scaffold, caps.decl, argv surface, first runnable `--dry-run` | **Landed** |
| M2 | Real superblock write, non-blank refusal gate, root inode | Pending |
| M3 | Device-cap target, signing, semantic-pipe emit, audit, elevate | Pending |
| M4 | Tests + smoke | Pending |
| M5 | Signed release | Pending |

## License

MIT — see [`LICENSE`](LICENSE).

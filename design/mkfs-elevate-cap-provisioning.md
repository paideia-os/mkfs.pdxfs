# mkfs.pdxfs — KIND_ELEVATE_CHANNEL boot-time cap provisioning (#26 follow-up)

**Status:** proposal, not landed. Written as the companion doc
`src/elevate_wire.pdx`'s wave-o hygiene addendum points to.
**Scope:** paideia-os (init/broker side) + libpdx-elevate (client-side
consumer of the new discovery step). NOT resolvable from the
`mkfs.pdxfs` repo alone — see `src/elevate_wire.pdx`'s own header for
why a satellite-only dispatch stops at documenting the gap.

## 1. The gap, precisely

`design/user/fs-tools-caps.md` §2.1 and this repo's own `caps.decl`
both record, correctly, that `KIND_ELEVATE_CHANNEL` is **deliberately
absent** from `mkfs.pdxfs`'s exec-time capability set: this tool
"elevates on demand," never holding an elevate cap ambiently
(R90-XREPO.011 policy).

That policy is right for a standalone CLI exec'd fresh for one format
operation. But "elevate on demand" presupposes a **demand path** —
some way for a process holding zero elevate-shaped capabilities at
`exec` time to reach the elevate broker anyway. That path does not
exist today:

- `elevate_client_acquire`'s real, landed signature (libpdx-elevate
  ENH-001..003) takes `caps` (an already-resolved parent capability
  slot for the elevate channel), plus a `reply_ep_id` this process
  must already own.
- Nothing at boot mints `mkfs.pdxfs` — or any standalone CLI in the
  same shape (`rm --recursive`'s privileged path, `mount.pdxfs`,
  `umount.pdxfs` all document the identical gap in their own
  `src/elevate.pdx` / `src/mint_wire.pdx`) — a `KIND_ELEVATE_CHANNEL`
  slot to present.
- There is no init-side registry a freshly-exec'd process can query to
  obtain one on demand, either.

So "on-demand elevate" is the documented *policy*, but there is no
*mechanism* underneath it yet. `src/elevate_wire.pdx`'s
`mkfs_elev_require_device_write` therefore has nothing honest to call
and stays at its fail-closed `MKFS_ELEV_DENY` stub.

## 2. What already exists to build on

Two kernel-side primitives, both already landed, get most of the way
there:

1. **Named service discovery without an ambient cap.**
   `src/kernel/core/ipc/svc_broker.pdx`'s `svc_lookup(name_ptr,
   name_len) -> endpoint_id | SVC_LOOKUP_NONE` is declared `@{}` — no
   capability required to call it. A process with zero elevate-shaped
   caps can already ask "what endpoint answers to this well-known
   name" today, via whatever `sys_svc_lookup` wrapper (sysno per
   R20b.M3-004) libpdx-elevate or a future shim exposes.
2. **A cap-mint primitive that already exists on the broker side.**
   `design/security/elevate-broker.md` documents
   `elevate_channel_cap_mint_inner` as the real, landed mint path for
   `KIND_ELEVATE_CHANNEL` rows, exercised end-to-end by the boot
   witness `src/kernel/boot/witness/elevate_broker_dispatch.pdx`. The
   mint primitive is not the gap — *reaching* it from a capability-less
   process is.

Neither of these was designed with "standalone CLI, zero ambient
elevate cap, needs a channel for exactly one bounded request" in mind,
but both compose toward it.

## 3. Proposal: init-side mint pool + discovery hand-off

### 3.1 Boot-time: a bounded, named request-pool

At boot, alongside the existing `KIND_ELEVATE_CHANNEL` broker-endpoint
setup `elevate_broker_dispatch.pdx` already exercises, init additionally:

1. Registers the broker's own request-intake endpoint under a
   well-known service name (e.g. `"elevate.broker"`) via the existing
   `svc_register` primitive — no new kernel primitive needed, this is
   wiring init already has the pieces for.
2. Reserves a small, fixed-size pool of **unbound** `KIND_ELEVATE_CHANNEL`
   *request slots* (distinct from a granted elevate row — these are
   "permission to ask," not "permission granted"). A pool, not a
   per-process static allocation, because standalone CLI tools are
   exec'd transiently and never hold a slot long enough to need a
   dedicated one; a bounded pool (say 8-16 slots, sized like
   `svc_broker`'s existing 32-row table) caps the DoS surface of "spawn
   many mkfs.pdxfs processes to exhaust broker request slots."

### 3.2 Exec-time: nothing changes for the process's caps.decl

This is the point of the design: `mkfs.pdxfs`'s `caps.decl` keeps
`KIND_ELEVATE_CHANNEL` absent, exactly as `fs-tools-caps.md` §2.1
specifies. The pool above is broker/init-side state, not a capability
minted into the exec'ing process's table.

### 3.3 Request-time: the hand-off contract

When `mkfs.pdxfs` actually needs to format a `cap:blkdev:` target
(i.e. exactly the call site `mkfs_elev_require_device_write` already
marks), the sequence is:

1. **Discover.** `sys_svc_lookup("elevate.broker")` -> broker endpoint
   id. Requires no capability (per `svc_lookup`'s `@{}` signature)
   beyond the generic "may call `sys_svc_lookup`" floor every process
   already has.
2. **Mint a local reply endpoint.** The process calls whatever
   generic (non-elevate-shaped) endpoint-mint syscall
   `src/kernel/core/ipc/channel_create.pdx` / `endpoint_table.pdx`
   already expose for a process to obtain an endpoint it owns in
   `[1..127]` — this closes the *other* long-documented gap in
   `src/elevate_wire.pdx` (`reply_ep_id` "STILL UNRESOLVED" in the
   LE-001 addendum) as a side effect, since that gap and this one are
   the same underlying "standalone CLI has no provisioning story" hole.
3. **Request a bounded slot from the pool.** Present
   `(requester_pid, target_cap_kind, target_cap_rights, scope_fp,
   reply_ep_id)` to the broker's request-intake endpoint from step 1.
   The broker validates against the pool's capacity (§3.1) and, on
   success, calls the existing `elevate_channel_cap_mint_inner` to mint
   a **scope-bound, short-lived** `KIND_ELEVATE_CHANNEL` row exactly as
   it does today for processes that already hold one ambiently — the
   mint primitive itself needs no change.
4. **Proceed with the existing, already-specified call sequence.** The
   row_id this hand-off returns is exactly the `caps` input
   `elevate_client_acquire` already expects per the LE-001 addendum in
   `src/elevate_wire.pdx`. Everything downstream of that point (`
   elevate_client_cap_bind_scope`, `elevate_client_require_scoped`)
   is unchanged.

### 3.4 What this does NOT solve

- The link-line exclusion (`paideia-os/tools/build.sh` deliberately
  omits `libpdx-elevate` from `mkfs.pdxfs`'s build) is a separate,
  independent blocker. This proposal makes the *capability* path
  honest; the *build graph* still needs the `tools/build.sh` change
  `src/elevate_wire.pdx`'s LE-001 addendum already describes.
- This is a design sketch, not a kernel patch. It needs osarch
  review before any kernel-side primitive (the request-intake
  registration, the pool bookkeeping, the request-validation gate) is
  implemented — none of that is mkfs.pdxfs-repo-scoped work.

## 4. Why a pool, not a per-tool static grant

An earlier-considered alternative — mint each standalone CLI tool a
permanent, ambient `KIND_ELEVATE_CHANNEL` cap at exec time via
`caps.decl` — is exactly the policy `fs-tools-caps.md` §2.1 already
rejected for good reason: it would mean every `mkfs.pdxfs` invocation
carries elevate authority whether or not it ever touches a
`cap:blkdev:` target, widening the ambient authority surface for a
capability this tool needs in maybe 10% of invocations (dev-path
targets never need it at all). The discovery+pool hand-off keeps the
authority-on-demand property `fs-tools-caps.md` wants while finally
giving "on demand" an actual mechanism.

## 5. Open questions for osarch

- Exact syscall numbering / shim for the generic reply-endpoint mint
  used in step 2 above, if one does not already exist under a
  different name.
- Pool sizing and starvation/backpressure behavior when all slots are
  in use (return a distinct error the caller can retry-with-backoff
  on, per this org's general "distinct error code over silent stall"
  convention — see `src/refusal.pdx`'s own precedent in this repo).
- Whether request-intake validation (step 3) belongs in the existing
  `svc_broker.pdx` table or as a new, elevate-specific intake
  structure — the former reuses proven code, the latter keeps
  elevate's request-admission policy (rate limits, kind/rights
  allowlisting) out of the general-purpose service broker.

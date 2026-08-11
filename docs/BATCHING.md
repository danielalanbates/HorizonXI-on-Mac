# Draw-call batching — the route to 30 fps, measured

## The result

Instrumented DXVK's D3D9 draw entry points to group every draw in a frame by its state
signature (vertex shader, pixel shader, vertex declaration, textures 0 and 1). Run with
`DXVK_BATCH_PROBE=1`; output goes to `/tmp/dxvk-batch-probe.log`. Raw log: `docs/batch-probe.log`.

Crowded hub, steady state:

```
frame 4140 draws 1892 stategroups 61 texgroups 55  merge_ratio 31.0x
frame 4170 draws 1895 stategroups 63 texgroups 56  merge_ratio 30.1x
frame 4200 draws 1892 stategroups 61 texgroups 55  merge_ratio 31.0x
```

Character-select scene:

```
frame 60   draws  379 stategroups 10 texgroups 10  merge_ratio 37.9x
```

**1,892 draw calls collapse into 61 distinct state groups. Only 55 distinct textures are in
play across the entire frame.** The ratio is stable at ~30–38× across scenes.

## Why this matters

The stack is bound by draw submission, not by the GPU — measured at 9–11% GPU utilisation
against 0% CPU idle, sustaining roughly 11,000–29,000 draw calls per second (see
`PHASE2-PACKAGING.md`).

At 30× merging, a 1,892-draw frame becomes ~61 submitted draws. That is far below the
~400–650 draws/frame that 30 fps requires at the current ceiling — it would move the
bottleneck off draw submission entirely and onto the GPU, which is currently 90% idle.

This is the single highest-value change available, and it is worth more than every renderer
and setting change tried so far combined.

## Where it goes, and what it does NOT touch

Entirely inside our `d3d9.dll`. Specifically DXVK's D3D9 frontend.

- **No private-server changes.** Servers send game state, not draw calls. HorizonXI, Eden and
  any other server benefit identically with zero per-server work.
- **No FFXI client changes.** We sit below the client, at the D3D9 boundary.
- **No per-server maintenance.** One DLL, all servers.

## The hard part, stated honestly

FFXI is fixed-function and sets a **world matrix per object as device state**, not as
per-vertex or per-instance data. Two draws of two different trees share shaders and texture
but differ in that transform, so they cannot be concatenated as-is.

Making them mergeable means promoting the fixed-function transform out of device state and
into per-instance data:

1. Extend the FF vertex shader generated in `d3d9_fixed_function.cpp` to read the world
   (and world-view-projection) matrix from a per-instance buffer indexed by
   `gl_InstanceIndex`, instead of from the render-state block.
2. In the draw path, accumulate consecutive draws that share the state signature, appending
   each draw's transform (and any other per-object FF state: texture-stage constants,
   material, alpha ref) into that buffer.
3. Flush the accumulated batch as one instanced draw when the signature changes, the buffer
   fills, or the frame ends.

Correctness constraints that must be respected, or the picture breaks:

- **Alpha-blended draws are order-dependent.** Only merge within a run that does not cross a
  blended draw, or restrict merging to opaque passes.
- Any state not folded into per-instance data must be identical across the batch — that is
  what the signature is for; it should be widened to cover every FF state the shader reads.
- Draws using `DrawPrimitiveUP` supply inline vertex data and need their own handling.

## Suggested order

1. Widen the probe signature to include the full FF state the shader consumes, and re-measure.
   If the ratio holds near 30×, the headroom is real rather than an artefact of a too-narrow
   signature. **Do this first — it is cheap and it protects against building on a wrong number.**
2. Implement instancing for opaque, non-blended FF draws only. Measure.
3. Extend to blended draws within safe runs if step 2 pays.

## Reproducing

```sh
DXVK_BATCH_PROBE=1   # plus the usual MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1
tail -f /tmp/dxvk-batch-probe.log
```

The probe writes every 30th frame and costs two set insertions per draw, so leave it off for
real frame-rate measurements.

## Note on the patch file

`patches/dxvk-1.10.3-metal-features-and-fog-probes.patch` is a **superset**: it already
contains the GCC 14 `<cstdint>` header fixes. Apply it alone to a clean `v1.10.3` checkout —
applying `dxvk-1.10.3-build-gcc14.patch` first will conflict.

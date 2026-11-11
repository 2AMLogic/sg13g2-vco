# DR-008: State the output-interface swing and load against a downstream clock need

- **Status**: **proposed** -- a statement of the interface and of the gap. It
  is not binding on design work, and **no ratified bound is changed by it**:
  no cell of row 7 (or any other row) of `spec/target-spec.md` is edited.
- **Date**: 2026-11-10
- **Decided by**: Builder agent, issue #319 (statement only; any change to the
  row-7 floor is a PO-level decision, see "Alternatives considered")
- **Supersedes**: none. It adds an interface statement beside row 7, which
  DR-004 ratified, and changes none of it.

## Context

A downstream 10 Gb/s half-rate SerDes TX mux needs its 5.0 GHz clock at
**>= 0.4 V per side (0.8 Vpp differential, antiphase), centred near 0.6 V**,
into a self-biased (AC-coupled) squarer load. The consumer calls this a lower
bound: in its own PVT sweep the mux output was not switched at the slow corner
(ss, 1.08 V) with 0.4 V per side, so the real need is higher. Source:
sg13g2-serdes `spec/decisions/DR-009-mux-clock-swing.md` and
`spec/clock-requirement.md` (Level / load row). Both are cited from the issue
and **not re-verified from this repo**.

`spec/target-spec.md` row 7 (ratified by DR-004) grades swing only as
`Vpp_diff` at the tank nodes. It gives no per-node figure and no
common-mode statement, and it does not compare itself to this need.

## Decision

State the interface and the comparison; ratify nothing new.

1. `spec/target-spec.md` gains an "Output interface statement" paragraph
   (immediately after the summary table) giving per-node vs differential
   swing, the load, the common mode, and the comparison to the downstream
   0.8 Vpp_diff need.
2. **Verdict: not met by the ratified floor; met at nominal by pilot data;
   ungraded over corners.**
   - Ratified row-7 floor is 0.40 Vpp_diff (0.65 stretch), i.e. **half** of
     the 0.8 Vpp_diff need. Row 7's own arithmetic gives 0.492 Vpp_diff at the
     row-5 Q floor of 6 (`(4/pi) * I_tail * R_p,diff`, `I_tail` = 204.1 uA),
     which is still ~0.31 V short of 0.8.
   - The pilot measured 0.808 / 1.098 Vpp_diff at the band edges (nominal,
     current-limited; row 7) and +/-0.275 V per node (1.10 Vpp_diff) at one
     operating point (`design/README.md`). That clears 0.8 Vpp_diff at
     nominal with <= ~1 % margin at the low edge. These are pilot numbers and
     grade no row.
   - No committed record grades 0.8 Vpp_diff over the row-10 corner set. The
     consumer's slow-corner remark implies the need is higher than 0.8.
3. **No ratified bound changes.** Row 7's floor and stretch stay 0.40 / 0.65
   Vpp_diff. The downstream figure is **not** adopted into row 7 now.

## Alternatives considered

- **Raise row 7 to 0.8 Vpp_diff now** -- not chosen. It lifts the floor above
  the current-limited arithmetic, so it pulls on tail current (row 8 power) and
  on pad capacitance (rows 1 and 2). It needs its own ratification and an
  over-corner basis. If wanted, it goes to the operator as a decision.
- **Add an output buffer** -- not chosen. Row 7 states that a buffer
  re-grades rows 1 and 2 and supersedes row 7.
- **Leave the interface unstated** -- not chosen. The consumer cannot tell
  whether the block meets its need, which is the gap the issue reports.

## Consequences

- The downstream consumer gets a stated swing, load and common mode, and a
  clear "not met by the floor" verdict, instead of inferring from tank-node
  numbers.
- `spec/target-spec.md` changes only by an added paragraph, so the row-7
  extractor in `.github/scripts/check-grader-spec-agreement.py` is unaffected.
- Open, not done here: corner evidence for 0.8 Vpp_diff (a separate sim issue
  if wanted); whether the consumer's AC-coupling capacitor plus squarer input
  loads the tank nodes, and by how much (row 7: ~2.1 fF, 3 % of `C_tot`, moves
  f0 by 1.5 %, which consumes row 1's margin); the common-mode trace over
  corners.
- Bad consequence: the spec now documents a known shortfall against a real
  consumer without closing it. That is intended; closing it is a PO call.

* ref-network.inc -- the ONE definition of the ideal-RLC reference network
* that every known-answer extraction check in this repo simulates alongside
* its devices under test (issue #66; the extraction this guards is
* sim/tank-characterization's and sim/varactor-characterization's C/Q/SRF
* arithmetic). Expanded into netlists by the run scripts -- see EXPANSION
* below -- and parsed back out of the generated netlist by sim/lib.sh's
* method_check_point().
*
* ANATOMY
* -------
* Lref/Rref/Cref is not a PDK device. It is an ideal series-RL shunted by an
* ideal C whose Leff, Q and SRF are known in closed form, so the same
* .control arithmetic that reports the DUT numbers can be checked against
* algebra rather than against itself. With R=2 ohm, L=1 nH, C=100 fF
* (full derivation in tb_mimcap_zscan.spice.tmpl's header):
*
*   Zref(w) = (R + jwL) / ((1 - w^2 LC) + jw R C)
*   Leff(w) = Im(Zref)/w ;  Q(w) = Im(Zref)/Re(Zref)
*   SRF     = sqrt((L - R^2 C) / (L^2 C)) / (2*pi)
*
* COUPLING CONTRACT -- why this file exists
* -----------------------------------------
* sim/lib.sh's method_check_point() does NOT restate R/L/C as constants. It
* parses this network's device cards out of the GENERATED NETLIST (the cards
* below, post-expansion) and derives the closed form from them at run time.
* Change a value here and every corner's known-answer check re-derives
* automatically; a netlist whose reference network is missing or malformed
* fails every row loudly. The failure this forecloses is the silent one: a
* green-looking check comparing a correct simulation against the closed form
* of values the netlist no longer contains.
*
* The network is corner-, temperature- and bias-independent by construction,
* and is inductive below its SRF, so its Im(Z) crosses zero DOWNWARD -- hence
* srf_ref is measured with FALL=1 while every DUT SRF meas uses RISE=1.
*
* EXPANSION
* ---------
* Not a literal ngspice .include: two of the three sections live INSIDE the
* .control block, and ngspice has no .include for .control bodies. Each run
* script materializes the sections into its scratch WORKDIR once per run via
* ref_network_section() (sim/lib.sh) and injects them into the expanded
* netlist with sed's `r` command at the template placeholders:
*
*   cards -> @@REF_NET_CARDS@@   four netlist device cards (pre-.control)
*   lets  -> @@REF_NET_LETS@@    three pass-1 vector derivations (in .control)
*   meas  -> @@REF_NET_MEAS@@    three reference .meas cards (pass 1, in
*                                .control, after the DUT scalar meas)
*
* The pass-2 `let l_ref`/`let q_ref` curve lines deliberately stay in each
* template: they must re-run after pass 2's own `ac` line and feed a
* template-specific wrdata vector list, so they are not part of the shared
* block. The sections below carry no comment lines, so an expanded netlist
* differs from its pre-fragment predecessor only by the documented
* srf_ref relocation (issue #66's verification step).
*
* @@ref-network:cards@@
Iref 0 ref dc 0 ac 1
Lref ref refn 1n
Rref refn 0 2
Cref ref 0 100f
* @@ref-network:lets@@
let zref = imag(v(ref))
let lref = imag(v(ref))/wrad
let qref = imag(v(ref))/real(v(ref))
* @@ref-network:meas@@
meas ac srf_ref WHEN zref=0 FALL=1
meas ac l_ref_1g   FIND lref AT=1e9
meas ac q_ref_1g   FIND qref AT=1e9
* @@ref-network:end@@

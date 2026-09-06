# closed_form_z.awk -- independent closed-form reference for the analytic
# SG13G2 spiral-inductor model.
#
# This is the KNOWN ANSWER that run_model_check.sh holds the SPICE netlist in
# sg13g2_inductor_analytic.spice to. It re-derives the driving-point impedance
# of that model's 2-pi topology from the same geometry and the same PDK
# constants, but NOT from the same code path: the netlist builds the series
# branch as a ten-section R||L ladder (a truncation of the partial-fraction
# expansion of xi*coth(xi)); this file evaluates xi*coth(xi) directly in
# complex arithmetic. Agreement to the run's tolerance therefore demonstrates
# both that the netlist implements the intended algebra and that the ladder
# truncation is negligible in the checked band -- which is the only thing a
# known-answer check can demonstrate. Whether the MODEL is right is a
# different question; see README.md.
#
# Same convention as sim/tank-characterization's reference network: the
# reference is re-evaluated at every corner, because the point is to catch a
# run whose arithmetic silently went wrong, not to check algebra once.
#
# Usage (all lengths in um, temp in C, f in Hz):
#   awk -v w=8.22 -v s=3.29 -v d=47.65 -v n=1 -v mc_rsh=1 -v mc_rsub=1 \
#       -v temp=27 -v f=5e9 -f closed_form_z.awk </dev/null
# Prints, space separated:
#   zr zi absz leff q k_2side k_1side dR_crowd
# where dR_crowd is the extra series resistance the one-sided
# effective-conduction-depth assumption would add (the Q lower-bound term --
# see ACCURACY LIMITS item 3 in sg13g2_inductor_analytic.spice).
#
# SPDX-License-Identifier: Apache-2.0

function cmul_r(ar, ai, br, bi) { return ar*br - ai*bi }
function cmul_i(ar, ai, br, bi) { return ar*bi + ai*br }
function cdiv_r(ar, ai, br, bi,   den) { den = br*br + bi*bi; return (ar*br + ai*bi)/den }
function cdiv_i(ar, ai, br, bi,   den) { den = br*br + bi*bi; return (ai*br - ar*bi)/den }
function sinh_(x) { return (exp(x) - exp(-x))/2 }
function cosh_(x) { return (exp(x) + exp(-x))/2 }

BEGIN {
    PI   = 3.14159265358979
    MU0  = 1.25663706212e-6
    EPS0 = 8.8541878128e-12

    # ---- PDK constants, identical to sg13g2_inductor_analytic.spice ----------
    TTM2   = 3.000e-6
    RSH2   = 11.0e-3
    RSH1   = 18.0e-3
    TC2    = 3.8e-3
    DW2    = -0.140e-6
    RTV2   = 1.1
    CASUB  = 3.233e-6
    CPSUB  = 31.175e-12
    CA21   = 13.0e-6
    RHOSUB = 0.5
    EPSSI  = 11.9
    GRID   = 0.01e-6
    KOCT   = 3.31370849898476
    AOCT   = 0.828427124746190

    # ---- geometry (inputs arrive in um) --------------------------------------
    wm = w*1e-6; sm = s*1e-6; dm = d*1e-6
    pitch = sm + wm + GRID
    din   = dm
    dout  = dm + 2*(n-1)*pitch + 2*wm
    davg  = (din + dout)/2
    fill  = (dout - din)/(dout + din)
    len   = KOCT*n*(dm + wm + (n-1)*pitch)
    weff  = wm + DW2

    # ---- inductance: Mohan et al. 1999 eq. (1), octagonal --------------------
    lmw = 2.25*MU0*n*n*davg/(1 + 3.55*fill)

    # ---- series resistance, temperature-scaled exactly as ngspice tc1 does ---
    tsc  = 1 + TC2*(temp - 27)
    rshT = RSH2*mc_rsh*tsc
    rdc  = rshT*len/weff
    lu   = MU0*len*TTM2/(2*weff)

    nvia  = int((w + 0.06)/1.96)
    narr  = (n > 1) ? 2*n : 0
    ltm1  = 2*(1.70711*wm + 0.9143*sm)
    # The whole crossunder resistor carries TC1RSTM2 in the netlist (one R
    # element), so the via term drifts with temperature here too -- see the
    # crossunder note in sg13g2_inductor_analytic.spice. The mc_rsh process
    # corner is applied only to the metal term, matching the netlist.
    rcros = (narr*RTV2/(nvia*nvia) + (n-1)*RSH1*mc_rsh*ltm1/weff + 1e-9)*tsc

    # ---- exact vertical-skin internal impedance: R_dc * xi*coth(xi) ----------
    # rho_m = sheet resistance * thickness, so f_skin (delta = t) is
    # rho_m/(pi*mu0*t^2) and u = f/f_skin = (t/delta)^2.
    rhom  = rshT*TTM2
    fskin = rhom/(PI*MU0*TTM2*TTM2)
    u     = f/fskin
    a     = sqrt(u)/2
    b     = a
    chr = cosh_(a)*cos(b); chi = sinh_(a)*sin(b)
    shr = sinh_(a)*cos(b); shi = cosh_(a)*sin(b)
    cothr = cdiv_r(chr, chi, shr, shi)
    cothi = cdiv_i(chr, chi, shr, shi)
    xcr = cmul_r(a, b, cothr, cothi)
    xci = cmul_i(a, b, cothr, cothi)

    om = 2*PI*f

    # series branch: R_dc*xi*coth(xi) already carries R_dc and the internal
    # inductance lu/6, so the external inductance is lmw - lu/6.
    zsr = rdc*xcr + rcros
    zsi = rdc*xci + om*(lmw - lu/6)

    # ---- feed-through and oxide/substrate ------------------------------------
    novl = 2*(n-1)
    cs   = novl*weff*weff*CA21 + 1e-21

    aband = AOCT*(dout*dout - din*din)
    edge  = KOCT*(dout + din)
    coxt  = aband*CASUB + edge*CPSUB
    coxh  = coxt/2

    rhos = RHOSUB*mc_rsub
    aout = AOCT*dout*dout
    aeq  = sqrt(aout/PI)
    rsi  = sqrt(2)*rhos/(4*aeq)
    csi  = EPS0*EPSSI*rhos/rsi

    # substrate branch as seen from port la: 1/(j w Coxh) + (Rsi || Csi)
    ysr = 1/rsi; ysi = om*csi
    zsubr = cdiv_r(1, 0, ysr, ysi); zsubi = cdiv_i(1, 0, ysr, ysi)
    zbr = zsubr; zbi = zsubi - 1/(om*coxh)

    # total admittance at la, with lb and sub grounded (as in the testbench),
    # plus the testbench's own 1 H DC-path inductor to ground.
    ytr = cdiv_r(1, 0, zsr, zsi) + cdiv_r(1, 0, zbr, zbi)
    yti = cdiv_i(1, 0, zsr, zsi) + cdiv_i(1, 0, zbr, zbi) + om*cs - 1/(om*1.0)

    zr = cdiv_r(1, 0, ytr, yti)
    zi = cdiv_i(1, 0, ytr, yti)

    # ---- current-crowding lower bound on Q -----------------------------------
    # One-sided effective conduction depth t_eff = delta*(1-exp(-t/delta)),
    # i.e. R/R_dc = sqrt(u)/(1-exp(-sqrt(u))). See ACCURACY LIMITS item 3.
    k1 = sqrt(u)/(1 - exp(-sqrt(u)))
    dR = rdc*(k1 - xcr)

    printf "%.9e %.9e %.9e %.9e %.9e %.9e %.9e %.9e\n", \
        zr, zi, sqrt(zr*zr + zi*zi), zi/om, zi/zr, xcr, k1, dR
}

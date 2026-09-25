v {xschem version=3.4.7 file_version=1.2
}
G {}
K {}
V {}
S {}
E {}
T {sg13g2-vco -- LC-VCO core, v1 (issue #44)

Topology is fixed by the decision records, not chosen here:
  DR-002  SiGe HBT cross-coupled pair, npn13G2v, 3.3 V rail, tail-current biased
  DR-001  sg13_hv_svaricap MOS accumulation-mode varactor over the full
          0.0-3.3 V Vctrl domain; no band-switching capacitor bank in v1
  DR-003  ratified rows 1 (4.5/5.0/5.5 GHz), 2 (tuning range >= 15 %),
          5 (loaded tank Q >= 6), 6 (startup margin >= 3.0), 8 (<= 10 mW)

Tank sizing -- 16 parallel minimum-geometry sg13_hv_svaricap cells per side,
one 3.65 x 3.65 um cap_cmim across the tank, two p11 EM-extracted spirals --
and the arithmetic behind it, including why the fixed capacitor is cap_cmim
and not cap_rfcmim (whose model and PCell both floor at 7 um, i.e. 74 fF,
3.7x this tank's entire row-2 fixed-C budget): design/README.md.} -1500 -140 0 0 0.4 0.4 {}
N -900 -1330 -900 -1350 {
lab=VDD}
N -900 -1270 -900 -1250 {
lab=OUTP}
N -870 -1270 -830 -1270 {
lab=0}
N 900 -1330 900 -1350 {
lab=VDD}
N 900 -1270 900 -1250 {
lab=OUTN}
N 930 -1270 970 -1270 {
lab=0}
N 0 -1330 0 -1350 {
lab=OUTP}
N 0 -1270 0 -1250 {
lab=OUTN}
N -340 -1000 -360 -1000 {
lab=VCTRL}
N -260 -1000 -240 -1000 {
lab=VCTRL}
N -300 -1030 -300 -1050 {
lab=OUTP}
N -300 -970 -300 -950 {
lab=OUTP}
N -510 -1000 -530 -1000 {
lab=VCTRL}
N -430 -1000 -410 -1000 {
lab=VCTRL}
N -470 -1030 -470 -1050 {
lab=OUTP}
N -470 -970 -470 -950 {
lab=OUTP}
N -680 -1000 -700 -1000 {
lab=VCTRL}
N -600 -1000 -580 -1000 {
lab=VCTRL}
N -640 -1030 -640 -1050 {
lab=OUTP}
N -640 -970 -640 -950 {
lab=OUTP}
N -850 -1000 -870 -1000 {
lab=VCTRL}
N -770 -1000 -750 -1000 {
lab=VCTRL}
N -810 -1030 -810 -1050 {
lab=OUTP}
N -810 -970 -810 -950 {
lab=OUTP}
N -1020 -1000 -1040 -1000 {
lab=VCTRL}
N -940 -1000 -920 -1000 {
lab=VCTRL}
N -980 -1030 -980 -1050 {
lab=OUTP}
N -980 -970 -980 -950 {
lab=OUTP}
N -1190 -1000 -1210 -1000 {
lab=VCTRL}
N -1110 -1000 -1090 -1000 {
lab=VCTRL}
N -1150 -1030 -1150 -1050 {
lab=OUTP}
N -1150 -970 -1150 -950 {
lab=OUTP}
N -1360 -1000 -1380 -1000 {
lab=VCTRL}
N -1280 -1000 -1260 -1000 {
lab=VCTRL}
N -1320 -1030 -1320 -1050 {
lab=OUTP}
N -1320 -970 -1320 -950 {
lab=OUTP}
N -1530 -1000 -1550 -1000 {
lab=VCTRL}
N -1450 -1000 -1430 -1000 {
lab=VCTRL}
N -1490 -1030 -1490 -1050 {
lab=OUTP}
N -1490 -970 -1490 -950 {
lab=OUTP}
N -340 -800 -360 -800 {
lab=VCTRL}
N -260 -800 -240 -800 {
lab=VCTRL}
N -300 -830 -300 -850 {
lab=OUTP}
N -300 -770 -300 -750 {
lab=OUTP}
N -510 -800 -530 -800 {
lab=VCTRL}
N -430 -800 -410 -800 {
lab=VCTRL}
N -470 -830 -470 -850 {
lab=OUTP}
N -470 -770 -470 -750 {
lab=OUTP}
N -680 -800 -700 -800 {
lab=VCTRL}
N -600 -800 -580 -800 {
lab=VCTRL}
N -640 -830 -640 -850 {
lab=OUTP}
N -640 -770 -640 -750 {
lab=OUTP}
N -850 -800 -870 -800 {
lab=VCTRL}
N -770 -800 -750 -800 {
lab=VCTRL}
N -810 -830 -810 -850 {
lab=OUTP}
N -810 -770 -810 -750 {
lab=OUTP}
N -1020 -800 -1040 -800 {
lab=VCTRL}
N -940 -800 -920 -800 {
lab=VCTRL}
N -980 -830 -980 -850 {
lab=OUTP}
N -980 -770 -980 -750 {
lab=OUTP}
N -1190 -800 -1210 -800 {
lab=VCTRL}
N -1110 -800 -1090 -800 {
lab=VCTRL}
N -1150 -830 -1150 -850 {
lab=OUTP}
N -1150 -770 -1150 -750 {
lab=OUTP}
N -1360 -800 -1380 -800 {
lab=VCTRL}
N -1280 -800 -1260 -800 {
lab=VCTRL}
N -1320 -830 -1320 -850 {
lab=OUTP}
N -1320 -770 -1320 -750 {
lab=OUTP}
N -1530 -800 -1550 -800 {
lab=VCTRL}
N -1450 -800 -1430 -800 {
lab=VCTRL}
N -1490 -830 -1490 -850 {
lab=OUTP}
N -1490 -770 -1490 -750 {
lab=OUTP}
N 260 -1000 240 -1000 {
lab=VCTRL}
N 340 -1000 360 -1000 {
lab=VCTRL}
N 300 -1030 300 -1050 {
lab=OUTN}
N 300 -970 300 -950 {
lab=OUTN}
N 430 -1000 410 -1000 {
lab=VCTRL}
N 510 -1000 530 -1000 {
lab=VCTRL}
N 470 -1030 470 -1050 {
lab=OUTN}
N 470 -970 470 -950 {
lab=OUTN}
N 600 -1000 580 -1000 {
lab=VCTRL}
N 680 -1000 700 -1000 {
lab=VCTRL}
N 640 -1030 640 -1050 {
lab=OUTN}
N 640 -970 640 -950 {
lab=OUTN}
N 770 -1000 750 -1000 {
lab=VCTRL}
N 850 -1000 870 -1000 {
lab=VCTRL}
N 810 -1030 810 -1050 {
lab=OUTN}
N 810 -970 810 -950 {
lab=OUTN}
N 940 -1000 920 -1000 {
lab=VCTRL}
N 1020 -1000 1040 -1000 {
lab=VCTRL}
N 980 -1030 980 -1050 {
lab=OUTN}
N 980 -970 980 -950 {
lab=OUTN}
N 1110 -1000 1090 -1000 {
lab=VCTRL}
N 1190 -1000 1210 -1000 {
lab=VCTRL}
N 1150 -1030 1150 -1050 {
lab=OUTN}
N 1150 -970 1150 -950 {
lab=OUTN}
N 1280 -1000 1260 -1000 {
lab=VCTRL}
N 1360 -1000 1380 -1000 {
lab=VCTRL}
N 1320 -1030 1320 -1050 {
lab=OUTN}
N 1320 -970 1320 -950 {
lab=OUTN}
N 1450 -1000 1430 -1000 {
lab=VCTRL}
N 1530 -1000 1550 -1000 {
lab=VCTRL}
N 1490 -1030 1490 -1050 {
lab=OUTN}
N 1490 -970 1490 -950 {
lab=OUTN}
N 260 -800 240 -800 {
lab=VCTRL}
N 340 -800 360 -800 {
lab=VCTRL}
N 300 -830 300 -850 {
lab=OUTN}
N 300 -770 300 -750 {
lab=OUTN}
N 430 -800 410 -800 {
lab=VCTRL}
N 510 -800 530 -800 {
lab=VCTRL}
N 470 -830 470 -850 {
lab=OUTN}
N 470 -770 470 -750 {
lab=OUTN}
N 600 -800 580 -800 {
lab=VCTRL}
N 680 -800 700 -800 {
lab=VCTRL}
N 640 -830 640 -850 {
lab=OUTN}
N 640 -770 640 -750 {
lab=OUTN}
N 770 -800 750 -800 {
lab=VCTRL}
N 850 -800 870 -800 {
lab=VCTRL}
N 810 -830 810 -850 {
lab=OUTN}
N 810 -770 810 -750 {
lab=OUTN}
N 940 -800 920 -800 {
lab=VCTRL}
N 1020 -800 1040 -800 {
lab=VCTRL}
N 980 -830 980 -850 {
lab=OUTN}
N 980 -770 980 -750 {
lab=OUTN}
N 1110 -800 1090 -800 {
lab=VCTRL}
N 1190 -800 1210 -800 {
lab=VCTRL}
N 1150 -830 1150 -850 {
lab=OUTN}
N 1150 -770 1150 -750 {
lab=OUTN}
N 1280 -800 1260 -800 {
lab=VCTRL}
N 1360 -800 1380 -800 {
lab=VCTRL}
N 1320 -830 1320 -850 {
lab=OUTN}
N 1320 -770 1320 -750 {
lab=OUTN}
N 1450 -800 1430 -800 {
lab=VCTRL}
N 1530 -800 1550 -800 {
lab=VCTRL}
N 1490 -830 1490 -850 {
lab=OUTN}
N 1490 -770 1490 -750 {
lab=OUTN}
N -280 -530 -280 -550 {
lab=OUTP}
N -320 -500 -340 -500 {
lab=OUTN}
N -280 -470 -280 -450 {
lab=TAIL}
N -280 -500 -260 -500 {
lab=0}
N 320 -530 320 -550 {
lab=OUTN}
N 280 -500 260 -500 {
lab=OUTP}
N 320 -470 320 -450 {
lab=TAIL}
N 320 -500 340 -500 {
lab=0}
N 20 -330 20 -350 {
lab=TAIL}
N -20 -300 -40 -300 {
lab=NBIAS}
N 20 -270 20 -250 {
lab=TE}
N 20 -300 40 -300 {
lab=0}
N 0 -190 0 -210 {
lab=TE}
N 0 -130 0 -110 {
lab=0}
N 900 -470 900 -490 {
lab=VDD}
N 900 -410 900 -390 {
lab=NBIAS}
N 920 -330 920 -350 {
lab=NBIAS}
N 880 -300 860 -300 {
lab=NBIAS}
N 920 -270 920 -250 {
lab=RE}
N 920 -300 940 -300 {
lab=0}
N 900 -190 900 -210 {
lab=RE}
N 900 -130 900 -110 {
lab=0}
N -1500 -1330 -1540 -1330 {
lab=VDD}
N -1500 -1270 -1540 -1270 {
lab=0}
N -1500 -1030 -1540 -1030 {
lab=VCTRL}
N -1500 -970 -1540 -970 {
lab=0}
C {sg13g2_pr/inductor.sym} -900 -1300 0 0 {name=L1
m=1
value=1n
footprint=1206
device=inductor
spiceprefix=X
w=8.22e-6
s=3.74e-6
d=141.975e-6
nr_r=4}
C {sg13g2_pr/inductor.sym} 900 -1300 0 0 {name=L2
m=1
value=1n
footprint=1206
device=inductor
spiceprefix=X
w=8.22e-6
s=3.74e-6
d=141.975e-6
nr_r=4}
C {sg13g2_pr/cap_cmim.sym} 0 -1300 0 0 {name=C1
model=cap_cmim
w=3.65e-6
l=3.65e-6
m=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -300 -1000 0 0 {name=CVP1
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -470 -1000 0 0 {name=CVP2
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -640 -1000 0 0 {name=CVP3
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -810 -1000 0 0 {name=CVP4
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -980 -1000 0 0 {name=CVP5
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -1150 -1000 0 0 {name=CVP6
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -1320 -1000 0 0 {name=CVP7
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -1490 -1000 0 0 {name=CVP8
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -300 -800 0 0 {name=CVP9
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -470 -800 0 0 {name=CVP10
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -640 -800 0 0 {name=CVP11
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -810 -800 0 0 {name=CVP12
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -980 -800 0 0 {name=CVP13
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -1150 -800 0 0 {name=CVP14
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -1320 -800 0 0 {name=CVP15
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} -1490 -800 0 0 {name=CVP16
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 300 -1000 0 0 {name=CVN1
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 470 -1000 0 0 {name=CVN2
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 640 -1000 0 0 {name=CVN3
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 810 -1000 0 0 {name=CVN4
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 980 -1000 0 0 {name=CVN5
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 1150 -1000 0 0 {name=CVN6
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 1320 -1000 0 0 {name=CVN7
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 1490 -1000 0 0 {name=CVN8
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 300 -800 0 0 {name=CVN9
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 470 -800 0 0 {name=CVN10
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 640 -800 0 0 {name=CVN11
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 810 -800 0 0 {name=CVN12
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 980 -800 0 0 {name=CVN13
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 1150 -800 0 0 {name=CVN14
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 1320 -800 0 0 {name=CVN15
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/sg13_svaricap.sym} 1490 -800 0 0 {name=CVN16
model=sg13_hv_svaricap
w=3.74e-6
l=0.3e-6
Nx=1
spiceprefix=X}
C {sg13g2_pr/npn13G2v.sym} -300 -500 0 0 {name=Q1
model=npn13G2v
spiceprefix=X
Nx=1
El=1.0}
C {sg13g2_pr/npn13G2v.sym} 300 -500 0 0 {name=Q2
model=npn13G2v
spiceprefix=X
Nx=1
El=1.0}
C {sg13g2_pr/npn13G2v.sym} 0 -300 0 0 {name=Q3
model=npn13G2v
spiceprefix=X
Nx=1
El=2.0}
C {devices/res.sym} 0 -160 0 0 {name=RTE
value=2k
footprint=1206
device=resistor
m=1}
C {devices/res.sym} 900 -440 0 0 {name=RREF
value=20.5k
footprint=1206
device=resistor
m=1}
C {sg13g2_pr/npn13G2v.sym} 900 -300 0 0 {name=Q4
model=npn13G2v
spiceprefix=X
Nx=1
El=1.0}
C {devices/res.sym} 900 -160 0 0 {name=RRE
value=4k
footprint=1206
device=resistor
m=1}
C {devices/vsource.sym} -1500 -1300 0 0 {name=VSUP
value="dc 3.3"
savecurrent=true}
C {devices/vsource.sym} -1500 -1000 0 0 {name=VCT
value="dc 1.65"
savecurrent=false}
C {devices/lab_pin.sym} -900 -1350 0 0 {name=p1 lab=VDD}
C {devices/lab_pin.sym} -900 -1250 0 0 {name=p2 lab=OUTP}
C {devices/lab_pin.sym} -830 -1270 0 0 {name=p3 lab=0}
C {devices/lab_pin.sym} 900 -1350 0 0 {name=p4 lab=VDD}
C {devices/lab_pin.sym} 900 -1250 0 0 {name=p5 lab=OUTN}
C {devices/lab_pin.sym} 970 -1270 0 0 {name=p6 lab=0}
C {devices/lab_pin.sym} 0 -1350 0 0 {name=p7 lab=OUTP}
C {devices/lab_pin.sym} 0 -1250 0 0 {name=p8 lab=OUTN}
C {devices/lab_pin.sym} -360 -1000 0 0 {name=p10 lab=VCTRL}
C {devices/lab_pin.sym} -240 -1000 0 0 {name=p11 lab=VCTRL}
C {devices/lab_pin.sym} -300 -1050 0 0 {name=p12 lab=OUTP}
C {devices/lab_pin.sym} -300 -950 0 0 {name=p13 lab=OUTP}
C {devices/lab_pin.sym} -530 -1000 0 0 {name=p14 lab=VCTRL}
C {devices/lab_pin.sym} -410 -1000 0 0 {name=p15 lab=VCTRL}
C {devices/lab_pin.sym} -470 -1050 0 0 {name=p16 lab=OUTP}
C {devices/lab_pin.sym} -470 -950 0 0 {name=p17 lab=OUTP}
C {devices/lab_pin.sym} -700 -1000 0 0 {name=p18 lab=VCTRL}
C {devices/lab_pin.sym} -580 -1000 0 0 {name=p19 lab=VCTRL}
C {devices/lab_pin.sym} -640 -1050 0 0 {name=p20 lab=OUTP}
C {devices/lab_pin.sym} -640 -950 0 0 {name=p21 lab=OUTP}
C {devices/lab_pin.sym} -870 -1000 0 0 {name=p22 lab=VCTRL}
C {devices/lab_pin.sym} -750 -1000 0 0 {name=p23 lab=VCTRL}
C {devices/lab_pin.sym} -810 -1050 0 0 {name=p24 lab=OUTP}
C {devices/lab_pin.sym} -810 -950 0 0 {name=p25 lab=OUTP}
C {devices/lab_pin.sym} -1040 -1000 0 0 {name=p26 lab=VCTRL}
C {devices/lab_pin.sym} -920 -1000 0 0 {name=p27 lab=VCTRL}
C {devices/lab_pin.sym} -980 -1050 0 0 {name=p28 lab=OUTP}
C {devices/lab_pin.sym} -980 -950 0 0 {name=p29 lab=OUTP}
C {devices/lab_pin.sym} -1210 -1000 0 0 {name=p30 lab=VCTRL}
C {devices/lab_pin.sym} -1090 -1000 0 0 {name=p31 lab=VCTRL}
C {devices/lab_pin.sym} -1150 -1050 0 0 {name=p32 lab=OUTP}
C {devices/lab_pin.sym} -1150 -950 0 0 {name=p33 lab=OUTP}
C {devices/lab_pin.sym} -1380 -1000 0 0 {name=p34 lab=VCTRL}
C {devices/lab_pin.sym} -1260 -1000 0 0 {name=p35 lab=VCTRL}
C {devices/lab_pin.sym} -1320 -1050 0 0 {name=p36 lab=OUTP}
C {devices/lab_pin.sym} -1320 -950 0 0 {name=p37 lab=OUTP}
C {devices/lab_pin.sym} -1550 -1000 0 0 {name=p38 lab=VCTRL}
C {devices/lab_pin.sym} -1430 -1000 0 0 {name=p39 lab=VCTRL}
C {devices/lab_pin.sym} -1490 -1050 0 0 {name=p40 lab=OUTP}
C {devices/lab_pin.sym} -1490 -950 0 0 {name=p41 lab=OUTP}
C {devices/lab_pin.sym} -360 -800 0 0 {name=p42 lab=VCTRL}
C {devices/lab_pin.sym} -240 -800 0 0 {name=p43 lab=VCTRL}
C {devices/lab_pin.sym} -300 -850 0 0 {name=p44 lab=OUTP}
C {devices/lab_pin.sym} -300 -750 0 0 {name=p45 lab=OUTP}
C {devices/lab_pin.sym} -530 -800 0 0 {name=p46 lab=VCTRL}
C {devices/lab_pin.sym} -410 -800 0 0 {name=p47 lab=VCTRL}
C {devices/lab_pin.sym} -470 -850 0 0 {name=p48 lab=OUTP}
C {devices/lab_pin.sym} -470 -750 0 0 {name=p49 lab=OUTP}
C {devices/lab_pin.sym} -700 -800 0 0 {name=p50 lab=VCTRL}
C {devices/lab_pin.sym} -580 -800 0 0 {name=p51 lab=VCTRL}
C {devices/lab_pin.sym} -640 -850 0 0 {name=p52 lab=OUTP}
C {devices/lab_pin.sym} -640 -750 0 0 {name=p53 lab=OUTP}
C {devices/lab_pin.sym} -870 -800 0 0 {name=p54 lab=VCTRL}
C {devices/lab_pin.sym} -750 -800 0 0 {name=p55 lab=VCTRL}
C {devices/lab_pin.sym} -810 -850 0 0 {name=p56 lab=OUTP}
C {devices/lab_pin.sym} -810 -750 0 0 {name=p57 lab=OUTP}
C {devices/lab_pin.sym} -1040 -800 0 0 {name=p58 lab=VCTRL}
C {devices/lab_pin.sym} -920 -800 0 0 {name=p59 lab=VCTRL}
C {devices/lab_pin.sym} -980 -850 0 0 {name=p60 lab=OUTP}
C {devices/lab_pin.sym} -980 -750 0 0 {name=p61 lab=OUTP}
C {devices/lab_pin.sym} -1210 -800 0 0 {name=p62 lab=VCTRL}
C {devices/lab_pin.sym} -1090 -800 0 0 {name=p63 lab=VCTRL}
C {devices/lab_pin.sym} -1150 -850 0 0 {name=p64 lab=OUTP}
C {devices/lab_pin.sym} -1150 -750 0 0 {name=p65 lab=OUTP}
C {devices/lab_pin.sym} -1380 -800 0 0 {name=p66 lab=VCTRL}
C {devices/lab_pin.sym} -1260 -800 0 0 {name=p67 lab=VCTRL}
C {devices/lab_pin.sym} -1320 -850 0 0 {name=p68 lab=OUTP}
C {devices/lab_pin.sym} -1320 -750 0 0 {name=p69 lab=OUTP}
C {devices/lab_pin.sym} -1550 -800 0 0 {name=p70 lab=VCTRL}
C {devices/lab_pin.sym} -1430 -800 0 0 {name=p71 lab=VCTRL}
C {devices/lab_pin.sym} -1490 -850 0 0 {name=p72 lab=OUTP}
C {devices/lab_pin.sym} -1490 -750 0 0 {name=p73 lab=OUTP}
C {devices/lab_pin.sym} 240 -1000 0 0 {name=p74 lab=VCTRL}
C {devices/lab_pin.sym} 360 -1000 0 0 {name=p75 lab=VCTRL}
C {devices/lab_pin.sym} 300 -1050 0 0 {name=p76 lab=OUTN}
C {devices/lab_pin.sym} 300 -950 0 0 {name=p77 lab=OUTN}
C {devices/lab_pin.sym} 410 -1000 0 0 {name=p78 lab=VCTRL}
C {devices/lab_pin.sym} 530 -1000 0 0 {name=p79 lab=VCTRL}
C {devices/lab_pin.sym} 470 -1050 0 0 {name=p80 lab=OUTN}
C {devices/lab_pin.sym} 470 -950 0 0 {name=p81 lab=OUTN}
C {devices/lab_pin.sym} 580 -1000 0 0 {name=p82 lab=VCTRL}
C {devices/lab_pin.sym} 700 -1000 0 0 {name=p83 lab=VCTRL}
C {devices/lab_pin.sym} 640 -1050 0 0 {name=p84 lab=OUTN}
C {devices/lab_pin.sym} 640 -950 0 0 {name=p85 lab=OUTN}
C {devices/lab_pin.sym} 750 -1000 0 0 {name=p86 lab=VCTRL}
C {devices/lab_pin.sym} 870 -1000 0 0 {name=p87 lab=VCTRL}
C {devices/lab_pin.sym} 810 -1050 0 0 {name=p88 lab=OUTN}
C {devices/lab_pin.sym} 810 -950 0 0 {name=p89 lab=OUTN}
C {devices/lab_pin.sym} 920 -1000 0 0 {name=p90 lab=VCTRL}
C {devices/lab_pin.sym} 1040 -1000 0 0 {name=p91 lab=VCTRL}
C {devices/lab_pin.sym} 980 -1050 0 0 {name=p92 lab=OUTN}
C {devices/lab_pin.sym} 980 -950 0 0 {name=p93 lab=OUTN}
C {devices/lab_pin.sym} 1090 -1000 0 0 {name=p94 lab=VCTRL}
C {devices/lab_pin.sym} 1210 -1000 0 0 {name=p95 lab=VCTRL}
C {devices/lab_pin.sym} 1150 -1050 0 0 {name=p96 lab=OUTN}
C {devices/lab_pin.sym} 1150 -950 0 0 {name=p97 lab=OUTN}
C {devices/lab_pin.sym} 1260 -1000 0 0 {name=p98 lab=VCTRL}
C {devices/lab_pin.sym} 1380 -1000 0 0 {name=p99 lab=VCTRL}
C {devices/lab_pin.sym} 1320 -1050 0 0 {name=p100 lab=OUTN}
C {devices/lab_pin.sym} 1320 -950 0 0 {name=p101 lab=OUTN}
C {devices/lab_pin.sym} 1430 -1000 0 0 {name=p102 lab=VCTRL}
C {devices/lab_pin.sym} 1550 -1000 0 0 {name=p103 lab=VCTRL}
C {devices/lab_pin.sym} 1490 -1050 0 0 {name=p104 lab=OUTN}
C {devices/lab_pin.sym} 1490 -950 0 0 {name=p105 lab=OUTN}
C {devices/lab_pin.sym} 240 -800 0 0 {name=p106 lab=VCTRL}
C {devices/lab_pin.sym} 360 -800 0 0 {name=p107 lab=VCTRL}
C {devices/lab_pin.sym} 300 -850 0 0 {name=p108 lab=OUTN}
C {devices/lab_pin.sym} 300 -750 0 0 {name=p109 lab=OUTN}
C {devices/lab_pin.sym} 410 -800 0 0 {name=p110 lab=VCTRL}
C {devices/lab_pin.sym} 530 -800 0 0 {name=p111 lab=VCTRL}
C {devices/lab_pin.sym} 470 -850 0 0 {name=p112 lab=OUTN}
C {devices/lab_pin.sym} 470 -750 0 0 {name=p113 lab=OUTN}
C {devices/lab_pin.sym} 580 -800 0 0 {name=p114 lab=VCTRL}
C {devices/lab_pin.sym} 700 -800 0 0 {name=p115 lab=VCTRL}
C {devices/lab_pin.sym} 640 -850 0 0 {name=p116 lab=OUTN}
C {devices/lab_pin.sym} 640 -750 0 0 {name=p117 lab=OUTN}
C {devices/lab_pin.sym} 750 -800 0 0 {name=p118 lab=VCTRL}
C {devices/lab_pin.sym} 870 -800 0 0 {name=p119 lab=VCTRL}
C {devices/lab_pin.sym} 810 -850 0 0 {name=p120 lab=OUTN}
C {devices/lab_pin.sym} 810 -750 0 0 {name=p121 lab=OUTN}
C {devices/lab_pin.sym} 920 -800 0 0 {name=p122 lab=VCTRL}
C {devices/lab_pin.sym} 1040 -800 0 0 {name=p123 lab=VCTRL}
C {devices/lab_pin.sym} 980 -850 0 0 {name=p124 lab=OUTN}
C {devices/lab_pin.sym} 980 -750 0 0 {name=p125 lab=OUTN}
C {devices/lab_pin.sym} 1090 -800 0 0 {name=p126 lab=VCTRL}
C {devices/lab_pin.sym} 1210 -800 0 0 {name=p127 lab=VCTRL}
C {devices/lab_pin.sym} 1150 -850 0 0 {name=p128 lab=OUTN}
C {devices/lab_pin.sym} 1150 -750 0 0 {name=p129 lab=OUTN}
C {devices/lab_pin.sym} 1260 -800 0 0 {name=p130 lab=VCTRL}
C {devices/lab_pin.sym} 1380 -800 0 0 {name=p131 lab=VCTRL}
C {devices/lab_pin.sym} 1320 -850 0 0 {name=p132 lab=OUTN}
C {devices/lab_pin.sym} 1320 -750 0 0 {name=p133 lab=OUTN}
C {devices/lab_pin.sym} 1430 -800 0 0 {name=p134 lab=VCTRL}
C {devices/lab_pin.sym} 1550 -800 0 0 {name=p135 lab=VCTRL}
C {devices/lab_pin.sym} 1490 -850 0 0 {name=p136 lab=OUTN}
C {devices/lab_pin.sym} 1490 -750 0 0 {name=p137 lab=OUTN}
C {devices/lab_pin.sym} -280 -550 0 0 {name=p138 lab=OUTP}
C {devices/lab_pin.sym} -340 -500 0 0 {name=p139 lab=OUTN}
C {devices/lab_pin.sym} -280 -450 0 0 {name=p140 lab=TAIL}
C {devices/lab_pin.sym} -260 -500 0 0 {name=p141 lab=0}
C {devices/lab_pin.sym} 320 -550 0 0 {name=p142 lab=OUTN}
C {devices/lab_pin.sym} 260 -500 0 0 {name=p143 lab=OUTP}
C {devices/lab_pin.sym} 320 -450 0 0 {name=p144 lab=TAIL}
C {devices/lab_pin.sym} 340 -500 0 0 {name=p145 lab=0}
C {devices/lab_pin.sym} 20 -350 0 0 {name=p146 lab=TAIL}
C {devices/lab_pin.sym} -40 -300 0 0 {name=p147 lab=NBIAS}
C {devices/lab_pin.sym} 20 -250 0 0 {name=p148 lab=TE}
C {devices/lab_pin.sym} 40 -300 0 0 {name=p149 lab=0}
C {devices/lab_pin.sym} 0 -210 0 0 {name=p150 lab=TE}
C {devices/lab_pin.sym} 0 -110 0 0 {name=p151 lab=0}
C {devices/lab_pin.sym} 900 -490 0 0 {name=p152 lab=VDD}
C {devices/lab_pin.sym} 900 -390 0 0 {name=p153 lab=NBIAS}
C {devices/lab_pin.sym} 920 -350 0 0 {name=p154 lab=NBIAS}
C {devices/lab_pin.sym} 860 -300 0 0 {name=p155 lab=NBIAS}
C {devices/lab_pin.sym} 920 -250 0 0 {name=p156 lab=RE}
C {devices/lab_pin.sym} 940 -300 0 0 {name=p157 lab=0}
C {devices/lab_pin.sym} 900 -210 0 0 {name=p158 lab=RE}
C {devices/lab_pin.sym} 900 -110 0 0 {name=p159 lab=0}
C {devices/lab_pin.sym} -1540 -1330 0 0 {name=p160 lab=VDD}
C {devices/lab_pin.sym} -1540 -1270 0 0 {name=p161 lab=0}
C {devices/lab_pin.sym} -1540 -1030 0 0 {name=p162 lab=VCTRL}
C {devices/lab_pin.sym} -1540 -970 0 0 {name=p163 lab=0}
C {devices/code_shown.sym} -1500 -740 0 0 {name=MODELS only_toplevel=false
value="
* Model libraries for this elaboration. The paths below are machine-specific,
* so the committed netlist carries placeholder tokens that
* design/run_elaborate.sh substitutes before running ngspice -- the same
* mechanism sim/*/run_*.sh use for their testbench templates. The token list
* and what each resolves to is documented in design/README.md.
.lib @@MODELS_DIR@@/cornerHBT.lib hbt_typ
.lib @@MODELS_DIR@@/cornerMOShv.lib mos_tt
.lib @@MODELS_DIR@@/cornerCAP.lib cap_typ
.include @@IND_MODEL@@
"}
C {devices/code_shown.sym} 300 -740 0 0 {name=NGSPICE only_toplevel=false
value="
* A perfectly symmetric differential pair sits on an unstable DC equilibrium;
* this 10 mV differential initial condition is what lets the startup transient
* leave it.  It is an initial condition, not a drive: it is not refreshed.
.ic v(OUTP)=3.305 v(OUTN)=3.295

.control
pre_osdi @@OSDI_MOSVAR@@
* VSUP carries savecurrent=true, which emits a `.save i(vsup)` card -- and a
* .save card RESTRICTS the saved set, so without this `save all` every node
* voltage below is unavailable and `let vdiff = ...` has nothing to read.
save all
op
print v(NBIAS) v(TE) v(TAIL) v(OUTP) v(OUTN) i(VSUP)
* 2 ps ceiling = 100 points per period at 5 GHz, ample for the rising-zero-
* crossing period count design/run_elaborate.sh does; 20 ns is ~100 periods,
* and startup from the .ic below completes inside the first nanosecond
* (net negative conductance / 2C ~ 7 GNp/s), so the 10-20 ns window the
* script measures over is settled oscillation.
foreach vv 0 1.65 3.3
  alter VCT dc = $vv
  tran 1p 20n 0 2p
  let vdiff = v(OUTP) - v(OUTN)
  wrdata vco_tran_$vv vdiff
* Differential-mode evidence, not decoration. A genuinely differential tank
* puts the whole fundamental into vdiff and leaves the common mode and the
* tail node with only the 2f component the two half-circuits pump in phase;
* two independently-resonating branches would instead show a fundamental in
* vcm. run_elaborate.sh reports Vpp(vcm)/Vpp(vdiff) and the tail node's own
* crossing-counted frequency against f_osc for exactly that test.
  let vcm = (v(OUTP) + v(OUTN))/2 - 3.3
  wrdata vco_cm_$vv vcm
  let vtl = v(TAIL) - mean(v(TAIL))
  wrdata vco_tail_$vv vtl
* Large-signal supply current: the row-8 power number the DC operating point
* alone cannot give, since the pair's average current shifts once it is
* switching. Sign flipped so the printed number is current OUT of the rail.
  let isup = -i(VSUP)
  wrdata vco_isup_$vv isup
end
.endc
"}

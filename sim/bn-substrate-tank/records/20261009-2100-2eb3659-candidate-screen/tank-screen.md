# Tank screen -- SCREENING ARITHMETIC, NOT EVIDENCE

Method: lumped LC resonance (2 L(f) EM-fitted, C = MIM + N/2 effective cells); no HBT pair loading, no parasitics beyond what the records carry; cell C calibrated on the bn=substrate A/B record (tt, cap_typ, 27 C), endpoints only; no loss/Q model.

Limits: lumped LC only, no HBT loading, known-answer f0 error vs the A/B record +0.33, +0.30 % (bn-tank forward model, Vctrl 0 / 3.3).

374 candidates; 0 pass rows 1 and 2 under this arithmetic.

Best tuning ratio in the grid: 1.1624 (row 2 needs 1.15); if no candidate passes both rows, that is the input the #93 spec-question decision record anticipates -- still screening arithmetic, not a finding.

| rank | inductor | cells_per_side | mim_side_um | mim_ff | f0_vctrl0_ghz | f0_vctrl3p3_ghz | fc_ghz | tuning_ratio | row1_pass | row2_pass | row1_pass_mim_pm10 | row1_margin | row2_margin | score |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | p11 | 14 | 1.14 | 2.132 | 4.768 | 4.25 | 4.501 | 1.122 | True | False | False | 0.0002806 | -0.02448 | -0.02448 |
| 2 | p11 | 14 | 2 | 6.32 | 4.694 | 4.198 | 4.439 | 1.118 | False | False | False | -0.01371 | -0.02751 | -0.02751 |
| 3 | p11 | 12 | 1.14 | 2.132 | 5.041 | 4.513 | 4.77 | 1.117 | True | False | True | 0.05653 | -0.02876 | -0.02876 |
| 4 | p11 | 12 | 2 | 6.32 | 4.955 | 4.451 | 4.696 | 1.113 | True | False | True | 0.04174 | -0.03201 | -0.03201 |
| 5 | p11 | 10 | 1.14 | 2.132 | 5.367 | 4.832 | 5.092 | 1.111 | True | False | True | 0.08006 | -0.0342 | -0.0342 |
| 6 | p11 | 12 | 3 | 13.98 | 4.808 | 4.343 | 4.57 | 1.107 | True | False | True | 0.01525 | -0.03744 | -0.03744 |
| 7 | p13 | 10 | 1.14 | 2.132 | 4.798 | 4.335 | 4.561 | 1.107 | True | False | True | 0.01328 | -0.03755 | -0.03755 |
| 8 | p11 | 10 | 2 | 6.32 | 5.263 | 4.756 | 5.003 | 1.107 | True | False | True | 0.09931 | -0.03768 | -0.03768 |
| 9 | p11 | 14 | 3 | 13.98 | 4.569 | 4.107 | 4.332 | 1.112 | False | False | False | -0.03882 | -0.03264 | -0.03882 |
| 10 | p13 | 10 | 2 | 6.32 | 4.709 | 4.269 | 4.483 | 1.103 | False | False | False | -0.003728 | -0.04082 | -0.04082 |
| 11 | p11 | 8 | 1.14 | 2.132 | 5.765 | 5.229 | 5.491 | 1.102 | True | False | True | 0.001716 | -0.04132 | -0.04132 |
| 12 | p11 | 12 | 3.65 | 20.57 | 4.691 | 4.257 | 4.469 | 1.102 | False | False | False | -0.006967 | -0.04166 | -0.04166 |
| 13 | p11 | 10 | 3 | 13.98 | 5.088 | 4.626 | 4.851 | 1.1 | True | False | True | 0.07243 | -0.04343 | -0.04343 |
| 14 | p13 | 8 | 1.14 | 2.132 | 5.14 | 4.679 | 4.904 | 1.098 | True | False | True | 0.08241 | -0.04483 | -0.04483 |
| 15 | p11 | 8 | 2 | 6.32 | 5.637 | 5.133 | 5.379 | 1.098 | True | False | True | 0.02242 | -0.04503 | -0.04503 |
| 16 | p13 | 10 | 3 | 13.98 | 4.557 | 4.155 | 4.352 | 1.097 | False | False | False | -0.0341 | -0.04623 | -0.04623 |
| 17 | p11 | 12 | 4.5 | 31.1 | 4.522 | 4.129 | 4.321 | 1.095 | False | False | False | -0.04149 | -0.04765 | -0.04765 |
| 18 | p11 | 10 | 3.65 | 20.57 | 4.951 | 4.522 | 4.731 | 1.095 | True | False | True | 0.04891 | -0.04782 | -0.04782 |
| 19 | p13 | 8 | 2 | 6.32 | 5.031 | 4.596 | 4.809 | 1.094 | True | False | True | 0.06416 | -0.04829 | -0.04829 |
| 20 | p11 | 8 | 3 | 13.98 | 5.424 | 4.971 | 5.192 | 1.091 | True | False | True | 0.05924 | -0.05108 | -0.05108 |
| 21 | p13 | 12 | 1.14 | 2.132 | 4.516 | 4.057 | 4.28 | 1.113 | False | False | False | -0.05131 | -0.03197 | -0.05131 |
| 22 | p11 | 16 | 1.14 | 2.132 | 4.534 | 4.028 | 4.273 | 1.126 | False | False | False | -0.05301 | -0.02102 | -0.05301 |
| 23 | p13 | 8 | 3 | 13.98 | 4.847 | 4.455 | 4.647 | 1.088 | True | False | True | 0.03169 | -0.05391 | -0.05391 |
| 24 | p11 | 10 | 4.5 | 31.1 | 4.753 | 4.369 | 4.557 | 1.088 | True | False | True | 0.01249 | -0.054 | -0.054 |
| 25 | p11 | 8 | 3.65 | 20.57 | 5.259 | 4.842 | 5.046 | 1.086 | True | False | True | 0.0899 | -0.05562 | -0.05562 |

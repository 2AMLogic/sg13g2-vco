#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# ihp_deck_categories.py -- STATIC review of which RDB rule categories IHP's
# primary DRC runset (libs.tech/klayout/tech/drc/ihp-sg13g2.drc) declares
# under the invocation layout/drc.sh uses.
#
#   python3 layout/scripts/ihp_deck_categories.py <ihp-sg13g2.drc> \
#       [--facts <facts.json>] [--list]
#
# WHY THIS EXISTS.  `klt drc --engine klayout --expect-rule-categories N`
# only upgrades a zero-finding native-deck run from `coverage_unknown` to
# `clean` when the caller vouches for N.  That N must not be read back off
# the very run being accepted (that would make the assertion a tautology).
# This script derives it from the deck SOURCE instead: it walks the deck's
# `# %include` list, evaluates each included file's switch guards under the
# invocation drc.sh uses, and enumerates every `.output(...)` name the
# reachable code declares -- literal names directly, interpolated names by
# expanding the loop domain the file itself defines (a hash's keys, a %w[]
# list, an array's length).  Every interpolated template must be one this
# script has been reviewed against; an unknown one is a hard error, so a deck
# change cannot silently move the count.
#
# THE INVOCATION MODELLED (and the one drc.sh passes): no switch deck-vars
# beyond `threads` (which gates no rule), so
#   tables = main; FEOL, BEOL, OFFGRID, ANGLE, PIN, FORBIDDEN, RECOMMENDED on;
#   PRECHECK_DRC off; run_mode deep.
# Under those switches every included file's top-level guard is true; the
# only remaining gates are `unless PRECHECK_DRC` / `next if PRECHECK_DRC`
# (taken), `if RECOMMENDED` (taken), `if en_tiles` (wraps no output), and two
# DATA-dependent gates, which this script cannot evaluate from source and
# instead takes as input facts about the stream (--facts, produced by
# layout/scripts/ihp_deck_facts.py):
#   Seal.l  -- declared only when the stream carries an EdgeSeal boundary
#              (39/4) shape (`unless seal_l_l1.is_empty?`, 6_10_sealring.drc)
#   MIM.gR  -- declared only when total MIM (36/0) area exceeds Mim_gR
#              (`if mim_total_area > mim_gr_value.um`, 6_11_mim.drc); i.e.
#              its category only exists when it is ALSO a finding
# Without --facts both are reported as conditional and left out of the
# expected count, which is exact for a stream with neither condition true.
#
# NOT INCLUDED by ihp-sg13g2.drc, hence out of scope of any count derived
# here: rule_decks/density.drc (chip-level density/fill), rule_decks/
# antenna.drc, rule_decks/sg13g2_maximal.drc.  See layout/PROVENANCE.md.
#
# Output: JSON on stdout (or the sorted category list with --list).

import json
import os
import re
import sys

INCLUDE_RE = re.compile(r"^#\s*%include\s+(\S+)\s*$", re.M)
# `.output(` followed (possibly across a newline) by a quoted name.
OUTPUT_RE = re.compile(r"\.output\(\s*(['\"])((?:(?!\1).)*)\1", re.S)

# Every included file's first rule-bearing guard, and why it is true under
# the modelled invocation.  A file whose guard is not in this table is a
# hard error -- it must be reviewed before it can be counted.
GUARD_RE = re.compile(r"^if (.+)$", re.M)
TRUE_GUARDS = {
    "FEOL": "FEOL is on (no $no_feol)",
    "BEOL": "BEOL is on (no $no_beol)",
    "PIN": "PIN is on (no $no_pin)",
    "FORBIDDEN": "FORBIDDEN is on (no $no_forbidden)",
    "(TABLES.include?('main') && OFFGRID)": "tables=main and OFFGRID on",
    "(TABLES.include?('main') && ANGLE)": "tables=main and ANGLE on",
}

# Categories whose declaration depends on the DATA, not the switches.
CONDITIONAL = {
    "Seal.l": {
        "file": "rule_decks/beol/6_10_sealring.drc",
        "declared_when": "the stream carries an EdgeSeal boundary (39/4) "
                         "shape interacting the chip extent",
        "fact": "edgeseal_boundary_shapes",
        "test": lambda f: f["edgeseal_boundary_shapes"] > 0,
    },
    "MIM.gR": {
        "file": "rule_decks/beol/6_11_mim.drc",
        "declared_when": "total MIM (36/0) area exceeds Mim_gR "
                         "(174800 um^2) -- the category only exists when "
                         "it is also a finding",
        "fact": "mim_area_um2",
        "test": lambda f: f["mim_area_um2"] > f["mim_gr_um2"],
    },
}


def strip_comments(src):
    """Drop full-line `#` comments (the decks never put `#` inside a rule
    name; interpolation `#{` only appears inside strings, never at column
    start)."""
    return "\n".join(l for l in src.splitlines()
                     if not l.lstrip().startswith("#"))


def hash_keys(src, const):
    m = re.search(r"\b%s\s*=\s*\{(.*?)\}" % re.escape(const), src, re.S)
    if not m:
        raise SystemExit("review error: hash %s not found" % const)
    return re.findall(r"['\"]([^'\"]+)['\"]\s*=>", m.group(1))


def wlist(src, var):
    m = re.search(r"\b%s\s*=\s*%%w\[([^\]]*)\]" % re.escape(var), src)
    if not m:
        raise SystemExit("review error: %%w list %s not found" % var)
    return m.group(1).split()


def array_len(src, var):
    m = re.search(r"\b%s\s*=\s*\[([^\]]*)\]" % re.escape(var), src, re.S)
    if not m:
        raise SystemExit("review error: array %s not found" % var)
    return len([x for x in m.group(1).split(",") if x.strip()])


def int_assign(src, var):
    m = re.search(r"\b%s\s*=\s*(\d+)\b" % re.escape(var), src)
    if not m:
        raise SystemExit("review error: integer %s not found" % var)
    return int(m.group(1))


def numbered(src, arr, start_var):
    s = int_assign(src, start_var)
    return [str(s + i) for i in range(array_len(src, arr))]


def pad_abbrevs(src):
    m = re.search(r"\bmetals\s*=\s*\[(.*?)\n\s*\]", src, re.S)
    if not m:
        raise SystemExit("review error: pad metals list not found")
    return re.findall(r"\[\s*\w+\s*,\s*'([^']+)'\s*\]", m.group(1))


# Reviewed interpolation templates: (file suffix, template) -> domain.
# The domain is re-parsed from the file each run; only the SHAPE of the loop
# is hard-coded here, after reading it.
TEMPLATES = {
    ("geometry/3_1_offgrid.drc", "#{base_name}_Offgrid"):
        ("base_name", lambda s: hash_keys(s, "OFFGRID_LAYERS")),
    ("geometry/3_2_angle.drc", "#{base_name}_Acute"):
        ("base_name", lambda s: hash_keys(s, "ACUTE_SCOPE_LAYERS")),
    ("geometry/3_2_angle.drc", "#{base_name}_Angle90"):
        ("base_name", lambda s: hash_keys(s, "ORTHO_ONLY_LAYERS")),
    ("geometry/3_2_angle.drc", "#{base_name}_Angle45"):
        ("base_name", lambda s: hash_keys(s, "ORTHO_45_LAYERS")),
    ("beol/5_17_metaln.drc", "M#{met_no}.a"):
        ("met_no", lambda s: numbered(s, "mets_lay", "metal_start_index")),
    ("beol/5_17_metaln.drc", "M#{met_no}.b"):
        ("met_no", lambda s: numbered(s, "mets_lay", "metal_start_index")),
    ("beol/5_17_metaln.drc", "M#{met_no}.e"):
        ("met_no", lambda s: numbered(s, "mets_lay", "metal_start_index")),
    ("beol/5_17_metaln.drc", "M#{met_no}.f"):
        ("met_no", lambda s: numbered(s, "mets_lay", "metal_start_index")),
    ("beol/5_17_metaln.drc", "M#{met_no}.g"):
        ("met_no", lambda s: numbered(s, "mets_lay", "metal_start_index")),
    ("beol/5_17_metaln.drc", "M#{met_no}.i"):
        ("met_no", lambda s: numbered(s, "mets_lay", "metal_start_index")),
    ("beol/5_18_metalnfiller.drc", "M#{metalfiller_no}Fil.c"):
        ("metalfiller_no",
         lambda s: numbered(s, "metalfillers_lay", "metalfiller_start_index")),
    ("beol/5_18_metalnfiller.drc", "M#{metalfiller_no}Fil.a2"):
        ("metalfiller_no",
         lambda s: numbered(s, "metalfillers_lay", "metalfiller_start_index")),
    ("beol/5_20_vian.drc", "V#{via_no}.a"):
        ("via_no", lambda s: numbered(s, "vias_lay", "via_start_index")),
    ("beol/5_20_vian.drc", "V#{via_no}.b"):
        ("via_no", lambda s: numbered(s, "vias_lay", "via_start_index")),
    ("beol/5_20_vian.drc", "V#{via_no}.c"):
        ("via_no", lambda s: numbered(s, "vias_lay", "via_start_index")),
    ("beol/7_3_metalslits.drc", "Slt.e1_#{met_abbrev}"):
        ("met_abbrev", lambda s: wlist(s, "metals_abbrev")),
    ("pin/7_4_pin.drc", "Pin.#{pin_rule}"):
        ("pin_rule", lambda s: wlist(s, "rule_names")),
    ("forbidden/3_2_forbidden.drc", "forbidden.#{forb_lay}"):
        ("forb_lay", lambda s: hash_keys(s, "forb_lays")),
    ("beol/6_10_sealring.drc", "Seal.b_#{seal_b_lay}"):
        ("seal_b_lay", lambda s: wlist(s, "seal_b_names")),
    ("beol/6_9_pad.drc", "Pad.fR_#{met_abbrev}"):
        ("met_abbrev", pad_abbrevs),
}


def enumerate_deck(deck_path, facts=None):
    deck_dir = os.path.dirname(os.path.abspath(deck_path))
    with open(deck_path) as fh:
        top = fh.read()
    if OUTPUT_RE.search(strip_comments(top)):
        raise SystemExit("review error: the top-level deck now declares "
                         "outputs of its own -- re-review")
    includes = INCLUDE_RE.findall(top)
    per_file, cats, conditional, used_templates = [], set(), [], set()
    for inc in includes:
        with open(os.path.join(deck_dir, inc)) as fh:
            raw = fh.read()
        src = strip_comments(raw)
        rel = inc.split("rule_decks/", 1)[-1]
        names = []
        if OUTPUT_RE.search(src):
            g = GUARD_RE.search(src)
            guard = g.group(1).split("||")[-1].strip() if g else None
            if guard not in TRUE_GUARDS:
                raise SystemExit("review error: %s guard %r not reviewed"
                                 % (rel, g.group(1) if g else None))
            for _, name in OUTPUT_RE.findall(src):
                if "#{" not in name:
                    names.append(name)
                    continue
                key = (rel, name)
                if key not in TEMPLATES:
                    raise SystemExit("review error: unreviewed interpolated "
                                     "category %r in %s" % (name, rel))
                used_templates.add(key)
                var, dom = TEMPLATES[key]
                for v in dom(src):
                    names.append(name.replace("#{%s}" % var, v))
        file_cats = []
        for n in dict.fromkeys(names):
            if n in CONDITIONAL:
                c = dict(CONDITIONAL[n])
                test = c.pop("test")
                c["category"] = n
                c["declared_for_this_input"] = (
                    None if facts is None else bool(test(facts)))
                conditional.append(c)
                if facts is not None and test(facts):
                    file_cats.append(n)
            else:
                file_cats.append(n)
        cats.update(file_cats)
        per_file.append({"file": inc, "categories": len(file_cats)})
    unused = set(TEMPLATES) - used_templates
    if unused:
        raise SystemExit("review error: reviewed templates no longer present "
                         "in the deck: %s -- re-review" % sorted(unused))
    return {
        "deck": os.path.basename(deck_path),
        "invocation_modelled": {
            "tables": "main", "FEOL": True, "BEOL": True, "OFFGRID": True,
            "ANGLE": True, "PIN": True, "FORBIDDEN": True,
            "RECOMMENDED": True, "PRECHECK_DRC": False, "run_mode": "deep"},
        "included_files": len(includes),
        "per_file": per_file,
        "conditional_categories": conditional,
        "facts": facts,
        "expected_unique_categories": len(cats),
        "categories": sorted(cats),
    }


def main(argv):
    args = list(argv)
    facts = None
    want_list = "--list" in args
    if want_list:
        args.remove("--list")
    if "--facts" in args:
        i = args.index("--facts")
        with open(args[i + 1]) as fh:
            facts = json.load(fh)
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__ if __doc__ else "usage: ihp_deck_categories.py DECK "
              "[--facts F] [--list]", file=sys.stderr)
        return 2
    rec = enumerate_deck(args[0], facts)
    if want_list:
        print("\n".join(rec["categories"]))
    else:
        json.dump(rec, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

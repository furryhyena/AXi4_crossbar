#!/usr/bin/env python3
# =============================================================================
# cov_text.py - coverage summary as plain text (no browser needed).
#   Reads the reports written by xcrg in sim/cov_report/<group>/ and prints:
#     1. one row per test + TOTAL : functional score, code scores of the RTL
#     2. TOTAL : score of every covergroup
#     3. TOTAL : every functional bin that was never hit
#     4. TOTAL : code coverage of every RTL module (rtl/ files only)
#   Usage: python3 tools/cov_text.py <cov_report_dir> <test1> <test2> ...
#   Called by "make cov"; the same text is saved in sim/cov_report/coverage_summary.txt
# =============================================================================
import os, re, sys, html

def func_txt(d):
    return os.path.join(d, "func", "functionalCoverageReport", "xcrg_func_cov_report.txt")

def code_mod(d):
    # xcrg may put the HTML report in a sub-folder of its own: search for it
    for root, _, files in os.walk(d):
        if "modules.html" in files:
            return os.path.join(root, "modules.html")
    return os.path.join(d, "code", "codeCoverageReport", "modules.html")

def code_log_scores(d):
    # whole-design scores that xcrg prints at the end of its run
    sc = {}
    try:
        for line in open(os.path.join(d, "xcrg_code.log")):
            m = re.search(r"(Line|Statement|Branch|Condition|Toggle) Coverage Score\s+([\d.]+)", line)
            if m: sc[m.group(1)] = float(m.group(2))
    except OSError:
        pass
    if not sc: return None
    return [sc.get("Line", sc.get("Statement")), sc.get("Branch"), sc.get("Condition"), sc.get("Toggle")]

def func_score(d):
    try:
        for line in open(func_txt(d)):
            m = re.search(r"Coverage Score\s*:,\s*([\d.]+)", line)
            if m: return float(m.group(1))
    except OSError:
        pass
    return None

def func_groups(d):
    out, inside = [], False
    try:
        for line in open(func_txt(d)):
            if "Total Summary" in line:       inside = True;  continue
            if "CoverGroups Summary" in line: break
            if not inside or "CgName" in line: continue
            m = re.match(r"\s+(\S[^,]*?)\s*,\s*([\d.]+)\s*,", line)
            if m: out.append((m.group(1), float(m.group(2))))
    except OSError:
        pass
    return out

def func_holes(d):
    holes, where, in_unc = [], "", False
    try:
        for line in open(func_txt(d)):
            m = re.search(r"Cover Point Table for Inst :\s*(.*?),\s*Variable :,\s*(\S+)", line)
            if m:
                where, in_unc = f"{m.group(1)} / {m.group(2)}", False
                continue
            if "Uncovered bins" in line: in_unc = True;  continue
            if "Covered bins" in line:   in_unc = False; continue
            if in_unc:
                parts = [p.strip() for p in line.strip().strip(",").split(",")]
                if len(parts) >= 3 and parts[-2] == "0" and parts[0] not in ("Name",) and "Hit Count" not in line:
                    key = (where, " , ".join(parts[:-2]))
                    if key not in holes: holes.append(key)
    except OSError:
        pass
    return holes

def code_modules(d):
    rows = []
    try:
        s = open(code_mod(d)).read()
    except OSError:
        return rows
    for tr in re.findall(r"<tr>(.*?)</tr>", s, re.S):
        cells = re.findall(r"<td class='moduleInfosTable'>(.*?)</td>", tr, re.S)
        if len(cells) < 9: continue
        txt = [html.unescape(re.sub(r"<[^>]+>", " ", c)).strip() for c in cells]
        path = re.search(r"tooltiptext'>\s*(\S+)", cells[8])
        path = path.group(1) if path else txt[8]
        try:
            sc = [float(x) for x in txt[4:8]]
        except ValueError:
            continue
        rows.append((txt[1], int(txt[2] or 0), path, sc))
    return rows

def rtl_avg(d):
    mods = [m for m in code_modules(d) if "/rtl/" in m[2]]
    if not mods: return None
    return [sum(m[3][i] for m in mods) / len(mods) for i in range(4)]

def code_cols(d):
    # RTL modules only when the module table is found, else xcrg's whole-design score
    c = rtl_avg(d)
    if c: return c, "rtl"
    c = code_log_scores(d)
    if c: return c, "all"
    return [None] * 4, ""

def fmt(x):
    return "n/a" if x is None else f"{x:.1f}"

def main():
    rep, tests = sys.argv[1], sys.argv[2:]
    groups = [t for t in tests if os.path.isdir(os.path.join(rep, t))] + ["TOTAL"]
    L = []
    L.append("=" * 86)
    L.append(" COVERAGE SUMMARY   (each test = all its seeds merged, TOTAL = all runs merged)")
    L.append(" code columns: RTL modules only (average), or * = whole design incl. testbench (from xcrg log)")
    L.append("=" * 86)
    L.append(f"{'TEST':<26}{'FUNC %':>10}{'STMT %':>10}{'BRANCH %':>10}{'COND %':>10}{'TOGGLE %':>10}")
    for g in groups:
        d = os.path.join(rep, g)
        c, kind = code_cols(d)
        star = "*" if kind == "all" else ""
        if g == "TOTAL": L.append("-" * 86)
        L.append(f"{g:<26}{fmt(func_score(d)):>10}" + "".join(f"{fmt(x) + star:>10}" for x in c))
    tot = os.path.join(rep, "TOTAL")

    L.append("")
    L.append(" COVERGROUPS (TOTAL)")
    for name, sc in func_groups(tot):
        L.append(f"   {sc:6.1f} %   {name}")

    holes = func_holes(tot)
    L.append("")
    L.append(f" FUNCTIONAL BINS NEVER HIT (TOTAL): {len(holes)}")
    for where, b in holes:
        L.append(f"   {where:<46} {b}")

    mods = [m for m in code_modules(tot) if "/rtl/" in m[2]]
    L.append("")
    L.append(" CODE COVERAGE PER RTL MODULE (TOTAL)")
    L.append(f"   {'MODULE':<30}{'INST':>5}{'STMT %':>9}{'BRANCH %':>10}{'COND %':>9}{'TOGGLE %':>10}")
    for name, n, _, sc in mods:
        L.append(f"   {name:<30}{n:>5}" + f"{sc[0]:>9.1f}{sc[1]:>10.1f}{sc[2]:>9.1f}{sc[3]:>10.1f}")
    if not mods:
        L.append("   (module table modules.html not found; the * numbers above come from the xcrg log)")
        L.append("   to find the HTML report:  find sim/cov_report/TOTAL -name '*.html'")
    L.append("")
    L.append(" details in text : sim/cov_report/TOTAL/func/functionalCoverageReport/xcrg_func_cov_report.txt")
    text = "\n".join(L)
    print(text)
    open(os.path.join(rep, "coverage_summary.txt"), "w").write(text + "\n")

if __name__ == "__main__":
    main()

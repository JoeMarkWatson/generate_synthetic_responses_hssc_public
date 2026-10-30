#!/usr/bin/env python3
"""Export saved paired comparisons to Appendix Table G1 (Python standard library).

Run from any directory: python scripts/create_table_g1.py
No raw Monte Carlo results, human records, models or statistical tests are read/run.
XLSX is read/written as standard Office Open XML; no Excel dependency is needed.
CSV retains source precision (including CI bounds); Excel displays four decimals.
"""
import argparse
import csv
import hashlib
import posixpath
from decimal import Decimal
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
SCALES = ['Extraversion', 'Openness', 'Neuroticism', 'Agreeableness',
          'Conscientiousness', 'Work Conscientiousness', 'Work Honesty–Humility']
METRICS = ['pearson_r', 'spearman_r']
FIELDS = ['mean_diff', 'ci_lower', 'ci_upper', 'p_holm', 'valid_paired_repetitions']
NOTE = ('Note. All synthetic methods use no_detail_variation. Differences are synthetic minus '
        'human reference: full-human calibration for the Big Five-based scales and human224 '
        'for workplace scales. Validity uses raw sum scores: held-out same-trait item sums for '
        'the Big Five and external convergent criteria for workplace scales. Mean paired '
        'differences, pointwise 95% confidence intervals and Holm-adjusted p-values are copied '
        'from saved paired comparisons; no tests or multiplicity adjustments are recomputed. '
        'Holm adjustments retain the original analysis comparison families. n counts valid '
        'paired Monte Carlo repetitions; unsuccessful pairs are omitted, never zero-filled. '
        'Confidence intervals are not multiplicity-adjusted. Source audit preserves full '
        'precision; CSV also retains full precision. Positive differences favour synthetic selection.')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def only(rows, **criteria):
    selected = [r for r in rows if all(r.get(k) == v for k, v in criteria.items())]
    require(len(selected) == 1, f'Expected one source row for {criteria}; found {len(selected)}')
    return selected[0]


def csv_rows(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        return [dict(r, _row=i) for i, r in enumerate(csv.DictReader(f), 2)]


def workbook_rows(path, sheet):
    """Read cell addresses, shared/inline strings, and numeric source text faithfully."""
    with ZipFile(path) as z:
        wb = ET.fromstring(z.read('xl/workbook.xml'))
        matches = [s for s in wb.findall(f'{{{NS}}}sheets/{{{NS}}}sheet') if s.get('name') == sheet]
        require(len(matches) == 1, f'{path}: missing/ambiguous sheet {sheet}')
        links = {r.get('Id'): r.get('Target') for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
        target = links[matches[0].get(f'{{{REL}}}id')]
        target = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
        strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            strings = [''.join(n.itertext()) for n in ET.fromstring(z.read('xl/sharedStrings.xml')).findall(f'{{{NS}}}si')]
        rows = []
        for row in ET.fromstring(z.read(target)).findall(f'{{{NS}}}sheetData/{{{NS}}}row'):
            cells = {}
            for cell in row.findall(f'{{{NS}}}c'):
                address = cell.get('r').rstrip('0123456789')
                value = cell.find(f'{{{NS}}}v')
                text = value.text if value is not None else ''
                if cell.get('t') == 's':
                    text = strings[int(text)]
                elif cell.get('t') == 'inlineStr':
                    text = ''.join(cell.find(f'{{{NS}}}is').itertext())
                require(cell.find(f'{{{NS}}}f') is None, f'Unexpected source formula: {path}/{sheet}/{cell.get("r")}')
                cells[address] = text
            rows.append((int(row.get('r')), cells))
        headers = rows[0][1]
        return [dict({label: cells.get(col, '') for col, label in headers.items()}, _row=index)
                for index, cells in rows[1:] if any(cells.values())]


def collect():
    base = ROOT / 'evaluate_resps'
    efile = base / 'monte_carlo_study1_output/monte_carlo_comparisons.xlsx'
    esheet = 'Held-out validity'
    erows = workbook_rows(efile, esheet)
    # The Study 1 workbook does not contain a scale column. Confirm its identity
    # using companion aggregate metadata and cross-check every extracted statistic
    # against the companion Monte Carlo summary (not against marginal correlations).
    identity = base / 'monte_carlo_study1_output/retrospective_alpha_summary.csv'
    require({r['scale'] for r in csv_rows(identity)} == {'Extraversion'}, 'Study 1 scale identity mismatch')
    esummary = csv_rows(base / 'monte_carlo_study1_output/monte_carlo_summary.csv')
    afile = base / 'monte_carlo_study2a_output/cross_scale_summary.csv'
    arows = csv_rows(afile)
    records, audit = [], []
    for scale in SCALES:
        models = ['DeepSeek', 'OpenAI', 'Claude', 'Xiaomi'] if scale == 'Extraversion' else ['OpenAI', 'Xiaomi']
        for model in models:
            method = ('v2.1.1_no_detail_variation' if model == 'DeepSeek'
                      else model.lower() + '_no_detail_variation')
            result = {'scale': scale, 'model': model}
            for metric in METRICS:
                if scale == 'Extraversion':
                    path, sheet, reference = efile, esheet, 'reference'
                    row = only(erows, method=method)
                    require(row['scoring method'] == 'SUM_SCORE', 'Study 1 is not raw-sum validity')
                    prefix = metric.replace('_', ' ') + ' vs reference '
                    columns = [prefix + suffix for suffix in ['mean difference', 'ci lower', 'ci upper',
                               'Holm adjusted p', 'valid paired repetitions']]
                    raw = [row[c] for c in columns]
                    check = only(esummary, stage='short_form_evaluation', method=method)
                    require(check['scoring_method'] == 'SUM_SCORE', 'Study 1 summary scoring mismatch')
                    require(all(Decimal(v) == Decimal(check[metric + '_vs_reference_' + f])
                                for v, f in zip(raw, FIELDS)), 'Study 1 workbook/summary statistics disagree')
                    identity_source = str(identity.relative_to(ROOT))
                elif scale in SCALES[1:5]:
                    path, sheet, reference = afile, '(CSV)', 'reference'
                    row = only(arows, stage='short_form_evaluation', scale=scale, method=method)
                    require(row['scoring_method'] == 'SUM_SCORE', f'{scale}: not raw-sum validity')
                    columns = [metric + '_vs_reference_' + f for f in FIELDS]
                    raw = [row[c] for c in columns]
                    identity_source = 'scale column in source'
                else:
                    slug = {'Work Conscientiousness': 'Work_conscientiousness',
                            'Work Honesty–Humility': 'Work_honesty_humility'}[scale]
                    path = base / 'monte_carlo_study2b_output' / slug / 'monte_carlo_comparisons.xlsx'
                    sheet, reference = 'Convergent validity', 'human224'
                    rows = workbook_rows(path, sheet)
                    require({r['scale'] for r in rows} == {slug}, f'{path}: scale identity mismatch')
                    row = only(rows, scale=slug, stage='short_form_evaluation', metric=metric,
                               method=method, comparison='vs_human224')
                    columns = FIELDS
                    raw = [row[c] for c in columns]
                    identity_source = 'scale column in source'
                values = [Decimal(v) for v in raw]
                require(all(v.is_finite() for v in values), f'{scale}/{model}/{metric}: missing/nonfinite result')
                d, low, high, p, n = values
                require(low <= d <= high and 0 <= p <= 1 and n == int(n) and n > 1,
                        f'{scale}/{model}/{metric}: invalid paired statistics')
                result[metric] = values
                audit.append([str(path.relative_to(ROOT)), sheet, row['_row'], scale, model, method,
                              metric, 'vs_' + reference, reference, identity_source,
                              ', '.join(columns), *values, hashlib.sha256(path.read_bytes()).hexdigest()])
            records.append(result)
    validate(records)
    return records, audit


def validate(records):
    require(len(records) == 16 and len({(r['scale'], r['model']) for r in records}) == 16,
            'Expected exactly 16 distinct model–scale combinations')
    require(all(set(METRICS) <= r.keys() for r in records), 'Missing validity metric')
    e = [r for r in records if r['scale'] == 'Extraversion']
    require(abs(min(r['pearson_r'][0] for r in e) - Decimal('.0068')) <= Decimal('.00005')
            and abs(max(r['pearson_r'][0] for r in e) - Decimal('.0125')) <= Decimal('.00005')
            and all(r['pearson_r'][3] < Decimal('.001') for r in e), 'Known Extraversion check failed')
    a = [r for r in records if r['scale'] in SCALES[1:5]]
    require(len(a) == 8 and all(r['pearson_r'][0] > 0 and r['pearson_r'][3] <= Decimal('.010') for r in a),
            'Known additional Big Five Pearson check failed')
    checks = [('Work Conscientiousness', 'OpenAI', 'pearson_r', 0, '.0701', '.00005'),
              ('Work Conscientiousness', 'Xiaomi', 'pearson_r', 0, '.0963', '.00005'),
              ('Work Honesty–Humility', 'OpenAI', 'pearson_r', 0, '-.0033', '.00005'),
              ('Work Honesty–Humility', 'OpenAI', 'pearson_r', 3, '.116', '.0005'),
              ('Work Honesty–Humility', 'OpenAI', 'spearman_r', 0, '.0313', '.00005'),
              ('Work Honesty–Humility', 'Xiaomi', 'pearson_r', 0, '-.0127', '.00005'),
              ('Work Honesty–Humility', 'Xiaomi', 'spearman_r', 0, '.0045', '.00005'),
              ('Work Honesty–Humility', 'Xiaomi', 'spearman_r', 3, '.069', '.0005')]
    for scale, model, metric, index, expected, tolerance in checks:
        actual = only(records, scale=scale, model=model)[metric][index]
        require(abs(actual - Decimal(expected)) <= Decimal(tolerance),
                f'Known-result check failed: {scale}/{model}/{metric}/{FIELDS[index]}: {actual}; expected approximately {expected}')


def colname(n):
    result = ''
    while n:
        n, rem = divmod(n - 1, 26)
        result = chr(65 + rem) + result
    return result


def worksheet(rows, widths, publication=False):
    sheet = ET.Element('worksheet', xmlns=NS)
    views = ET.SubElement(sheet, 'sheetViews')
    view = ET.SubElement(views, 'sheetView', workbookViewId='0', showGridLines='0')
    ET.SubElement(view, 'pane', ySplit='3' if publication else '1', topLeftCell='A4' if publication else 'A2', state='frozen')
    cols = ET.SubElement(sheet, 'cols')
    for i, width in enumerate(widths, 1):
        ET.SubElement(cols, 'col', min=str(i), max=str(i), width=str(width), customWidth='1')
    data = ET.SubElement(sheet, 'sheetData')
    last_scale = None
    for i, values in enumerate(rows, 1):
        attrs = {'r': str(i)}
        if publication:
            attrs.update(ht=str(30 if i == 1 else 42 if i == 3 else 105 if i == len(rows) else 24), customHeight='1')
        row = ET.SubElement(data, 'row', attrs)
        for j, value in enumerate(values, 1):
            style = 0
            if publication:
                style = 1 if i == 1 else 2 if i == 3 else 6 if i == len(rows) else 3
                if 4 <= i < len(rows) and j in (3, 6): style = 4
                if 4 <= i < len(rows) and j in (5, 8): style = 5
            elif i == 1: style = 2
            cell = ET.SubElement(row, 'c', r=colname(j) + str(i), s=str(style))
            if isinstance(value, (int, Decimal)):
                ET.SubElement(cell, 'v').text = str(value)
            else:
                cell.set('t', 'inlineStr')
                ET.SubElement(ET.SubElement(cell, 'is'), 't').text = str(value)
    if publication:
        merges = ET.SubElement(sheet, 'mergeCells', count='2')
        ET.SubElement(merges, 'mergeCell', ref=f'A1:{colname(len(widths))}1')
        ET.SubElement(merges, 'mergeCell', ref=f'A{len(rows)}:{colname(len(widths))}{len(rows)}')
    else:
        ET.SubElement(sheet, 'autoFilter', ref=f'A1:{colname(len(widths))}{len(rows)}')
    ET.SubElement(sheet, 'pageMargins', left='.3', right='.3', top='.4', bottom='.4', header='.2', footer='.2')
    ET.SubElement(sheet, 'pageSetup', orientation='landscape', paperSize='9', fitToWidth='1', fitToHeight='1')
    return ET.tostring(sheet, encoding='utf-8', xml_declaration=True)


STYLES = '''<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="0.0000;-0.0000;0.0000"/><numFmt numFmtId="165" formatCode="[&lt;0.001]&quot;&lt; .001&quot;;0.000"/></numFmts>
<fonts count="3"><font><sz val="11"/><name val="Arial"/><color rgb="FF000000"/></font><font><b/><sz val="12"/><name val="Arial"/><color rgb="FF000000"/></font><font><i/><sz val="10"/><name val="Arial"/><color rgb="FF000000"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFECEFF1"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border/><border><bottom style="thin"><color rgb="FF000000"/></bottom></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" applyNumberFormat="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'''


def write_workbook(path, rows, audit, widths):
    content = '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'''
    for i in (1, 2):
        content += f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    content += '</Types>'
    audit_headers = ['Source file', 'Source sheet', 'Source row', 'Scale', 'Model', 'Method', 'Metric',
                     'Comparison identifier', 'Reference', 'Scale identity evidence', 'Source columns',
                     'Mean paired difference', 'CI lower', 'CI upper', 'Holm-adjusted p', 'Paired repetitions', 'Source SHA256']
    with ZipFile(path, 'w', ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', content)
        z.writestr('_rels/.rels', f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{REL}/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml', f'<workbook xmlns="{NS}" xmlns:r="{REL}"><sheets><sheet name="Table G1" sheetId="1" r:id="rId1"/><sheet name="Source audit" sheetId="2" r:id="rId2"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels', f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{REL}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="{REL}/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="{REL}/styles" Target="styles.xml"/></Relationships>')
        z.writestr('xl/styles.xml', STYLES)
        z.writestr('xl/worksheets/sheet1.xml', worksheet(rows, widths, True))
        z.writestr('xl/worksheets/sheet2.xml', worksheet([audit_headers] + audit, [70, 24, 12, 28, 14, 38, 18, 20, 16, 60, 80, 24, 24, 24, 24, 18, 68]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'tables')
    args = parser.parse_args()
    records, audit = collect()  # All extraction and known-result checks precede writing.
    separate_n = any(r['pearson_r'][4] != r['spearman_r'][4] for r in records)
    headers = ['Scale', 'Model', 'Pearson Δr', 'Pearson 95% CI', 'Pearson Holm-adjusted p',
               'Spearman Δρ', 'Spearman 95% CI', 'Spearman Holm-adjusted p']
    headers += ['Pearson paired repetitions (n)', 'Spearman paired repetitions (n)'] if separate_n else ['Paired repetitions (n)']
    display, full = [], []
    for r in records:
        drow, frow = [r['scale'], r['model']], [r['scale'], r['model']]
        for metric in METRICS:
            d, lo, hi, p, n = r[metric]
            drow += [d, f'[{lo:.4f}, {hi:.4f}]', p]
            frow += [d, f'[{lo}, {hi}]', p]
        counts = [int(r[m][4]) for m in METRICS]
        drow += counts if separate_n else counts[:1]
        frow += counts if separate_n else counts[:1]
        display.append(drow)
        full.append(frow)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    xlsx = args.output_dir / 'table_g1_validity.xlsx'
    csv_path = args.output_dir / 'table_g1_validity.csv'
    title = 'Appendix Table G1. Paired comparisons of synthetic and human-reference short-form validity across seven scales'
    write_workbook(xlsx, [[title], [], headers] + display + [[NOTE]], audit,
                   [29, 14, 15, 25, 19, 15, 25, 19] + ([18, 18] if separate_n else [18]))
    with csv_path.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(full)
    # Round-trip the written values against source precision, including all 32 CIs/p-values.
    back = workbook_rows(xlsx, 'Source audit')
    require(len(back) == 32, 'Audit round-trip count failed')
    for row, original in zip(back, audit):
        for key, value in zip(['Mean paired difference', 'CI lower', 'CI upper', 'Holm-adjusted p', 'Paired repetitions'], original[11:16]):
            require(Decimal(row[key]) == value, f'Excel round-trip changed {key}')
    require(len(csv_rows(csv_path)) == 16, 'CSV round-trip count failed')
    print('PASS: 16 model–scale combinations; both metrics; 32 source comparisons; all known-result checks.')
    print('PASS: reference identifiers, source precision and Excel/CSV round-trip checks.')
    print('Paired n: 495 for Work Conscientiousness; 500 for other scales.' if
          all(r[m][4] == (495 if r['scale'] == 'Work Conscientiousness' else 500) for r in records for m in METRICS)
          else 'Paired n differs from the usual 495/500 pattern; inspect Source audit.')
    print('Sources:')
    for source in dict.fromkeys(row[0] for row in audit): print(' ', source)
    print('Outputs:', xlsx, csv_path, sep='\n  ')


if __name__ == '__main__':
    main()

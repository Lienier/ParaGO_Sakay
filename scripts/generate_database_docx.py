from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile


SOURCE = Path("docs/PARAGO_MYSQL_STYLE_DATABASE_TABLES.md")
OUTPUT = Path("docs/PARAGO_MYSQL_STYLE_DATABASE_TABLES.docx")


def run(text, bold=False, size=20, color=None):
    props = [f'<w:sz w:val="{size}"/>', f'<w:szCs w:val="{size}"/>']
    if bold:
        props.append("<w:b/>")
    if color:
        props.append(f'<w:color w:val="{color}"/>')
    return f'<w:r><w:rPr>{"".join(props)}</w:rPr><w:t xml:space="preserve">{escape(text)}</w:t></w:r>'


def paragraph(text="", bold=False, size=20, color=None):
    return f'<w:p><w:pPr><w:spacing w:after="100"/></w:pPr>{run(text, bold, size, color)}</w:p>'


def table(rows):
    if not rows:
        return ""
    cols = max(len(row) for row in rows)
    grid = "".join('<w:gridCol w:w="2200"/>' for _ in range(cols))
    xml = [f'<w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="6"/><w:left w:val="single" w:sz="6"/><w:bottom w:val="single" w:sz="6"/><w:right w:val="single" w:sz="6"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr><w:tblGrid>{grid}</w:tblGrid>']
    for row_no, row in enumerate(rows):
        xml.append("<w:tr>")
        for value in row + [""] * (cols - len(row)):
            shade = '<w:shd w:fill="1F4E78"/>' if row_no == 0 else ""
            text_color = "FFFFFF" if row_no == 0 else None
            xml.append(f'<w:tc><w:tcPr>{shade}<w:tcW w:w="2200" w:type="dxa"/></w:tcPr><w:p>{run(value, row_no == 0, 16, text_color)}</w:p></w:tc>')
        xml.append("</w:tr>")
    xml.append("</w:tbl>")
    return "".join(xml)


def document(markdown):
    body = []
    lines = markdown.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("| "):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [cell.strip().replace("`", "") for cell in lines[i].strip().strip("|").split("|")]
                if not all(set(cell) <= set("-:") for cell in cells):
                    rows.append(cells)
                i += 1
            body.append(table(rows))
            continue
        if line.startswith(">"):
            body.append(paragraph(line.lstrip("> "), size=18, color="666666"))
        elif line.startswith("# "):
            body.append(paragraph(line[2:], True, 34, "1F4E78"))
        elif line.startswith("## "):
            body.append(paragraph(line[3:], True, 27, "1F4E78"))
        elif line.startswith("### "):
            body.append(paragraph(line[4:], True, 23, "2F75B5"))
        elif line.startswith("-"):
            body.append(paragraph("• " + line[1:].strip(), size=18))
        else:
            body.append(paragraph(line.replace("**", "").replace("`", ""), size=18))
        i += 1
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>''' + "".join(body) + '''<w:sectPr><w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/></w:sectPr></w:body></w:document>'''


def main():
    content_types = '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'''
    rels = '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'''
    with ZipFile(OUTPUT, "w", ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", rels)
        archive.writestr("word/document.xml", document(SOURCE.read_text(encoding="utf-8")))
    print(OUTPUT)


if __name__ == "__main__":
    main()

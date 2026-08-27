#!/usr/bin/env python3
"""Convert a .docx specification into Markdown, preserving structure verbatim.

Written for the two source documents in docs/source/. It handles what those documents
actually use — Title and Heading styles, a CodeBlock style carrying ASCII diagrams and
GDScript, tables, and the soft line breaks that hold multi-line blocks together — and
nothing else. It changes no wording.

Usage:
    python3 tools/docx_to_markdown.py docs/source/implementation-plan.docx > docs/implementation-plan.md

Standard library only; no dependency to install before the docs can be regenerated.
"""

import sys
import xml.etree.ElementTree as ET
import zipfile

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def para_text(p):
	"""Text of one paragraph, with <w:br/> kept as a real newline.

	The source documents build their ASCII trees as a single paragraph of soft breaks,
	so dropping these collapses every diagram in the file onto one line.
	"""
	out = []
	for node in p.iter():
		if node.tag == W + "t":
			out.append(node.text or "")
		elif node.tag in (W + "br", W + "cr"):
			out.append("\n")
		elif node.tag == W + "tab":
			out.append("    ")
	return "".join(out)


def para_style(p):
	pPr = p.find(W + "pPr")
	if pPr is None:
		return ""
	style = pPr.find(W + "pStyle")
	return style.get(W + "val") if style is not None else ""


def cell_text(tc):
	return " ".join(para_text(p).replace("\n", " ").strip() for p in tc.findall(W + "p")).strip()


def render_table(tbl):
	rows = []
	for tr in tbl.findall(W + "tr"):
		rows.append([cell_text(tc).replace("|", "\\|") for tc in tr.findall(W + "tc")])
	if not rows:
		return ""
	width = max(len(row) for row in rows)
	rows = [row + [""] * (width - len(row)) for row in rows]
	lines = ["| " + " | ".join(rows[0]) + " |", "| " + " | ".join(["---"] * width) + " |"]
	for row in rows[1:]:
		lines.append("| " + " | ".join(row) + " |")
	return "\n".join(lines)


def convert(path):
	with zipfile.ZipFile(path) as archive:
		root = ET.fromstring(archive.read("word/document.xml"))
	blocks = []
	for child in root.find(W + "body"):
		if child.tag == W + "p":
			style = para_style(child)
			text = para_text(child)
			if not text.strip():
				continue
			if style == "Title":
				blocks.append("# " + text.strip())
			elif style.startswith("Heading"):
				# Word's Heading1 is the document's section level, below its Title.
				level = int("".join(c for c in style if c.isdigit()) or 1)
				blocks.append("#" * (level + 1) + " " + text.strip())
			elif style == "CodeBlock":
				blocks.append("```\n" + text.strip("\n").rstrip() + "\n```")
			else:
				blocks.append(text.strip())
		elif child.tag == W + "tbl":
			blocks.append(render_table(child))
	return "\n\n".join(blocks) + "\n"


def main(argv):
	if len(argv) != 2:
		sys.stderr.write("usage: docx_to_markdown.py <file.docx>\n")
		return 2
	sys.stdout.write(convert(argv[1]))
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))

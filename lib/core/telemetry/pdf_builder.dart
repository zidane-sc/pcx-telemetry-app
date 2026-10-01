/// Minimal single-page PDF writer for the ride report.
///
/// Zero dependencies on purpose. The `printing` package would pull a native
/// PDF renderer and a platform channel for a document that is a column of text
/// rows; a map image or chart are the only things that would need real
/// rendering and neither is in the report yet. A hand-rolled writer keeps the
/// APK at its current 8.3 MB and the CI build at its current time.
///
/// `ponytail:` one page, Helvetica, WinAnsi encoding, no compression. Latin-1
/// covers Indonesian and the degree sign; an em-dash or any CJK glyph will not
/// render. Upgrade to an embedded font or a real renderer only when the report
/// grows a chart, a map, or non-Latin text.
class PdfReport {
  final StringBuffer _body = StringBuffer();

  static const double _pageWidth = 595.0; // A4 at 72 dpi
  static const double _pageHeight = 842.0;
  static const double _margin = 44.0;
  static const double _usableWidth = _pageWidth - _margin * 2;

  double _y = _pageHeight - _margin;

  /// Draws one text run at the cursor, advancing downward.
  ///
  /// Returns false when the line would fall below the bottom margin, so the
  /// report code decides what to do rather than having the builder reflow
  /// invisibly.
  bool line(
    String value,
    double size, {
    bool bold = false,
    PdfColor color = PdfColor.black,
    double indent = 0.0,
    double? x,
    double spaceAfter = 3.0,
  }) {
    final lineHeight = size * 1.42;
    if (_y - lineHeight < _margin) return false;
    _y -= lineHeight;

    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');

    _body.writeln('BT');
    _body.writeln('${bold ? '/F2' : '/F1'} ${_fmt(size)} Tf');
    _body.writeln('${_fmt(color.r)} ${_fmt(color.g)} ${_fmt(color.b)} rg');
    _body.writeln('1 0 0 1 ${_fmt(x ?? (_margin + indent))} ${_fmt(_y)} Tm');
    _body.writeln('($escaped) Tj');
    _body.writeln('ET');

    _y -= spaceAfter;
    return true;
  }

  /// A label/value pair on one baseline, with the value right-aligned to the
  /// right margin. That alignment is what makes a column of rows scannable.
  bool row(String label, String value, {PdfColor? valueColor, double size = 10}) {
    final lineHeight = size * 1.42;
    if (_y - lineHeight < _margin) return false;
    _y -= lineHeight;

    // Helvetica averages ~0.5 em per character; this estimate is only used to
    // choose the value's x, and a few points of error is invisible at 10 pt.
    final valueWidth = value.length * size * 0.5;
    final valueX = _pageWidth - _margin - valueWidth;

    _text(value, size, bold: true, x: valueX, color: valueColor ?? PdfColor.black);
    _text(label, size, bold: false, x: _margin, color: PdfColor.grey);

    _y -= 3.0;
    return true;
  }

  void _text(
    String value,
    double size, {
    bool bold = false,
    required double x,
    required PdfColor color,
  }) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    _body.writeln('BT');
    _body.writeln('${bold ? '/F2' : '/F1'} ${_fmt(size)} Tf');
    _body.writeln('${_fmt(color.r)} ${_fmt(color.g)} ${_fmt(color.b)} rg');
    _body.writeln('1 0 0 1 ${_fmt(x)} ${_fmt(_y)} Tm');
    _body.writeln('($escaped) Tj');
    _body.writeln('ET');
  }

  /// A horizontal rule, the divider between report sections.
  void rule({double spaceAfter = 10.0}) {
    _y -= spaceAfter;
    _body.writeln('q');
    _body.writeln('0.82 0.84 0.86 RG');
    _body.writeln('0.7 w');
    _body.writeln('${_fmt(_margin)} ${_fmt(_y)} m '
        '${_fmt(_pageWidth - _margin)} ${_fmt(_y)} l S');
    _body.writeln('Q');
    _y -= spaceAfter;
  }

  /// A filled rectangle. Used for the cyan title accent bar.
  void bar(double x, double y, double w, double h, PdfColor color) {
    _body.writeln('q');
    _body.writeln('${_fmt(color.r)} ${_fmt(color.g)} ${_fmt(color.b)} rg');
    _body.writeln('${_fmt(x)} ${_fmt(y)} ${_fmt(w)} ${_fmt(h)} re f');
    _body.writeln('Q');
  }

  /// A simple progress bar: `value` of `total`, with the fill in [fill].
  void meter({
    required double value,
    required double total,
    required PdfColor fill,
    double barHeight = 7.0,
    double spaceAfter = 10.0,
  }) {
    final ratio = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    _y -= 4;
    bar(_margin, _y - barHeight, _usableWidth, barHeight, const PdfColor(0.9, 0.91, 0.92));
    if (ratio > 0) {
      bar(_margin, _y - barHeight, _usableWidth * ratio, barHeight, fill);
    }
    _y -= spaceAfter;
  }

  bool get hasRoom => _y - _margin > 40.0;

  /// Assembles the finished PDF.
  ///
  /// The xref table records a byte offset per indirect object, so the writer
  /// measures as it goes rather than composing strings and guessing lengths —
  /// a wrong offset makes the file unopenable, not merely ugly.
  List<int> build() {
    final bytes = <int>[];
    final offsets = <int, int>{};
    var pos = 0;

    void write(String s) {
      for (final c in s.codeUnits) {
        bytes.add(c);
      }
      pos += s.length;
    }

    void obj(int num, String body) {
      offsets[num] = pos;
      final header = '$num 0 obj\n';
      write(header);
      write(body);
      write('\nendobj\n');
    }

    // A binary comment marks the file as containing 8-bit data.
    final header = '%PDF-1.4\n';
    write(header);
    final marker = '%\xE2\xE3\xCF\xD3\n';
    for (final c in marker.codeUnits) {
      bytes.add(c);
    }
    pos += marker.length;

    // 1 catalog, 2 pages, 3 page, 4 F1, 5 F2, 6 content stream.
    obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
    obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    obj(
        3,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_fmt(_pageWidth)} ${_fmt(_pageHeight)}] '
            '/Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> '
            '/Contents 6 0 R >>');
    obj(4,
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    obj(
        5,
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');

    final stream = _body.toString();
    offsets[6] = pos;
    write('6 0 obj\n<< /Length ${stream.length} >>\nstream\n$stream\nendstream\nendobj\n');

    final total = 7;
    var xref = 'xref\n0 $total\n0000000000 65535 f \n';
    for (var i = 1; i < total; i++) {
      xref += '${(offsets[i] ?? 0).toString().padLeft(10, '0')} 00000 n \n';
    }

    // startxref must point at the *xref* keyword, so capture its offset before
    // writing it. Recording it afterwards yields the trailer's offset, and the
    // file then fails to open with no error at build time.
    final xrefPos = pos;
    write(xref);

    write('trailer\n<< /Size $total /Root 1 0 R >>\n');
    write('startxref\n$xrefPos\n%%EOF\n');

    return bytes;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

/// Report colours. Kept as a class of constants rather than an enum so the
/// `const` constructor stays usable at call sites.
class PdfColor {
  final double r, g, b;
  const PdfColor(this.r, this.g, this.b);

  static const black = PdfColor(0.10, 0.11, 0.13);
  static const grey = PdfColor(0.45, 0.47, 0.50);
  static const cyan = PdfColor(0.00, 0.72, 0.83);
  static const amber = PdfColor(0.80, 0.58, 0.00);
  static const red = PdfColor(0.85, 0.24, 0.24);
}
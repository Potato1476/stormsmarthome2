#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Báo cáo PDF: Apache Storm — Monolithic vs Fog Computing (IoT Smart Home).
Triết lý thiết kế: "Telemetric Clarity" (results/design_philosophy.md).
Tác giả: Nguyễn Gia Bảo · 09/06/2026
"""
import os
from PIL import Image as PILImage
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Image,
                                Table, TableStyle, PageBreak, HRFlowable,
                                KeepTogether)
from reportlab.platypus.tableofcontents import TableOfContents

# ── Đường dẫn ────────────────────────────────────────────────────────────────
ROOT = "/Users/nguyenbao/stormsmarthome2"
IMG  = os.path.join(ROOT, "results", "grafana-screenshots")
OUT  = os.path.join(ROOT, "results", "report_fog_vs_mono.pdf")
FONT = "/Library/Fonts/Arial Unicode.ttf"

# ── Font ─────────────────────────────────────────────────────────────────────
pdfmetrics.registerFont(TTFont("VN", FONT))
pdfmetrics.registerFontFamily("VN", normal="VN", bold="VN", italic="VN", boldItalic="VN")

# ── Palette (Telemetric Clarity) ─────────────────────────────────────────────
NAVY    = colors.HexColor("#1a365d")
BLUE    = colors.HexColor("#2c5282")
INK     = colors.HexColor("#1a202c")
GREY    = colors.HexColor("#555555")
LIGHT   = colors.HexColor("#f8f9fa")
GOOD    = colors.HexColor("#d4edda")
GOODTX  = colors.HexColor("#1e7e34")
BAD     = colors.HexColor("#f8d7da")
RULE    = colors.HexColor("#cbd5e0")
ACCENT  = colors.HexColor("#3182ce")

# ── Styles ───────────────────────────────────────────────────────────────────
ss = getSampleStyleSheet()
def style(name, **kw):
    base = dict(fontName="VN", textColor=INK, leading=14, fontSize=10.5)
    base.update(kw)
    return ParagraphStyle(name, **base)

S_BODY  = style("body", fontSize=10.5, leading=15.5, alignment=TA_JUSTIFY, spaceAfter=7)
S_H1    = style("H1", fontSize=15.5, leading=19, textColor=NAVY, spaceBefore=6, spaceAfter=4)
S_H2    = style("H2", fontSize=12.5, leading=16, textColor=BLUE, spaceBefore=10, spaceAfter=3)
S_H3    = style("H3", fontSize=11, leading=14, textColor=NAVY, spaceBefore=7, spaceAfter=2)
S_CAP   = style("cap", fontSize=9, leading=12, textColor=GREY, alignment=TA_CENTER, spaceBefore=4, spaceAfter=2)
S_NOTE  = style("note", fontSize=9.5, leading=13.5, textColor=GREY, alignment=TA_JUSTIFY, leftIndent=10, spaceAfter=5)
S_CELL  = style("cell", fontSize=9.3, leading=12)
S_CELLB = style("cellb", fontSize=9.3, leading=12, textColor=NAVY)
S_CELLW = style("cellw", fontSize=9.5, leading=12, textColor=colors.white)
S_TINY  = style("tiny", fontSize=8, leading=10, textColor=GREY)

# Cover styles
S_CV_TITLE = style("cvt", fontSize=25, leading=30, textColor=colors.white, alignment=TA_LEFT)
S_CV_SUB   = style("cvs", fontSize=12.5, leading=18, textColor=colors.HexColor("#cfe0f5"), alignment=TA_LEFT)

def P(t, st=S_BODY):   return Paragraph(t, st)
def cell(t, st=S_CELL): return Paragraph(t, st)

# ── Chèn ảnh giữ tỉ lệ, tối đa 16cm rộng ─────────────────────────────────────
MAXW = 16 * cm
def fig(rel, caption, maxw=MAXW, idx=None):
    path = os.path.join(IMG, rel)
    iw, ih = PILImage.open(path).size
    w = min(maxw, MAXW)
    h = w * ih / iw
    # giới hạn chiều cao để không tràn trang
    if h > 11.5 * cm:
        h = 11.5 * cm
        w = h * iw / ih
    im = Image(path, width=w, height=h)
    im.hAlign = "CENTER"
    cap = Paragraph(caption, S_CAP)
    return KeepTogether([Spacer(1, 4), im, cap, Spacer(1, 6)])

def h1(text, bookmark):
    # đề mục cấp 1 + thanh ngang + marker
    p = Paragraph(text, S_H1)
    p._bookmark = ("0", text)
    return KeepTogether([Spacer(1, 6), p,
                         HRFlowable(width="100%", thickness=1.2, color=BLUE,
                                    spaceBefore=2, spaceAfter=8)])

def h2(text):
    p = Paragraph(text, S_H2)
    p._bookmark = ("1", text)
    return p

def h3(text):
    return Paragraph(text, S_H3)

# ── DocTemplate có TOC + footer ──────────────────────────────────────────────
class Report(SimpleDocTemplate):
    def afterFlowable(self, flowable):
        bm = getattr(flowable, "_bookmark", None)
        if not bm and isinstance(flowable, KeepTogether):
            for f in flowable._content:
                bm = getattr(f, "_bookmark", None)
                if bm:
                    break
        if bm:
            level, text = bm
            self.notify("TOCEntry", (int(level), text, self.page))

def footer(canvas, doc):
    canvas.saveState()
    # marker góc trên phải
    canvas.setFont("VN", 7.5)
    canvas.setFillColor(RULE)
    canvas.drawRightString(A4[0] - 2 * cm, A4[1] - 1.25 * cm,
                           "OBS · 2026.06.09 · STORM / FOG·MONO")
    # rule + footer
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.5)
    canvas.line(2 * cm, 1.4 * cm, A4[0] - 2 * cm, 1.4 * cm)
    canvas.setFont("VN", 8)
    canvas.setFillColor(GREY)
    canvas.drawString(2 * cm, 1.05 * cm, "Nguyễn Gia Bảo  ·  Apache Storm: Fog vs Monolithic — IoT Smart Home")
    canvas.drawRightString(A4[0] - 2 * cm, 1.05 * cm, "Trang %d" % doc.page)
    canvas.restoreState()

def cover(canvas, doc):
    W, H = A4
    canvas.saveState()
    # nền navy nửa trên
    canvas.setFillColor(NAVY)
    canvas.rect(0, H * 0.52, W, H * 0.48, stroke=0, fill=1)
    # dải xanh nhấn
    canvas.setFillColor(BLUE)
    canvas.rect(0, H * 0.52, W, 6, stroke=0, fill=1)
    # lưới tick telemetry (góc trên phải) — thủ pháp "sổ tay quan trắc"
    canvas.setStrokeColor(colors.HexColor("#2f4a73"))
    canvas.setLineWidth(0.5)
    for i in range(18):
        x = W - 2 * cm - i * 0.32 * cm
        canvas.line(x, H - 1.6 * cm, x, H - 1.6 * cm - (0.55 * cm if i % 5 == 0 else 0.3 * cm))
    # nhãn nhỏ
    canvas.setFont("VN", 8.5)
    canvas.setFillColor(colors.HexColor("#9db8db"))
    canvas.drawString(2 * cm, H - 1.55 * cm, "BÁO CÁO KỸ THUẬT · PHÂN TÍCH HIỆU NĂNG HỆ PHÂN TÁN")
    # tiêu đề
    canvas.setFillColor(colors.white)
    canvas.setFont("VN", 26)
    title_lines = ["Phân tích hiệu năng Apache Storm:", "Kiến trúc Monolithic vs Fog", "Computing cho IoT Smart Home"]
    y = H * 0.86
    for ln in title_lines:
        canvas.drawString(2 * cm, y, ln)
        y -= 1.15 * cm
    # phụ đề
    canvas.setFont("VN", 12)
    canvas.setFillColor(colors.HexColor("#cfe0f5"))
    canvas.drawString(2 * cm, H * 0.585,
                      "Đo lường thực nghiệm trên hạ tầng đồng nhất · EC2 t3.large · 400 msg/s · 30 phút")
    # khối thông tin nửa dưới
    canvas.setFillColor(NAVY)
    canvas.setFont("VN", 11)
    canvas.drawString(2 * cm, H * 0.40, "Tác giả")
    canvas.setFont("VN", 15)
    canvas.setFillColor(INK)
    canvas.drawString(2 * cm, H * 0.365, "Nguyễn Gia Bảo")
    canvas.setFillColor(NAVY); canvas.setFont("VN", 11)
    canvas.drawString(2 * cm, H * 0.31, "Ngày")
    canvas.setFillColor(INK); canvas.setFont("VN", 13)
    canvas.drawString(2 * cm, H * 0.28, "09 / 06 / 2026")
    # ba chỉ số nổi bật (telemetry chips)
    chips = [("130×", "Complete Latency\nnhanh hơn"),
             ("151% → <1%", "Bolt Capacity\nhết nghẽn"),
             (">1000×", "Lưu lượng Cloud\ngiảm")]
    cx = 2 * cm
    for big, small in chips:
        canvas.setFillColor(LIGHT)
        canvas.roundRect(cx, H * 0.12, 5.0 * cm, 2.6 * cm, 6, stroke=0, fill=1)
        canvas.setFillColor(BLUE); canvas.setFont("VN", 17)
        canvas.drawString(cx + 0.4 * cm, H * 0.12 + 1.65 * cm, big)
        canvas.setFillColor(GREY); canvas.setFont("VN", 9)
        for j, sl in enumerate(small.split("\n")):
            canvas.drawString(cx + 0.4 * cm, H * 0.12 + 1.0 * cm - j * 0.42 * cm, sl)
        cx += 5.5 * cm
    canvas.setStrokeColor(RULE); canvas.setLineWidth(0.5)
    canvas.line(2 * cm, 1.4 * cm, W - 2 * cm, 1.4 * cm)
    canvas.setFont("VN", 8); canvas.setFillColor(GREY)
    canvas.drawString(2 * cm, 1.05 * cm, "Triết lý thiết kế: Telemetric Clarity — sự trong sáng của phép đo")
    canvas.restoreState()

# ── Bảng tiện ích ────────────────────────────────────────────────────────────
def data_table(header, rows, col_w, highlight=False):
    """highlight=True: cột Mono đỏ nhạt, cột Fog xanh nhạt (bảng so sánh)."""
    data = [[cell(h, S_CELLW) for h in header]]
    for r in rows:
        data.append([cell(c, S_CELL) for c in r])
    t = Table(data, colWidths=col_w, repeatRows=1)
    st = [
        ("BACKGROUND", (0, 0), (-1, 0), BLUE),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, RULE),
        ("LINEAFTER", (0, 0), (-2, -1), 0.4, colors.HexColor("#e2e8f0")),
        ("BOX", (0, 0), (-1, -1), 0.6, RULE),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            st.append(("BACKGROUND", (0, i), (-1, i), LIGHT))
    if highlight:
        for i in range(1, len(data)):
            st.append(("BACKGROUND", (1, i), (1, i), BAD))   # Mono
            st.append(("BACKGROUND", (2, i), (2, i), GOOD))  # Fog
    t.setStyle(TableStyle(st))
    return t

# ════════════════════════════════════════════════════════════════════════════
# NỘI DUNG
# ════════════════════════════════════════════════════════════════════════════
story = []

# ── Trang bìa (vẽ bằng canvas onFirstPage) → flowable đầu = PageBreak ─────────
story.append(PageBreak())

# ── Mục lục ──────────────────────────────────────────────────────────────────
story.append(Paragraph("Mục lục", S_H1))
story.append(HRFlowable(width="100%", thickness=1.2, color=BLUE, spaceBefore=2, spaceAfter=10))
toc = TableOfContents()
toc.levelStyles = [
    style("toc0", fontSize=11, leading=18, textColor=NAVY, leftIndent=6),
    style("toc1", fontSize=10, leading=15, textColor=INK, leftIndent=22),
]
story.append(toc)
story.append(PageBreak())

# ── 1. Giới thiệu ────────────────────────────────────────────────────────────
story.append(h1("1. Giới thiệu", "1"))
story.append(P(
    "Hệ thống nhà thông minh (Smart Home IoT) trong nghiên cứu này gồm <b>40 căn nhà</b>, mỗi nhà "
    "có nhiều thiết bị đo điện gắn ở ổ cắm. Các cảm biến liên tục phát số đọc về mức tiêu thụ, tạo "
    "thành dòng dữ liệu tốc độ cao — khoảng <b>400 bản tin/giây</b> ở quy mô thử nghiệm. Yêu cầu "
    "nghiệp vụ là tính các giá trị trung bình/tổng theo nhiều cửa sổ thời gian (1, 5, 10, 15, 30, 60, "
    "120 phút) phục vụ giám sát thời gian thực và cảnh báo."))
story.append(P(
    "Apache Storm là một nền tảng xử lý luồng (stream processing) phân tán: một <i>topology</i> là đồ "
    "thị có hướng gồm các <i>Spout</i> (nguồn phát tuple) và <i>Bolt</i> (đơn vị xử lý). Mỗi tuple đi "
    "qua đồ thị được theo dõi (ack) để đảm bảo độ tin cậy. Báo cáo này so sánh hai cách tổ chức cùng "
    "một bài toán trên Storm: kiến trúc <b>Monolithic</b> (tập trung toàn bộ xử lý trên Cloud) và kiến "
    "trúc <b>Fog Computing</b> (đẩy phần lớn xử lý xuống các nút biên gần nguồn dữ liệu)."))
story.append(P(
    "Mục tiêu không chỉ là chỉ ra kiến trúc nào “nhanh hơn”, mà phân tích <b>công bằng</b>: "
    "mỗi thay đổi của hệ Fog nằm ở đâu trong mã nguồn, tác động ra sao, và quan trọng — "
    "<b>cái giá phải trả là gì</b>. Không phải mọi thay đổi đều thuần lợi; một số chỉ là dịch chuyển "
    "chi phí, một số tạo ra giới hạn mở rộng mới. Báo cáo cố gắng tách bạch rõ ràng các sắc thái đó."))

# ── 2. Kiến trúc hệ thống ────────────────────────────────────────────────────
story.append(h1("2. Kiến trúc hệ thống", "2"))
story.append(h2("2.1 Kiến trúc Monolithic"))
story.append(P(
    "Toàn bộ xử lý chạy trên <b>một EC2 t3.large</b>. Luồng dữ liệu: Publisher → MQTT broker → "
    "<font face='VN'>Storm Spout</font> đọc dữ liệu thô của cả 40 nhà → <b>Bolt_split</b> phân tách "
    "mỗi tuple theo nhà và <i>fan-out</i> sang 8 nhánh cửa sổ thời gian → <b>8 Window Bolt</b> chạy "
    "song song tính trung bình theo từng cửa sổ (1/5/10/15/30/60/120 phút) → MySQL → REST API. "
    "Đặc điểm cốt lõi: <b>mọi tuple thô đều phải đi qua Cloud</b>, và việc nhân bản (fan-out) cùng "
    "định tuyến giữa các bolt diễn ra tập trung tại đây."))
story.append(h2("2.2 Kiến trúc Fog Computing (hai tầng)"))
story.append(P(
    "<b>Tầng Gateway (biên):</b> 8 Docker container trên laptop, mỗi container giả lập một Raspberry "
    "Pi 3B (giới hạn 1 GB RAM, 1 vCPU). Mỗi gateway phụ trách 5 nhà. Gateway nhận dữ liệu thô từ một "
    "MQTT broker cục bộ, tính <i>aggregation</i> ngay tại chỗ theo 5 cửa sổ (1/5/10/15/30 phút), rồi "
    "chỉ gửi <b>kết quả đã tổng hợp</b> lên Cloud MQTT theo cơ chế REPLACE (ghi đè theo khoá). Dữ liệu "
    "thô không bao giờ rời khỏi biên."))
story.append(P(
    "<b>Tầng Cloud:</b> EC2 t3.large (cùng cấu hình với Monolithic) nhận dữ liệu đã pre-aggregate. "
    "Topology gồm <font face='VN'>Spout_aggregated</font> → <b>Bolt_cloudMerge</b> (gộp dữ liệu từ 8 "
    "gateway, suy ra thêm cửa sổ 60/120 phút từ các lát 30 phút, ghi MySQL). Không còn fan-out lớn, "
    "không còn dòng thô tốc độ cao."))
story.append(h2("2.3 So sánh luồng dữ liệu"))
story.append(data_table(
    ["Khía cạnh", "Monolithic", "Fog Computing"],
    [["Dữ liệu lên Cloud", "Toàn bộ thô (~400 msg/s)", "Đã tổng hợp (~23 msg/phút)"],
     ["Nơi fan-out/windowing", "Tập trung tại Cloud", "Phân tán tại 8 gateway biên"],
     ["Định tuyến giữa bolt", "fieldsGrouping (cross-worker)", "cục bộ trong JVM / shuffle 1 task"],
     ["Cửa sổ dài (60/120')", "Tính trực tiếp tại Cloud", "Suy ra từ lát 30' khi merge"],
     ["Dữ liệu thô", "Đi xuyên toàn hệ", "Giữ tại biên, không lên Cloud"]],
    [4.6 * cm, 6.0 * cm, 6.2 * cm]))

# ── 3. Thiết kế thực nghiệm ──────────────────────────────────────────────────
story.append(h1("3. Thiết kế thực nghiệm", "3"))
story.append(P(
    "Dữ liệu dùng bộ <b>REFIT</b> (40 nhà, 16 giờ/nhà). Điều kiện được cố định cho cả hai kiến trúc "
    "để so sánh công bằng: cùng <b>~400 msg/s</b> dữ liệu thô, cùng thời lượng <b>30 phút</b>, cùng "
    "loại máy <b>EC2 t3.large</b> tại vùng ap-southeast-1. Bộ phát dữ liệu (publisher) dùng cùng cơ "
    "chế giới hạn tốc độ ở cả hai phía nên tải đầu vào là tương đương."))
story.append(P(
    "Công cụ đo: <b>Apache Storm REST API</b> + <b>storm-exporter</b> (cùng phiên bản mr4x2 v1.2.2, "
    "chu kỳ làm mới 5 giây ở cả hai hệ) → <b>Prometheus</b> (scrape 5 giây) → <b>Grafana</b>. Tài "
    "nguyên container đo bằng <i>docker stats</i>. Mọi biểu đồ trong báo cáo là ảnh chụp trực tiếp từ "
    "Grafana của phiên đo ngày 09/06/2026."))
story.append(P(
    "<b>Lưu ý về tính hợp lệ:</b> các chỉ số <i>throughput</i> (đếm tuple) độc lập phần cứng nên là "
    "bằng chứng mạnh nhất. Các chỉ số độ trễ/capacity phụ thuộc phần cứng, nhưng vì chạy trên cùng "
    "loại EC2 nên xu hướng so sánh vẫn hợp lệ. Lưu lượng WAN đo theo lượng dữ liệu thực tế qua broker.",
    S_NOTE))

# ── 4. Kết quả đo đạc ────────────────────────────────────────────────────────
story.append(h1("4. Kết quả đo đạc", "4"))

story.append(h2("4.1 Throughput — Monolithic"))
story.append(P(
    "Tốc độ phát (emitted) tăng dần và đạt đỉnh <b>2.520 ops/s</b> (trung bình 1.800 ops/s); tốc độ "
    "ack đạt đỉnh <b>1.430 ops/s</b> (trung bình 474 ops/s). Khoảng cách lớn giữa emitted và acked "
    "cho thấy hệ đang tích luỹ tuple chưa kịp xử lý xong — dấu hiệu của tắc nghẽn phía sau."))
story.append(fig("mono/throughput.png",
    "Hình 1. Topology Throughput — Monolithic: emitted đỉnh 2.52K ops/s, acked đỉnh 1.43K ops/s."))
story.append(fig("mono/spout-emitted-rate.png",
    "Hình 2. Spout Emitted Rate — Monolithic: nguồn phát đạt tối đa ~294 ops/s rồi giữ ổn định."))

story.append(h2("4.2 Throughput — Fog Computing"))
story.append(P(
    "Cloud chỉ nhận khoảng <b>40 tuple tổng hợp</b> mỗi chu kỳ flush. Tầng gateway xử lý tới "
    "<b>248.982 tuple thô</b> nhưng chỉ gửi <b>688 bản tin</b> lên Cloud trong toàn phiên (~23 bản "
    "tin/phút). Đây là khác biệt bản chất: phần lớn công việc đếm/cộng đã hoàn tất ở biên."))
story.append(fig("fog/cloud-tuples-emitted-transferred.png",
    "Hình 3. Cloud Tuples Emitted & Transferred — Fog: tăng dần đến ~480 trong cửa sổ 600s. "
    "Hai đường gần trùng khít → topology Cloud một bolt, không nhân bản tuple."))
story.append(fig("fog/cloud-tuples-acked.png",
    "Hình 4. Cloud Tuples Acked — Fog: ~40 tuple mỗi chu kỳ flush của gateway."))
story.append(fig("fog/gateway-ingestion-rate.png",
    "Hình 5. Gateway Tuple Ingestion Rate — 8 gateway cân bằng gần như hoàn hảo, mỗi nút ~30–32 tuples/s."))

story.append(h2("4.3 Complete Latency — chỉ số quan trọng nhất"))
story.append(P(
    "Complete Latency là độ trễ end-to-end: từ lúc Spout phát một tuple đến khi toàn bộ chuỗi xử lý "
    "(lineage) của nó được ack hoàn tất. Nó phản ánh tải <i>thực sự</i> của hệ — bao gồm cả thời gian "
    "tuple phải nằm chờ trong hàng đợi nội bộ."))
story.append(P(
    "Ở Monolithic, chỉ số này lên tới <b>trung bình 4,62 giây</b> và <b>đỉnh 14,0 giây</b> (đơn vị "
    "giây, không phải mili-giây). Nguyên nhân: các bolt cửa sổ chạy ở capacity vượt 100% (xem 4.4), "
    "tuple mới phải xếp hàng chờ — phần lớn complete latency chính là thời gian chờ này."))
story.append(fig("mono/complete-latency.png",
    "Hình 6. Complete Latency — Monolithic: Mean = 4,62 s, Max = 14,0 s. Spike cao do bolt capacity "
    "vượt 100%, tuple phải chờ hàng đợi."))
story.append(P(
    "Ở Fog, complete latency đo được chỉ <b>35,5 ms</b> — gần như thuần thời gian xử lý, vì "
    "<font face='VN'>Bolt_cloudMerge</font> chỉ nhận ~23 bản tin/phút nên capacity gần 0, không phát "
    "sinh thời gian chờ. Quá trình ổn định nên không cần biểu đồ đường riêng; ảnh dưới minh hoạ độ "
    "trễ xử lý bolt phía Cloud về gần 0."))
story.append(fig("fog/cloud-bolt-process-latency.png",
    "Hình 7. Cloud Bolt Process Latency — Fog: chỉ spike ngắn lúc khởi động rồi về ~0 ms."))

story.append(h2("4.4 Bolt Capacity và tắc nghẽn"))
story.append(P(
    "Bolt Capacity = (thời gian thực thi × số tuple đã xử lý) / thời gian cửa sổ đo. Giá trị > 1,0 "
    "(100%) nghĩa là bolt nhận tuple nhanh hơn khả năng xử lý — tuple dồn vào hàng đợi, kéo complete "
    "latency tăng vọt. Đây là định nghĩa kỹ thuật của “nghẽn cổ chai” trong Storm."))
story.append(fig("mono/bolt-capacity.png",
    "Hình 8. Bolt Capacity — Monolithic: split-5 = 151%, split-30 = 136%, split-120 = 135%... "
    "Tất cả bolt cửa sổ đều vượt 100% = bottleneck nghiêm trọng."))
story.append(fig("fog/cloud-bolt-capacity.png",
    "Hình 9. Cloud Bolt Capacity — Fog: spike ngắn khi khởi động, sau đó < 45%, cuối phiên về gần 0%."))
story.append(fig("fog/gateway-all-bolt-capacity.png",
    "Hình 10. Gateway Bolt Capacity — Fog: cả 8 gateway giữ < 0,54% suốt 30 phút (gw-07 cao nhất: 0,54%). "
    "Tải được phân tán đều, mỗi nút còn dư địa > 99%."))

story.append(h2("4.5 Execution Latency của Bolt"))
story.append(P(
    "Execution latency là thời gian chạy <i>bên trong</i> hàm xử lý của bolt (không gồm chờ hàng đợi). "
    "Ở Monolithic, các split bolt mất 1,52–1,90 ms (spike 3,65 ms). Ở Fog, mỗi gateway chỉ ~0,03 ms "
    "vì xử lý dữ liệu cục bộ, không I/O mạng ra ngoài."))
story.append(fig("mono/bolt-execution-latency.png",
    "Hình 11. Bolt Execution Latency — Monolithic: split bolt trung bình 1,52–1,90 ms, spike đến 3,65 ms."))
story.append(fig("fog/gateway-bolt-execute-latency.png",
    "Hình 12. Gateway Bolt Execute Latency EMA — Fog: baseline ~0,02–0,04 ms, spike lẻ tẻ < 0,3 ms."))
story.append(fig("fog/gateway-all-execute-latency.png",
    "Hình 13. Tất cả 8 Gateway Execute Latency EMA — đều ở mức cực thấp, ổn định."))

story.append(h2("4.6 Store-and-Forward Queue (chỉ có ở Fog)"))
story.append(P(
    "Gateway có cơ chế <i>store-and-forward</i>: nếu mất kết nối tới Cloud, bản tin được giữ trong "
    "hàng đợi cục bộ và gửi bù khi nối lại — đảm bảo không mất dữ liệu. Trong suốt phiên đo, độ sâu "
    "hàng đợi <b>luôn bằng 0</b>, xác nhận kết nối ổn định và không có backpressure."))
story.append(fig("fog/gateway-store-queue-depth.png",
    "Hình 14. Store-and-Forward Queue Depth — 8 gateway, bằng 0 suốt 30 phút = không mất dữ liệu, không backlog."))

story.append(h2("4.7 Panel tổng hợp Fog vs Monolithic"))
story.append(fig("fog/traffic-reduction-summary.png",
    "Hình 15. Bảng tổng hợp trên Grafana: Emitted/Transferred giảm 54,6%, Cloud Process Latency 0 ms, "
    "Store Queue = 0, 8/8 gateway hoạt động, exporter UP."))

story.append(h2("4.8 Tài nguyên hệ thống"))
story.append(P(
    "Trên Monolithic, container <b>supervisor</b> tiêu thụ <b>165% CPU</b> và 2,45 GB RAM (tổng cả "
    "box ~179% CPU, ~5,0 GB). Đáng chú ý: supervisor2 chỉ 11,8% — tải <b>không cân bằng</b> giữa hai "
    "supervisor (chi tiết bàn ở mục 6). Trên Fog, tổng CPU Cloud chỉ ~45%, RAM ~1,9 GB."))
story.append(fig("mono/cluster-slot-usage.png",
    "Hình 16. Cluster Slot Usage — Monolithic: 25% (chỉ 1 trong 4 slot worker được dùng) — một điểm "
    "quan trọng cho phân tích công bằng ở mục 6."))

# ── 5. Bảng so sánh tổng hợp ─────────────────────────────────────────────────
story.append(PageBreak())
story.append(h1("5. Bảng so sánh tổng hợp", "5"))
story.append(P(
    "Bảng dưới tổng hợp các chỉ số then chốt. Ô <b>đỏ</b> = giá trị Monolithic (kém hơn/nghẽn); ô "
    "<b>xanh</b> = giá trị Fog (tốt hơn). Mọi số liệu là đo thực tế phiên 09/06/2026."))
story.append(data_table(
    ["Chỉ số", "Monolithic", "Fog Computing", "Cải thiện"],
    [["Complete Latency (trung bình)", "4,62 giây", "35,5 ms", "≈ 130× nhanh hơn"],
     ["Complete Latency (đỉnh)", "14,0 giây", "≈ 35,5 ms", "≈ 394× nhanh hơn"],
     ["Bolt Capacity (tệ nhất)", "151% (nghẽn)", "< 0,54%", "Hết bottleneck"],
     ["Cloud CPU Supervisor", "165%", "17,86%", "≈ 9× thấp hơn"],
     ["Cloud RAM tổng", "≈ 5,0 GB", "≈ 1,9 GB", "≈ 2,6× thấp hơn"],
     ["Dữ liệu gửi lên Cloud", "≈ 400 raw msg/s", "≈ 23 agg msg/phút", "> 1.000× ít hơn"],
     ["Bolt Execute Latency", "1,52–1,90 ms", "≈ 0,03 ms", "≈ 60× nhanh hơn"],
     ["Queue / Backlog", "Có (capacity > 1,0)", "0", "Không tắc nghẽn"],
     ["Emitted tuple Cloud", "1.800–2.520 ops/s", "giảm 54,6%", "Giảm 54,6%"]],
    [4.8 * cm, 4.2 * cm, 3.9 * cm, 3.9 * cm], highlight=True))
story.append(Spacer(1, 6))
story.append(P(
    "Cảnh báo đọc số: các bội số (130×, 394×, >1.000×) ấn tượng vì phản ánh trạng thái Monolithic "
    "đang <i>bão hoà</i> trên t3.large. Chúng cho thấy ở đúng tải và đúng phần cứng này Fog vượt trội "
    "rõ rệt — nhưng không nên hiểu là “Fog nhanh hơn Monolithic 130 lần trong mọi điều kiện”. "
    "Mục 6 phân tích các điều kiện và đánh đổi.", S_NOTE))

# ── 6. Phân tích và thảo luận ────────────────────────────────────────────────
story.append(h1("6. Phân tích & thảo luận: các thay đổi và tác động", "6"))
story.append(P(
    "Phần này đi vào trọng tâm: hệ Fog đã thay đổi <b>chính xác chỗ nào</b> trong mã nguồn, mỗi thay "
    "đổi mang lại gì và <b>phải trả giá gì</b>. Tinh thần xuyên suốt: không thay đổi nào là “ma "
    "thuật” — phần lớn là dịch chuyển hoặc đánh đổi chi phí một cách có chủ đích."))

story.append(h3("Thay đổi 1 — Fan-out “logic” tại gateway thay cho fan-out vật lý"))
story.append(P(
    "<b>Ở đâu:</b> hàm <font face='VN'>Bolt_ingest.execute()</font> của gateway. Thay vì phát 5 tuple "
    "cho 5 cửa sổ, nó cập nhật 5 bộ tích luỹ (accumulator) trong <b>một lượt duyệt</b>, không phát "
    "tuple nào. <b>Tác động:</b> số tuple emitted/transferred trên Cloud sụp đổ nhiều bậc; không còn "
    "truyền chéo worker qua Netty; capacity gateway ~0. <b>Đánh đổi/sắc thái:</b> thay đổi này "
    "<i>không</i> làm giảm khối lượng số học (vẫn phải chạm vào mỗi số đọc một lần) — nó cắt phần "
    "<i>overhead</i> của Storm: tạo đối tượng tuple, sổ sách ack, tuần tự hoá mạng. Ở tốc độ tuple "
    "cao, chính overhead này mới là chi phí trội, nên lợi ích là thật; nhưng đây là tối ưu kỹ thuật "
    "vận hành, không phải giảm bản chất tính toán."))

story.append(h3("Thay đổi 2 — Cloud chỉ còn một bolt, shuffleGrouping về một task"))
story.append(P(
    "<b>Ở đâu:</b> <font face='VN'>CloudMainTopo</font>: một spout → một <font face='VN'>Bolt_cloudMerge</font> "
    "(parallelism = 1), shuffleGrouping tới đúng một task. <b>Tác động:</b> emitted = transferred = 620 "
    "(mỗi emit đúng một transfer, không nhân bản); process latency ~0; không còn executor nghẽn. "
    "<b>Đánh đổi:</b> điều này chỉ khả thi <i>vì</i> gateway đã gánh phần nặng. Nhưng một bolt "
    "parallelism = 1 tự nó là <b>trần mở rộng</b>: hiện chưa thể scale Cloud theo chiều ngang nếu số "
    "gateway tăng mạnh. “Một bolt” trông tuyệt ở quy mô này nhưng là một giới hạn thiết kế "
    "cần lưu ý trong tương lai."))

story.append(h3("Thay đổi 3 — Pre-aggregation tại biên, giảm lưu lượng WAN"))
story.append(P(
    "<b>Ở đâu:</b> gateway flush kết quả tổng hợp lên Cloud MQTT. <b>Tác động:</b> lưu lượng lên "
    "Cloud từ ~400 msg/s xuống ~23 msg/phút (giảm > 1.000×). Đây là lợi ích <b>thật, không phải dịch "
    "chuyển</b> — dữ liệu dư thừa bị loại bỏ ngay tại nguồn, băng thông WAN (tài nguyên đắt và khan "
    "nhất trong IoT) được giải phóng. <b>Đánh đổi:</b> tổng hợp làm <i>mất chi tiết thô</i> — Cloud "
    "không thể truy ngược từng số đọc. Với bài toán tính trung bình thì chấp nhận được; với nhu cầu "
    "điều tra sự kiện bất thường ở mức raw thì đây là mất mát."))

story.append(h3("Thay đổi 4 — REPLACE INTO + giá trị luỹ kế (tính idempotent)"))
story.append(P(
    "<b>Ở đâu:</b> <font face='VN'>FogDB_store</font> dùng REPLACE INTO; gateway gửi tổng <i>luỹ kế</i> "
    "thay vì gia số. <b>Tác động:</b> phân phối at-least-once trở nên idempotent — gateway gửi lại "
    "cùng batch (do reconnect) cũng không làm sai dữ liệu, an toàn với MQTT QoS=1. <b>Đánh đổi:</b> "
    "REPLACE nặng hơn INSERT (xoá rồi chèn); cộng với ghi qua mạng nội bộ tới MySQL, đây là lý do "
    "execute latency phía Cloud ~2,4 ms (I/O-bound). Một lợi ích về tính đúng đắn được mua bằng chi "
    "phí I/O mỗi lần ghi — chấp nhận được vì tần suất ghi rất thấp."))

story.append(h3("Thay đổi 5 — Phân tán xuống 8 gateway: cái giá tài nguyên"))
story.append(P(
    "<b>Tác động:</b> Cloud capacity từ 151% về < 1%; Cloud CPU từ 179% về 45%, RAM từ 5,0 GB về "
    "1,9 GB. <b>Sắc thái công bằng quan trọng nhất:</b> <i>tổng</i> khối lượng tính toán gần như được "
    "bảo toàn — tầng gateway tiêu thụ ~87% CPU tổng (8 × ~11%) và ~1,5 GB RAM. Nói cách khác, “Cloud "
    "nhẹ đi” một phần là <b>dịch chuyển</b> chi phí sang biên. Lợi ích ròng phụ thuộc vào việc "
    "gateway có phải phần cứng sẵn có và rẻ (Pi/hub trong nhà) hay không — nếu phải mua mới, ở quy mô "
    "40 nhà cán cân kinh tế chưa chắc nghiêng về Fog."))

story.append(h3("Caveat công bằng — Monolithic chưa được tinh chỉnh hết mức"))
story.append(P(
    "Cần sòng phẳng: Monolithic trong phiên đo <b>chỉ dùng 25% slot</b> (1/4 worker — Hình 16) và tải "
    "lệch hẳn về một supervisor (165% so với 11,8%). Nghĩa là topology Monolithic <i>chưa được song "
    "song hoá tốt</i> — về lý thuyết có thể tăng parallelism để dùng cả hai nhân của t3.large đều hơn. "
    "Tuy vậy, supervisor đã chạm ~165% trên máy 2 vCPU, nên nút thắt căn bản vẫn là <b>tỉ lệ giữa khối "
    "lượng thô và một box 2 vCPU</b>. Kết luận trung thực: so sánh phản ánh hai topology <i>như đã "
    "dựng</i>, không phải Monolithic tối ưu lý thuyết. Một Monolithic được tinh chỉnh kỹ có thể thu "
    "hẹp khoảng cách độ trễ, nhưng không thể tránh được việc phải tải toàn bộ dữ liệu thô lên Cloud — "
    "đó mới là khác biệt kiến trúc cốt lõi."))

story.append(h3("Vì sao Complete Latency giảm từ 4,62 s xuống 35,5 ms?"))
story.append(P(
    "Ở Monolithic, Bolt_split chạy ở capacity 100–151%; tuple mới phải chờ trong hàng đợi nội bộ — "
    "<i>thời gian chờ</i> này chiếm phần lớn 4+ giây. Ở Fog, Bolt_cloudMerge chỉ nhận ~23 bản tin/phút, "
    "capacity gần 0 nên hầu như không có thời gian chờ; complete latency còn lại chủ yếu là thời gian "
    "xử lý + ghi DB (~35 ms). Khác biệt không nằm ở “code chạy nhanh hơn” mà ở “gần như "
    "không còn xếp hàng”."))

story.append(h3("Tính đúng đắn & hạn chế"))
story.append(P(
    "<b>Đúng đắn:</b> REPLACE semantics + store-and-forward queue = 0 xác nhận không mất dữ liệu và "
    "không nhân đôi khi gửi lại. <b>Hạn chế:</b> (1) topology fog-cloud chạy 1 worker → chưa kiểm chứng "
    "mở rộng ngang; (2) độ phức tạp vận hành cao hơn — phải duy trì 8 container gateway, hai tầng, hai "
    "MQTT broker; (3) cơ chế durability (queue) chưa được “thử lửa” trong phiên này vì mạng "
    "ổn định — giá trị của nó chỉ hiện ra khi có sự cố. Những điểm này là chi phí phải cân nhắc, không "
    "phải lợi ích."))

# ── 7. Kết luận ──────────────────────────────────────────────────────────────
story.append(h1("7. Kết luận", "7"))
story.append(P(
    "Trên đúng tải (~400 msg/s) và đúng phần cứng (EC2 t3.large), Fog Computing giải quyết triệt để "
    "nút thắt của Monolithic: complete latency giảm khoảng 130 lần (4,62 s → 35,5 ms), bolt capacity "
    "từ quá tải 151% về dưới 1%, CPU Cloud giảm ~9× và RAM ~2,6×, lưu lượng lên Cloud giảm hơn 1.000 "
    "lần. Cơ chế store-and-forward bổ sung một lớp bền vững dữ liệu mà kiến trúc tập trung không có."))
story.append(P(
    "Tuy nhiên, kết luận cân bằng phải nhấn mạnh: lợi thế lớn nhất của Fog <b>không</b> phải “làm "
    "ít việc hơn” (tổng tính toán gần như bảo toàn), mà là <b>chọn đúng nơi thực thi</b> — đổi "
    "compute biên rẻ lấy băng thông WAN đắt, tách tải Cloud khỏi số lượng thiết bị (mở rộng ngang thay "
    "vì đụng trần dọc), và cho phép xử lý/cảnh báo cục bộ. Cái giá là độ phức tạp vận hành, tài nguyên "
    "biên, mất chi tiết dữ liệu thô và một trần mở rộng mới ở tầng Cloud (một bolt). Với hệ Smart Home "
    "nơi thiết bị biên (Pi 3B) sẵn có và đủ sức gánh pre-processing, đánh đổi này là xứng đáng và được "
    "chứng minh bằng số liệu thực nghiệm."))

# ── Tài liệu tham khảo ───────────────────────────────────────────────────────
story.append(h1("Tài liệu tham khảo", "ref"))
refs = [
    "[1] Apache Storm Documentation — “Concepts &amp; Internal Working”. https://storm.apache.org/",
    "[2] M. Satyanarayanan, “The Emergence of Edge Computing”, IEEE Computer, 2017.",
    "[3] F. Bonomi et al., “Fog Computing and Its Role in the Internet of Things”, MCC Workshop, 2012.",
    "[4] OpenFog Consortium, “OpenFog Reference Architecture for Fog Computing”, 2017.",
    "[5] D. Murray et al., REFIT Smart Home Dataset, Loughborough University, 2017.",
]
for r in refs:
    story.append(P(r, style("ref", fontSize=10, leading=15, spaceAfter=4)))

# ════════════════════════════════════════════════════════════════════════════
doc = Report(OUT, pagesize=A4,
             leftMargin=2 * cm, rightMargin=2 * cm,
             topMargin=2 * cm, bottomMargin=2 * cm,
             title="Phân tích hiệu năng Apache Storm: Monolithic vs Fog Computing",
             author="Nguyễn Gia Bảo")

def on_first(canvas, doc):  # trang bìa
    cover(canvas, doc)
def on_later(canvas, doc):
    footer(canvas, doc)

doc.multiBuild(story, onFirstPage=on_first, onLaterPages=on_later)
print("Đã tạo:", OUT)

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    Flowable,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.pdfbase.pdfmetrics import stringWidth


OUT = "docs/riscv_core_explained.pdf"


styles = getSampleStyleSheet()
styles.add(ParagraphStyle(
    name="CoverTitle",
    parent=styles["Title"],
    fontName="Helvetica-Bold",
    fontSize=30,
    leading=34,
    alignment=TA_CENTER,
    textColor=colors.HexColor("#122238"),
    spaceAfter=14,
))
styles.add(ParagraphStyle(
    name="CoverSub",
    parent=styles["BodyText"],
    fontSize=14,
    leading=19,
    alignment=TA_CENTER,
    textColor=colors.HexColor("#4b5c6d"),
))
styles.add(ParagraphStyle(
    name="H1x",
    parent=styles["Heading1"],
    fontSize=18,
    leading=22,
    textColor=colors.HexColor("#122238"),
    borderWidth=0,
    borderPadding=0,
    spaceBefore=10,
    spaceAfter=8,
))
styles.add(ParagraphStyle(
    name="H2x",
    parent=styles["Heading2"],
    fontSize=13,
    leading=16,
    textColor=colors.HexColor("#1d3758"),
    spaceBefore=8,
    spaceAfter=5,
))
styles.add(ParagraphStyle(
    name="Bodyx",
    parent=styles["BodyText"],
    fontSize=9.4,
    leading=12.4,
    textColor=colors.HexColor("#18222f"),
    spaceAfter=5,
))
styles.add(ParagraphStyle(
    name="Smallx",
    parent=styles["BodyText"],
    fontSize=8.2,
    leading=10.5,
    textColor=colors.HexColor("#4f5f6d"),
))


def p(text, style="Bodyx"):
    text = text.replace("<code>", "<font name='Courier' color='#12385d'>")
    text = text.replace("</code>", "</font>")
    return Paragraph(text, styles[style])


def h(text):
    return Paragraph(text, styles["H1x"])


def h2(text):
    return Paragraph(text, styles["H2x"])


def table(rows, widths=None):
    data = [[p(str(cell), "Smallx") for cell in row] for row in rows]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#edf3f8")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#12314f")),
        ("GRID", (0, 0), (-1, -1), 0.45, colors.HexColor("#d6dee8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    return t


class Diagram(Flowable):
    def __init__(self, kind, width=180 * mm, height=72 * mm):
        super().__init__()
        self.kind = kind
        self.width = width
        self.height = height

    def wrap(self, avail_width, avail_height):
        return min(self.width, avail_width), self.height

    def draw_box(self, c, x, y, w, h, title, sub="", fill="#f8fbfd", stroke="#58738a"):
        c.setStrokeColor(colors.HexColor(stroke))
        c.setFillColor(colors.HexColor(fill))
        c.roundRect(x, y, w, h, 5, stroke=1, fill=1)
        c.setFillColor(colors.HexColor("#18222f"))
        c.setFont("Helvetica-Bold", 8.6)
        c.drawCentredString(x + w / 2, y + h / 2 + 4, title)
        if sub:
            c.setFont("Helvetica", 6.8)
            c.drawCentredString(x + w / 2, y + h / 2 - 8, sub)

    def arrow(self, c, x1, y1, x2, y2, color="#32506a"):
        c.setStrokeColor(colors.HexColor(color))
        c.setLineWidth(1.0)
        c.line(x1, y1, x2, y2)
        # Small triangular arrowhead.
        import math
        ang = math.atan2(y2 - y1, x2 - x1)
        size = 4
        pts = [
            (x2, y2),
            (x2 - size * math.cos(ang - 0.45), y2 - size * math.sin(ang - 0.45)),
            (x2 - size * math.cos(ang + 0.45), y2 - size * math.sin(ang + 0.45)),
        ]
        pth = c.beginPath()
        pth.moveTo(*pts[0])
        pth.lineTo(*pts[1])
        pth.lineTo(*pts[2])
        pth.close()
        c.setFillColor(colors.HexColor(color))
        c.drawPath(pth, stroke=0, fill=1)

    def draw(self):
        c = self.canv
        c.setStrokeColor(colors.HexColor("#d8e0ea"))
        c.setFillColor(colors.white)
        c.roundRect(0, 0, self.width, self.height, 5, stroke=1, fill=1)
        c.saveState()
        c.translate(7, 7)
        if self.kind == "soc":
            self.soc(c)
        elif self.kind == "core":
            self.core(c)
        elif self.kind == "fsm":
            self.fsm(c)
        else:
            self.lsu(c)
        c.restoreState()

    def soc(self, c):
        self.draw_box(c, 5, 130, 74, 32, "UART Boot", "RX + Loader", "#fff7ea", "#b67526")
        self.draw_box(c, 5, 82, 74, 32, "SPI Flash Boot", "QSPI Read", "#fff7ea", "#b67526")
        self.draw_box(c, 5, 34, 74, 32, "AXI Prog.", "ext_prog_mode", "#fff7ea", "#b67526")
        self.draw_box(c, 115, 125, 82, 38, "IMEM", "4096 Worte", "#eef7f6", "#2d6f85")
        self.draw_box(c, 115, 40, 82, 38, "DMEM", "1024 Worte + BE", "#eef7f6", "#2d6f85")
        self.draw_box(c, 245, 76, 118, 65, "riscv_core_memless", "FSM, Decoder, ALU, CSR")
        self.draw_box(c, 400, 122, 78, 34, "Timer MMIO", "0x40001xxx", "#eef7f6", "#2d6f85")
        self.draw_box(c, 400, 52, 78, 34, "UART TX MMIO", "0x40002000", "#eef7f6", "#2d6f85")
        for y, ty in [(146, 144), (98, 144), (50, 59)]:
            self.arrow(c, 79, y, 115, ty, "#9b5f17")
        self.arrow(c, 197, 144, 245, 122)
        self.arrow(c, 245, 112, 197, 144)
        self.arrow(c, 245, 91, 197, 59)
        self.arrow(c, 197, 59, 245, 82)
        self.arrow(c, 363, 121, 400, 139)
        self.arrow(c, 400, 139, 363, 110)
        self.arrow(c, 363, 90, 400, 69)
    def core(self, c):
        self.draw_box(c, 5, 150, 70, 30, "IMEM", "instr")
        self.draw_box(c, 105, 145, 72, 40, "Instr. Reg", "instr_pc")
        self.draw_box(c, 205, 145, 72, 40, "Decoder", "control")
        self.draw_box(c, 305, 145, 72, 40, "cur_* Latch", "stabile Signale")
        self.draw_box(c, 205, 76, 72, 42, "Regfile", "x0=0")
        self.draw_box(c, 305, 83, 72, 34, "ALU", "arith/log/MUL")
        self.draw_box(c, 305, 36, 72, 34, "Branch", "take_o")
        self.draw_box(c, 405, 43, 72, 38, "LSU", "BE + Align")
        self.draw_box(c, 405, 112, 72, 38, "CSR File", "trap/irq")
        self.draw_box(c, 105, 30, 72, 36, "PC", "next_pc")
        for x1, y1, x2, y2 in [
            (75, 165, 105, 165), (177, 165, 205, 165), (277, 165, 305, 165),
            (341, 145, 341, 117), (277, 97, 305, 101), (377, 100, 405, 62),
            (405, 62, 377, 53), (377, 100, 405, 131), (141, 66, 141, 145),
            (305, 165, 177, 48), (377, 100, 177, 48),
        ]:
            self.arrow(c, x1, y1, x2, y2)
    def fsm(self, c):
        nodes = {
            "RESET": (8, 75), "FETCH": (74, 75), "FETCH_WAIT": (142, 75),
            "DECODE": (226, 75), "RF_WAIT": (292, 75), "ALU": (385, 145),
            "CSR": (385, 112), "JUMP": (385, 79), "BRANCH": (385, 46),
            "LOAD_ADDR": (385, 13), "STORE_ADDR": (385, -20), "WB": (465, 145),
            "MEM_R": (465, 13), "MEM_W": (465, -20), "TRAP/MRET": (292, 130),
        }
        for name, (x, y) in nodes.items():
            self.draw_box(c, x, y + 25, 58 if len(name) < 8 else 70, 25, name, "")
        seq = ["RESET", "FETCH", "FETCH_WAIT", "DECODE", "RF_WAIT"]
        for a, b in zip(seq, seq[1:]):
            ax, ay = nodes[a]; bx, by = nodes[b]
            self.arrow(c, ax + (70 if a == "FETCH_WAIT" else 58), ay + 37, bx, by + 37)
        for target in ["ALU", "CSR", "JUMP", "BRANCH", "LOAD_ADDR", "STORE_ADDR", "TRAP/MRET"]:
            ax, ay = nodes["RF_WAIT"]; bx, by = nodes[target]
            self.arrow(c, ax + 58, ay + 37, bx, by + 37)
        for a, b in [("ALU", "WB"), ("CSR", "WB"), ("JUMP", "WB"), ("LOAD_ADDR", "MEM_R"), ("STORE_ADDR", "MEM_W"), ("MEM_R", "WB")]:
            ax, ay = nodes[a]; bx, by = nodes[b]
            self.arrow(c, ax + (70 if len(a) >= 8 else 58), ay + 37, bx, by + 37)
    def lsu(self, c):
        self.draw_box(c, 15, 105, 88, 35, "Adresse", "rs1 + imm")
        self.draw_box(c, 15, 35, 88, 35, "Store-Daten", "rs2")
        self.draw_box(c, 150, 65, 110, 70, "Load/Store Unit", "offset, BE, Align", "#eef7f6", "#2d6f85")
        self.draw_box(c, 325, 78, 90, 46, "DMEM", "32-bit Worte", "#eef7f6", "#2d6f85")
        self.draw_box(c, 460, 78, 70, 46, "Writeback", "rd")
        self.arrow(c, 103, 122, 150, 112)
        self.arrow(c, 103, 53, 150, 84)
        self.arrow(c, 260, 100, 325, 101)
        self.arrow(c, 325, 89, 260, 78)
        self.arrow(c, 415, 101, 460, 101)


def build():
    doc = SimpleDocTemplate(
        OUT,
        pagesize=A4,
        rightMargin=14 * mm,
        leftMargin=14 * mm,
        topMargin=13 * mm,
        bottomMargin=13 * mm,
        title="RiscVFSM Core Dokumentation",
    )
    story = []
    story += [
        Spacer(1, 68 * mm),
        Paragraph("RiscVFSM RISC-V Core", styles["CoverTitle"]),
        p("Eine schulische Erklaerung: welche Bausteine im Prozessor stecken, welche Aufgabe sie haben und wie aus vielen kleinen Schritten eine laufende CPU wird.", "CoverSub"),
        Spacer(1, 18 * mm),
        p("Stand: 05.05.2026<br/>Quellenbasis: lokale VHDL-Dateien in <code>RiscVTest.srcs/sources_1/new</code><br/>Top-Pfad: <code>riscv_soc_boot</code> mit <code>riscv_core_memless</code>", "CoverSub"),
        PageBreak(),
    ]

    story += [
        h("1. Die Idee in einem Satz"),
        p("Der Core ist ein kleiner RISC-V-Prozessor, der ein Programm Schritt fuer Schritt aus dem Instruktionsspeicher liest, die Befehle versteht, mit Registern und Rechenwerk ausfuehrt und bei Bedarf auf Speicher, Timer oder UART zugreift."),
        p("Er ist kein Pipeline-Prozessor. Stattdessen arbeitet er wie ein genauer Ablaufplan: holen, dekodieren, Operanden lesen, ausfuehren, eventuell Speicher benutzen und Ergebnis zurueckschreiben. Diese Ablaufsteuerung ist die FSM. Merksatz: Die FSM ist der Taktgeber des Denkens."),
        Diagram("soc"),
    ]
    story += [h("2. Was gehoert alles dazu?"), p("Man kann den Aufbau wie ein kleines Computersystem sehen. Innen sitzt der eigentliche Prozessor. Aussen herum liegen Speicher, Boot-Logik und einfache Ein-/Ausgabe."), table([
        ["Baustein", "Rolle im System", "Zusammenhang"],
        ["riscv_core_memless", "Eigentlicher CPU-Kern mit PC, FSM, Decoder-Anbindung, Register, ALU, Branch, LSU und CSR.", "Fragt Instruktionen aus IMEM ab und liest oder schreibt Daten ueber DMEM/MMIO."],
        ["decoder", "Uebersetzer: erkennt aus den Instruktionsbits, ob es z. B. ADD, LW, Branch oder CSR ist.", "Seine Ausgaenge werden im Core gespeichert, damit die naechsten FSM-Zustaende stabile Steuersignale haben."],
        ["regfile", "Kurzzeitgedaechtnis der CPU mit 32 Registern; x0 ist immer Null.", "ALU, Branch Unit und LSU bekommen ihre Operanden meistens aus diesen Registern."],
        ["alu", "Rechenwerk fuer Addition, Subtraktion, Bitlogik, Shifts, Vergleiche und MUL-Low32.", "Ihr Ergebnis geht zurueck in ein Register oder dient als Speicheradresse."],
        ["branch_unit", "Entscheider fuer bedingte Spruenge.", "Bestimmt, ob der PC normal weiterlaeuft oder zum Branch-Ziel springt."],
        ["load_store_unit", "Adapter zwischen CPU-Werten und byteweisem Speicherzugriff.", "Setzt Byte-Enables und erweitert Load-Ergebnisse passend auf 32 Bit."],
        ["csr_file", "Verwaltungsbereich fuer Traps, Interrupts und Watchdog.", "Liefert bei besonderen Ereignissen die naechste PC-Adresse und merkt Ursache/Zustand."],
        ["riscv_soc_boot", "SoC-Schale um den Core.", "Verbindet Bootloader, Speicher, Timer, UART, Reset und CPU-Core."],
    ], [38 * mm, 66 * mm, 68 * mm]), PageBreak()]

    story += [
        h("3. Der Weg eines Befehls"),
        p("Ein RISC-V-Befehl ist fuer die Hardware zuerst nur ein 32-Bit-Muster. Damit daraus eine Aktion wird, wandert dieses Muster durch mehrere Stationen: Fetch, Decode, Register lesen, Execute, eventuell Memory und Writeback."),
        Diagram("core"),
        p("Nicht jeder Befehl benutzt alle Stationen gleich. Ein ADD braucht keinen Datenspeicher. Ein SW schreibt in den Speicher und hat keinen Register-Writeback. Ein Branch entscheidet nur, welcher PC als naechstes gilt."),
    ]
    story += [h("4. Die FSM als Ablaufplan"), p("Die Zustandsmaschine bringt Ordnung in den Ablauf. Sie sorgt dafuer, dass erst eine Instruktion geholt, dann verstanden, danach mit Registerwerten ausgefuehrt und am Ende sauber abgeschlossen wird."), table([
        ["Phase", "Schulische Erklaerung", "Typische Zustaende"],
        ["Start und Holen", "Die CPU nimmt den PC und fragt damit den Instruktionsspeicher.", "ST_RESET, ST_FETCH, ST_FETCH_WAIT"],
        ["Verstehen", "Der Decoder zerlegt die Instruktion in Registeradressen, Immediate und Steuersignale.", "ST_DECODE"],
        ["Vorbereiten", "Das Registerfile liefert die benoetigten Registerwerte.", "ST_RF_WAIT"],
        ["Ausfuehren", "ALU, Branch Unit, LSU oder CSR-Logik erledigen die eigentliche Aufgabe.", "ST_EXEC_ALU, ST_EXEC_BRANCH, ST_EXEC_LOAD_ADDR, ST_EXEC_STORE_ADDR, ST_EXEC_CSR"],
        ["Abschliessen", "Register, Speicher oder PC werden aktualisiert.", "ST_MEM_READ, ST_MEM_WRITE, ST_WB, ST_TRAP, ST_MRET"],
    ], [38 * mm, 78 * mm, 56 * mm]), p("Weil der Core mehrzyklisch ist, kann man ihn gut beobachten: <code>state_dbg_o</code> zeigt, in welchem Schritt die CPU gerade steht."), PageBreak()]

    story += [
        h("5. Decoder, Registerfile und ALU"),
        p("Diese drei Bausteine bilden den normalen Rechenweg. Der Decoder sagt, welche Register gelesen werden und welche Operation gebraucht wird. Das Registerfile liefert die Zahlen. Die ALU fuehrt die Operation aus. Danach schreibt der Core das Ergebnis in das Zielregister zurueck."),
        p("<b>Beispiel ADD x3, x1, x2:</b> Der Decoder erkennt: lies x1 und x2, addiere beide Werte und schreibe das Ergebnis nach x3. Das Registerfile liefert die Eingaben. Die ALU addiert. Im Writeback-Zustand bekommt x3 das Ergebnis."),
        p("<b>Beispiel ADDI x3, x1, 5:</b> Der zweite Wert kommt nicht aus einem Register, sondern direkt aus der Instruktion. Der Decoder erzeugt den Immediate-Wert 5. Die ALU addiert x1 und 5."),
        h("6. Branches"),
        p("Normalerweise wird nach jedem Befehl der PC um 4 erhoeht. Ein Branch kann diesen normalen Weg aendern. Die Branch Unit vergleicht zwei Registerwerte und entscheidet, ob das Branch-Ziel oder PC+4 der naechste PC wird."),
        p("Zusammenhang: Der Decoder erkennt die Branch-Art, das Registerfile liefert die Vergleichswerte, die Branch Unit entscheidet, und die FSM schreibt danach den passenden PC."),
        PageBreak(),
    ]

    story += [
        h("7. Speicherzugriffe und LSU"),
        p("Die CPU rechnet intern mit 32-Bit-Werten. Der Speicher kann aber auch einzelne Bytes oder Halfwords lesen und schreiben. Die Load/Store Unit uebersetzt deshalb zwischen CPU-Wunsch und 32-Bit-RAM mit vier Byte-Lanes."),
        Diagram("lsu", height=57 * mm),
        p("Bei einem Store erzeugt die LSU die passenden Byte-Enables. Bei einem Load sucht sie die richtige Byte-Lane heraus und erweitert den Wert auf 32 Bit. LB/LH erweitern mit Vorzeichen, LBU/LHU mit Nullen."),
        h("8. CSR, Traps, Timer und Watchdog"),
        p("Nicht jeder PC-Wechsel kommt aus einem normalen Branch. Bei illegalen Befehlen, ECALL, Timer-Interrupt oder Ruecksprung aus einer Ausnahmebehandlung wird die CSR-Datei wichtig."),
        p("CSRs merken, wo die CPU vor einer Ausnahme war (<code>mepc</code>), warum die Ausnahme passiert ist (<code>mcause</code>) und wohin gesprungen werden soll (<code>mtvec</code>). Der Watchdog kann einen Reset erzeugen, wenn er nicht rechtzeitig neu geladen wird."),
        PageBreak(),
    ]

    story += [
        h("9. Die SoC-Schale"),
        p("Ein CPU-Core allein reicht noch nicht, denn irgendwoher muss das Programm kommen und irgendwohin muessen Daten geschrieben werden. <code>riscv_soc_boot</code> verbindet den Core mit Bootloadern, Speicher, Timer, UART und Reset-Logik."),
        table([
            ["Bootpfad", "Einfache Erklaerung"],
            ["UART", "Ein Programm kann byteweise ueber die serielle Schnittstelle geladen werden."],
            ["SPI", "Ein Programm kann aus einem externen Flash gelesen werden."],
            ["External/AXI", "Eine aeussere Logik kann IMEM/DMEM direkt programmieren und den Start steuern."],
        ], [45 * mm, 127 * mm]),
        p("MMIO bedeutet: Peripherie wird wie Speicher angesprochen. Ein Schreibzugriff auf <code>0x40002000</code> sendet zum Beispiel ein UART-Byte. Der Timer liegt in der Region <code>0x40001000</code> bis <code>0x40001FFF</code>."),
        h("10. Gesamtbild"),
        p("Der PC zeigt auf den naechsten Befehl. IMEM liefert diesen Befehl. Der Decoder macht daraus Steuersignale. Das Registerfile liefert Werte. ALU, Branch Unit, LSU oder CSR-Logik erledigen die Aufgabe. Die FSM fuehrt alles in der passenden Reihenfolge aus."),
        p("Dadurch ist der RiscVFSM-Core fuer ein Lehr- und Bring-up-Projekt gut geeignet: Die Bausteine sind getrennt genug, um sie einzeln zu verstehen, aber eng genug verbunden, um zu sehen, wie daraus ein echter Prozessor wird."),
        p("Hinweis: Diese Dokumentation beschreibt den lokalen Stand der Dateien unter <code>RiscVTest.srcs/sources_1/new</code>. Generierte Vivado/IP-Shared-Kopien wurden nicht als primaere Quelle verwendet.", "Smallx"),
    ]

    doc.build(story)


if __name__ == "__main__":
    build()

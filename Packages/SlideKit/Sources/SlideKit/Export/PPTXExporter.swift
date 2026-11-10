import Foundation

/// Skriver ett Deck som .pptx (OOXML). Navet för all export: Keynote och Google Slides öppnar .pptx.
/// Mappning (CONTRACT §1): 1 bildenhet = 6350 EMU, typsnitt pt = size × 0,5.
public enum PPTXExporter {
    public static let emuPerUnit = 6350.0

    public static func export(_ deck: Deck, assets: AssetStore, now: Date = Date()) throws -> Data {
        var zip = ZipWriter()
        let n = deck.slides.count
        let slideNumber = Dictionary(uniqueKeysWithValues: deck.slides.enumerated().map { ($1.id, $0 + 1) })

        // Media: varje använd bild en gång, under sitt innehålls-ID.
        // Ljud görs om till WAV (krav för klickljud) och får namnet <hash>.wav.
        let soundIDs = Set(deck.slides.flatMap { $0.elements.compactMap(\.sound) })
        var media: [String: Data] = [:]
        for id in deck.assetIDs.subtracting(soundIDs).sorted() {
            if let d = assets.data(id) { media[id] = d }
        }
        var sounds: [String: (name: String, data: Data)] = [:]
        for id in soundIDs.sorted() {
            guard let d = assets.data(id) else { continue }
            let ext = (id as NSString).pathExtension
            guard let wav = AudioConvert.wav(d, ext: ext) else { continue }
            sounds[id] = ((id as NSString).deletingPathExtension + ".wav", wav)
        }

        zip.add("[Content_Types].xml", contentTypes(deck))
        zip.add("_rels/.rels", rootRels)
        zip.add("docProps/core.xml", core(title: deck.title, date: now))
        zip.add("docProps/app.xml", app(slides: n))
        zip.add("ppt/presentation.xml", presentation(slides: n))
        zip.add("ppt/_rels/presentation.xml.rels", presentationRels(slides: n))
        zip.add("ppt/presProps.xml", "\(xmlHead)<p:presentationPr \(ns)/>")
        zip.add("ppt/tableStyles.xml", "\(xmlHead)<a:tblStyleLst xmlns:a=\"\(nsA)\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>")
        zip.add("ppt/slideMasters/slideMaster1.xml", slideMaster)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([
            ("rId1", relLayout, "../slideLayouts/slideLayout1.xml", false),
            ("rId2", relTheme, "../theme/theme1.xml", false),
        ]))
        zip.add("ppt/slideLayouts/slideLayout1.xml", slideLayout)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([
            ("rId1", relMaster, "../slideMasters/slideMaster1.xml", false),
        ]))
        zip.add("ppt/theme/theme1.xml", theme)
        zip.add("ppt/theme/theme2.xml", theme)
        zip.add("ppt/notesMasters/notesMaster1.xml", notesMaster)
        zip.add("ppt/notesMasters/_rels/notesMaster1.xml.rels", rels([
            ("rId1", relTheme, "../theme/theme2.xml", false),
        ]))

        for (i, slide) in deck.slides.enumerated() {
            let num = i + 1
            var w = SlideWriter(slide: slide, media: media, sounds: sounds.mapValues(\.name), slideNumber: slideNumber)
            let xml = w.write()
            var r = w.rels
            r.insert(("rId1", relLayout, "../slideLayouts/slideLayout1.xml", false), at: 0)
            if hasNotes(slide) {
                r.append(("rIdNotes", relNotesSlide, "../notesSlides/notesSlide\(num).xml", false))
                zip.add("ppt/notesSlides/notesSlide\(num).xml", notesSlide(slide.notes))
                zip.add("ppt/notesSlides/_rels/notesSlide\(num).xml.rels", rels([
                    ("rId1", relNotesMaster, "../notesMasters/notesMaster1.xml", false),
                    ("rId2", relSlide, "../slides/slide\(num).xml", false),
                ]))
            }
            zip.add("ppt/slides/slide\(num).xml", xml)
            zip.add("ppt/slides/_rels/slide\(num).xml.rels", rels(r))
        }
        for (id, d) in media.sorted(by: { $0.key < $1.key }) { zip.add("ppt/media/\(id)", d) }
        for (_, snd) in sounds.sorted(by: { $0.key < $1.key }) { zip.add("ppt/media/\(snd.name)", snd.data) }
        return zip.finish()
    }

    static func hasNotes(_ s: Slide) -> Bool { !s.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - En bild

    struct SlideWriter {
        let slide: Slide
        let media: [String: Data]
        /// ljud-asset-id → filnamn i ppt/media (WAV)
        let sounds: [String: String]
        let slideNumber: [UUID: Int]
        var rels: [(String, String, String, Bool)] = []
        private var nextRel = 2
        private var nextShape = 2
        private var mediaRel: [String: String] = [:]
        private var soundRels: [String: String] = [:]
        /// element-id → shapens id i spTree (spid i animationerna) och om det är en p:sp
        private var shapeIDs: [UUID: (id: Int, isSp: Bool)] = [:]

        init(slide: Slide, media: [String: Data], sounds: [String: String] = [:], slideNumber: [UUID: Int]) {
            self.slide = slide; self.media = media; self.sounds = sounds; self.slideNumber = slideNumber
        }

        mutating func soundRel(_ assetID: String) -> (rel: String, name: String)? {
            guard let name = sounds[assetID] else { return nil }
            if let r = soundRels[assetID] { return (r, name) }
            let r = rel(relAudio, "../media/\(name)")
            soundRels[assetID] = r
            return (r, name)
        }

        mutating func rel(_ type: String, _ target: String, external: Bool = false) -> String {
            let id = "rId\(nextRel)"; nextRel += 1
            rels.append((id, type, target, external))
            return id
        }

        mutating func imageRel(_ assetID: String) -> String? {
            guard media[assetID] != nil else { return nil }
            if let r = mediaRel[assetID] { return r }
            let r = rel(relImage, "../media/\(assetID)")
            mediaRel[assetID] = r
            return r
        }

        mutating func write() -> String {
            var s = "\(xmlHead)<p:sld \(ns)><p:cSld>"
            s += "<p:bg><p:bgPr>\(background(slide.background))<a:effectLst/></p:bgPr></p:bg>"
            s += "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
            s += "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
            for e in slide.elements { s += element(e) }
            s += "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
            s += transition(slide.transition)
            s += timing()
            s += "</p:sld>"
            return s
        }

        mutating func background(_ f: Fill) -> String {
            switch f {
            case .solid(let c): return solidFill(c)
            case .gradient(let a, let b, let ang): return gradFill(a, b, ang)
            case .image(let id):
                guard let r = imageRel(id) else { return solidFill(.white) }
                return "<a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(r)\"/><a:srcRect/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
            }
        }

        /// Klick på formen: länk och/eller ljud i samma hlinkClick (ljud = `<a:snd>`, kräver WAV).
        mutating func hlink(_ link: ElementLink?, sound: String? = nil) -> String {
            var snd = ""
            if let id = sound, let (r, name) = soundRel(id) {
                snd = "<a:snd r:embed=\"\(r)\" name=\"\(esc(name))\"/>"
            }
            var open: String
            switch link {
            case nil:
                guard !snd.isEmpty else { return "" }
                open = "<a:hlinkClick r:id=\"\" action=\"ppaction://noaction\" highlightClick=\"1\""
            case .nextSlide?:
                open = "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=nextslide\""
            case .previousSlide?:
                open = "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=previousslide\""
            case .slide(let id)?:
                if let n = slideNumber[id] {
                    let r = rel(relSlide, "slide\(n).xml")
                    open = "<a:hlinkClick r:id=\"\(r)\" action=\"ppaction://hlinksldjump\""
                } else if !snd.isEmpty {
                    open = "<a:hlinkClick r:id=\"\" action=\"ppaction://noaction\" highlightClick=\"1\""
                } else {
                    return ""
                }
            case .url(let u)?:
                let r = rel(relHyperlink, u.absoluteString, external: true)
                open = "<a:hlinkClick r:id=\"\(r)\""
            }
            return snd.isEmpty ? open + "/>" : open + ">" + snd + "</a:hlinkClick>"
        }

        mutating func element(_ e: Element) -> String {
            let id = nextShape; nextShape += 1
            let link = hlink(e.link, sound: e.sound)
            let cNvPr = { (name: String) in "<p:cNvPr id=\"\(id)\" name=\"\(esc(name)) \(id)\">\(link)</p:cNvPr>" }
            // Lappar är bara till för dem som bygger.
            if e.isSticky { nextShape -= 1; return "" }
            var content = e.content
            // Omröstningar går inte att exportera levande: frågan och alternativen blir en textruta (CONTRACT §2).
            if case .poll(let p) = content {
                let size = max(min(e.frame.h / Double(p.options.count + 2) * 0.7, 72), 28)
                content = .text(TextBox(text: p.asText, style: TextStyle(size: size, color: p.textColor)))
            }
            // Diagram och nedräkningar exporteras normalt som bilder (Deck.flattened). Det här är reserven.
            if case .timer(let t) = content {
                content = .text(TextBox(text: TimerBox.label(t.seconds), style: TextStyle(size: e.frame.h * 0.6, color: t.color, bold: true, align: .center)))
            }
            if case .chart(let c) = content {
                let size = max(min(e.frame.h / Double(c.labels.count + 2) * 0.7, 64), 26)
                content = .text(TextBox(text: c.asText, style: TextStyle(size: size, color: c.textColor)))
            }
            switch content {
            case .poll, .timer, .chart: return ""
            case .text(let tb):
                shapeIDs[e.id] = (id, true)
                var s = "<p:sp><p:nvSpPr>\(cNvPr("Text"))<p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
                s += "<p:spPr>\(xfrm(e))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>"
                s += textBody(tb)
                s += "</p:sp>"
                return s
            case .shape(let sh):
                shapeIDs[e.id] = (id, true)
                var s = "<p:sp><p:nvSpPr>\(cNvPr("Shape"))<p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
                s += "<p:spPr>\(xfrm(e))<a:prstGeom prst=\"\(sh.kind.pptxPreset)\"><a:avLst/></a:prstGeom>"
                s += solidFill(sh.fill)
                if let st = sh.stroke, sh.strokeWidth > 0 {
                    s += "<a:ln w=\"\(emu(sh.strokeWidth))\">\(solidFill(st))</a:ln>"
                } else {
                    s += "<a:ln><a:noFill/></a:ln>"
                }
                s += "</p:spPr></p:sp>"
                return s
            case .image(let im):
                guard let r = imageRel(im.assetID) else { nextShape -= 1; return "" }
                shapeIDs[e.id] = (id, false)
                var s = "<p:pic><p:nvPicPr>\(cNvPr("Picture"))<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
                s += "<p:blipFill><a:blip r:embed=\"\(r)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                s += "<p:spPr>\(xfrm(e))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
                return s
            }
        }

        /// "Visa när jag trycker" som PowerPoints klicksekvens: en klickgrupp per element i
        /// `slide.revealOrder`. Formerna är synliga i själva XML:en; att de är dolda före klicket
        /// kommer från entréanimationen (set style.visibility → visible).
        mutating func timing() -> String {
            let items = slide.revealOrder.compactMap { id -> (Element, Int, Bool)? in
                guard let e = slide.element(id), e.reveal != nil, let sh = shapeIDs[id] else { return nil }
                return (e, sh.id, sh.isSp)
            }
            guard !items.isEmpty else { return "" }
            var ctn = 2   // 1 = tmRoot, 2 = mainSeq
            func next() -> Int { ctn += 1; return ctn }
            var clicks = ""
            for (e, spid, isSp) in items {
                let effect = e.reveal!
                let tgt = "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl>"
                let grp = isSp ? " grpId=\"0\"" : ""
                let outer = next(), inner = next(), eff = next()
                let (preset, subtype) = Self.preset(effect)
                var behaviours = "<p:set><p:cBhvr><p:cTn id=\"\(next())\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst></p:cTn>\(tgt)<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set>"
                func anim(_ attr: String, _ from: String, _ to: String) -> String {
                    "<p:anim calcmode=\"lin\" valueType=\"num\"><p:cBhvr additive=\"base\"><p:cTn id=\"\(next())\" dur=\"500\" fill=\"hold\"/>\(tgt)<p:attrNameLst><p:attrName>\(attr)</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst><p:tav tm=\"0\"><p:val>\(from)</p:val></p:tav><p:tav tm=\"100000\"><p:val>\(to)</p:val></p:tav></p:tavLst></p:anim>"
                }
                func str(_ v: String) -> String { "<p:strVal val=\"\(v)\"/>" }
                let fadeIn = { "<p:animEffect transition=\"in\" filter=\"fade\"><p:cBhvr><p:cTn id=\"\(next())\" dur=\"500\"/>\(tgt)</p:cBhvr></p:animEffect>" }
                switch effect {
                case .fade:
                    behaviours += fadeIn()
                case .pop, .spin, .confetti:
                    // Zoom (presetID 53, från objektets mitt): bredd/höjd från 0 + intoning.
                    behaviours += anim("ppt_w", "<p:fltVal val=\"0\"/>", str("#ppt_w"))
                    behaviours += anim("ppt_h", "<p:fltVal val=\"0\"/>", str("#ppt_h"))
                    behaviours += fadeIn()
                case .bounce:
                    behaviours += anim("ppt_x", str("#ppt_x"), str("#ppt_x"))
                    behaviours += anim("ppt_y", str("0-#ppt_h/2"), str("#ppt_y"))
                case .flyUp:
                    behaviours += anim("ppt_x", str("#ppt_x"), str("#ppt_x"))
                    behaviours += anim("ppt_y", str("1+#ppt_h/2"), str("#ppt_y"))
                case .flyFromLeft:
                    behaviours += anim("ppt_x", str("0-#ppt_w/2"), str("#ppt_x"))
                    behaviours += anim("ppt_y", str("#ppt_y"), str("#ppt_y"))
                case .flyFromRight:
                    behaviours += anim("ppt_x", str("1+#ppt_w/2"), str("#ppt_x"))
                    behaviours += anim("ppt_y", str("#ppt_y"), str("#ppt_y"))
                }
                // Ljud när elementet visas (PowerPoints "ljud" under effektalternativ).
                var sub = ""
                if let sid = e.sound, let (r, name) = soundRel(sid) {
                    sub = "<p:subTnLst><p:audio><p:cMediaNode><p:cTn id=\"\(next())\" display=\"0\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst></p:cTn><p:tgtEl><p:sndTgt r:embed=\"\(r)\" name=\"\(esc(name))\"/></p:tgtEl></p:cMediaNode></p:audio></p:subTnLst>"
                }
                clicks += "<p:par><p:cTn id=\"\(outer)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst><p:childTnLst>"
                clicks += "<p:par><p:cTn id=\"\(inner)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>"
                clicks += "<p:par><p:cTn id=\"\(eff)\" presetID=\"\(preset)\" presetClass=\"entr\" presetSubtype=\"\(subtype)\" fill=\"hold\"\(grp) nodeType=\"clickEffect\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>\(behaviours)</p:childTnLst>\(sub)</p:cTn></p:par>"
                clicks += "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>"
            }
            var t = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>"
            t += "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>\(clicks)</p:childTnLst></p:cTn>"
            t += "<p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>"
            t += "<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>"
            t += "</p:childTnLst></p:cTn></p:par></p:tnLst>"
            let blds = items.filter { $0.2 }.map { e, spid, _ -> String in
                if case .poll = e.content { return "<p:bldP spid=\"\(spid)\" grpId=\"0\"/>" }
                if case .text = e.content { return "<p:bldP spid=\"\(spid)\" grpId=\"0\"/>" }
                return "<p:bldP spid=\"\(spid)\" grpId=\"0\" animBg=\"1\"/>"
            }
            if !blds.isEmpty { t += "<p:bldLst>\(blds.joined())</p:bldLst>" }
            t += "</p:timing>"
            return t
        }

        /// PowerPoints entréförval: Tona (10), Flyg in (2: 4 = nerifrån, 8 = vänster, 2 = höger), Zooma (53, 16 = från mitten).
        static func preset(_ e: AppearEffect) -> (Int, Int) {
            switch e {
            case .fade: (10, 0)
            case .pop, .spin, .confetti: (53, 16)
            case .bounce: (2, 1)
            case .flyUp: (2, 4)
            case .flyFromLeft: (2, 8)
            case .flyFromRight: (2, 2)
            }
        }

        func textBody(_ tb: TextBox) -> String {
            let st = tb.style
            let algn: String = switch st.align { case .leading: "l"; case .center: "ctr"; case .trailing: "r" }
            let sz = min(max(Int((st.size * 50).rounded()), 100), 400000)
            let rPr = "<a:rPr lang=\"sv-SE\" sz=\"\(sz)\" b=\"\(st.bold ? 1 : 0)\" i=\"\(st.italic ? 1 : 0)\" dirty=\"0\">"
                + solidFill(st.color)
                + "<a:latin typeface=\"\(esc(st.font.rawValue))\"/><a:cs typeface=\"\(esc(st.font.rawValue))\"/>"
            let endPr = "<a:endParaRPr lang=\"sv-SE\" sz=\"\(sz)\" b=\"\(st.bold ? 1 : 0)\" i=\"\(st.italic ? 1 : 0)\" dirty=\"0\">"
                + solidFill(st.color)
                + "<a:latin typeface=\"\(esc(st.font.rawValue))\"/><a:cs typeface=\"\(esc(st.font.rawValue))\"/></a:endParaRPr>"
            var s = "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\" rtlCol=\"0\"><a:noAutofit/></a:bodyPr><a:lstStyle/>"
            let lines = tb.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
            for line in lines {
                s += "<a:p><a:pPr algn=\"\(algn)\"/>"
                if !line.isEmpty { s += "<a:r>\(rPr)</a:rPr><a:t>\(esc(line))</a:t></a:r>" }
                s += endPr + "</a:p>"
            }
            s += "</p:txBody>"
            return s
        }

        func transition(_ t: DeckTransition) -> String {
            switch t {
            case .none: return ""
            case .fade: return "<p:transition spd=\"med\"><p:fade/></p:transition>"
            case .push: return "<p:transition spd=\"med\"><p:push dir=\"l\"/></p:transition>"
            case .wipe: return "<p:transition spd=\"med\"><p:wipe dir=\"l\"/></p:transition>"
            case .zoom: return "<p:transition spd=\"med\"><p:zoom/></p:transition>"
            // "Vänd blad" finns inte i grundformatet: tona är närmast.
            case .flip: return "<p:transition spd=\"med\"><p:fade/></p:transition>"
            }
        }
    }

    // MARK: - Hjälpare

    static func emu(_ units: Double) -> Int { Int((units * emuPerUnit).rounded()) }

    static func xfrm(_ e: Element) -> String {
        var deg = e.rotation.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        let rot = Int((deg * 60000).rounded())
        let rotAttr = rot == 0 ? "" : " rot=\"\(rot)\""
        return "<a:xfrm\(rotAttr)><a:off x=\"\(emu(e.frame.x))\" y=\"\(emu(e.frame.y))\"/><a:ext cx=\"\(max(emu(e.frame.w), 0))\" cy=\"\(max(emu(e.frame.h), 0))\"/></a:xfrm>"
    }

    static func color(_ c: RGBA) -> String {
        if c.a >= 0.999 { return "<a:srgbClr val=\"\(c.hex)\"/>" }
        let a = Int((min(max(c.a, 0), 1) * 100000).rounded())
        return "<a:srgbClr val=\"\(c.hex)\"><a:alpha val=\"\(a)\"/></a:srgbClr>"
    }

    static func solidFill(_ c: RGBA) -> String { "<a:solidFill>\(color(c))</a:solidFill>" }

    static func gradFill(_ a: RGBA, _ b: RGBA, _ angle: Double) -> String {
        var deg = angle.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        return "<a:gradFill flip=\"none\" rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\">\(color(a))</a:gs><a:gs pos=\"100000\">\(color(b))</a:gs></a:gsLst><a:lin ang=\"\(Int((deg * 60000).rounded()))\" scaled=\"0\"/></a:gradFill>"
    }

    /// XML-escape + tar bort tecken som är otillåtna i XML 1.0.
    static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for u in s.unicodeScalars {
            switch u {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                let v = u.value
                if v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D { continue }
                if v == 0xFFFE || v == 0xFFFF { continue }
                out.unicodeScalars.append(u)
            }
        }
        return out
    }

    static func rels(_ items: [(String, String, String, Bool)]) -> String {
        var s = "\(xmlHead)<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (id, type, target, external) in items {
            s += "<Relationship Id=\"\(id)\" Type=\"\(type)\" Target=\"\(esc(target))\"\(external ? " TargetMode=\"External\"" : "")/>"
        }
        return s + "</Relationships>"
    }

    // MARK: - Fasta delar

    static let xmlHead = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""

    static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    static let relSlide = relBase + "slide"
    static let relLayout = relBase + "slideLayout"
    static let relMaster = relBase + "slideMaster"
    static let relTheme = relBase + "theme"
    static let relImage = relBase + "image"
    static let relHyperlink = relBase + "hyperlink"
    static let relNotesSlide = relBase + "notesSlide"
    static let relNotesMaster = relBase + "notesMaster"
    static let relAudio = relBase + "audio"

    static func contentTypes(_ deck: Deck) -> String {
        let pml = "application/vnd.openxmlformats-officedocument.presentationml"
        var s = "\(xmlHead)<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        s += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        s += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        s += "<Default Extension=\"png\" ContentType=\"image/png\"/>"
        s += "<Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>"
        s += "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>"
        s += "<Default Extension=\"gif\" ContentType=\"image/gif\"/>"
        s += "<Default Extension=\"wav\" ContentType=\"audio/wav\"/>"
        s += "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"\(pml).presentation.main+xml\"/>"
        s += "<Override PartName=\"/ppt/presProps.xml\" ContentType=\"\(pml).presProps+xml\"/>"
        s += "<Override PartName=\"/ppt/tableStyles.xml\" ContentType=\"\(pml).tableStyles+xml\"/>"
        s += "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"\(pml).slideMaster+xml\"/>"
        s += "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"\(pml).slideLayout+xml\"/>"
        s += "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"\(pml).notesMaster+xml\"/>"
        s += "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        s += "<Override PartName=\"/ppt/theme/theme2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        for (i, slide) in deck.slides.enumerated() {
            s += "<Override PartName=\"/ppt/slides/slide\(i + 1).xml\" ContentType=\"\(pml).slide+xml\"/>"
            if hasNotes(slide) {
                s += "<Override PartName=\"/ppt/notesSlides/notesSlide\(i + 1).xml\" ContentType=\"\(pml).notesSlide+xml\"/>"
            }
        }
        s += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        s += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        return s + "</Types>"
    }

    static let rootRels = rels([
        ("rId1", relBase + "officeDocument", "ppt/presentation.xml", false),
        ("rId2", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml", false),
        ("rId3", relBase + "extended-properties", "docProps/app.xml", false),
    ])

    static func core(title: String, date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let d = f.string(from: date)
        return "\(xmlHead)<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:title>\(esc(title))</dc:title><dc:creator>Woop Woop Keynote</dc:creator><dcterms:created xsi:type=\"dcterms:W3CDTF\">\(d)</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(d)</dcterms:modified></cp:coreProperties>"
    }

    static func app(slides: Int) -> String {
        "\(xmlHead)<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>Woop Woop Keynote</Application><Slides>\(slides)</Slides><PresentationFormat>Widescreen</PresentationFormat></Properties>"
    }

    static func presentation(slides: Int) -> String {
        var s = "\(xmlHead)<p:presentation \(ns) saveSubsetFonts=\"1\">"
        s += "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>"
        s += "<p:notesMasterIdLst><p:notesMasterId r:id=\"rId6\"/></p:notesMasterIdLst>"
        if slides > 0 {
            s += "<p:sldIdLst>"
            for i in 0..<slides { s += "<p:sldId id=\"\(256 + i)\" r:id=\"rId\(100 + i)\"/>" }
            s += "</p:sldIdLst>"
        }
        s += "<p:sldSz cx=\"12192000\" cy=\"6858000\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/>"
        s += "<p:defaultTextStyle><a:defPPr><a:defRPr lang=\"sv-SE\"/></a:defPPr></p:defaultTextStyle>"
        return s + "</p:presentation>"
    }

    static func presentationRels(slides: Int) -> String {
        var r: [(String, String, String, Bool)] = [
            ("rId1", relMaster, "slideMasters/slideMaster1.xml", false),
            ("rId2", relTheme, "theme/theme1.xml", false),
            ("rId3", relBase + "presProps", "presProps.xml", false),
            ("rId5", relBase + "tableStyles", "tableStyles.xml", false),
            ("rId6", relNotesMaster, "notesMasters/notesMaster1.xml", false),
        ]
        for i in 0..<slides { r.append(("rId\(100 + i)", relSlide, "slides/slide\(i + 1).xml", false)) }
        return rels(r)
    }

    static let emptyTree = "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr></p:spTree>"
    static let clrMap = "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"

    static let slideMaster: String = {
        let lvl = "<a:lvl1pPr><a:defRPr sz=\"1800\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/></a:defRPr></a:lvl1pPr>"
        return "\(xmlHead)<p:sldMaster \(ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>\(emptyTree)</p:cSld>\(clrMap)<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle>\(lvl)</p:titleStyle><p:bodyStyle>\(lvl)</p:bodyStyle><p:otherStyle>\(lvl)</p:otherStyle></p:txStyles></p:sldMaster>"
    }()

    static let slideLayout = "\(xmlHead)<p:sldLayout \(ns) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\">\(emptyTree)</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"

    static func ph(_ id: Int, _ name: String, _ type: String, _ idx: String, _ x: Int, _ y: Int, _ cx: Int, _ cy: Int, body: String = "") -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"\(type)\"\(idx)/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>\(body)</p:sp>"
    }

    static let notesMaster: String = {
        let tree = emptyTree.replacingOccurrences(of: "</p:spTree>", with:
            ph(2, "Slide Image Placeholder 1", "sldImg", " idx=\"2\"", 685800, 1143000, 5486400, 3086100)
            + ph(3, "Notes Placeholder 2", "body", " idx=\"1\"", 685800, 4400550, 5486400, 3600450,
                 body: "<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"sv-SE\"/></a:p></p:txBody>")
            + "</p:spTree>")
        let lvl = "<a:lvl1pPr><a:defRPr sz=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/></a:defRPr></a:lvl1pPr>"
        return "\(xmlHead)<p:notesMaster \(ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>\(tree)</p:cSld>\(clrMap)<p:notesStyle>\(lvl)</p:notesStyle></p:notesMaster>"
    }()

    static func notesSlide(_ notes: String) -> String {
        let lines = notes.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let paras = lines.map { l in
            l.isEmpty ? "<a:p><a:endParaRPr lang=\"sv-SE\"/></a:p>"
                : "<a:p><a:r><a:rPr lang=\"sv-SE\" dirty=\"0\"/><a:t>\(esc(l))</a:t></a:r></a:p>"
        }.joined()
        let tree = emptyTree.replacingOccurrences(of: "</p:spTree>", with:
            "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"1143000\"/><a:ext cx=\"5486400\" cy=\"3086100\"/></a:xfrm></p:spPr></p:sp>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"4400550\"/><a:ext cx=\"5486400\" cy=\"3600450\"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>\(paras)</p:txBody></p:sp>"
            + "</p:spTree>")
        return "\(xmlHead)<p:notes \(ns)><p:cSld>\(tree)</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
    }

    static let theme: String = {
        func sys(_ n: String, _ v: String, _ last: String) -> String { "<a:\(n)><a:sysClr val=\"\(v)\" lastClr=\"\(last)\"/></a:\(n)>" }
        func rgb(_ n: String, _ v: String) -> String { "<a:\(n)><a:srgbClr val=\"\(v)\"/></a:\(n)>" }
        let clr = "<a:clrScheme name=\"Woop\">" + sys("dk1", "windowText", "000000") + sys("lt1", "window", "FFFFFF")
            + rgb("dk2", "44546A") + rgb("lt2", "E7E6E6") + rgb("accent1", "4472C4") + rgb("accent2", "ED7D31")
            + rgb("accent3", "A5A5A5") + rgb("accent4", "FFC000") + rgb("accent5", "5B9BD5") + rgb("accent6", "70AD47")
            + rgb("hlink", "0563C1") + rgb("folHlink", "954F72") + "</a:clrScheme>"
        let font = "<a:fontScheme name=\"Woop\"><a:majorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
        let phFill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let ln = { (w: Int) in "<a:ln w=\"\(w)\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln>" }
        let fmt = "<a:fmtScheme name=\"Woop\"><a:fillStyleLst>\(phFill)\(phFill)\(phFill)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(ln(6350))\(ln(12700))\(ln(19050))</a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(phFill)\(phFill)\(phFill)</a:bgFillStyleLst></a:fmtScheme>"
        return "\(xmlHead)<a:theme xmlns:a=\"\(nsA)\" name=\"Woop\"><a:themeElements>\(clr)\(font)\(fmt)</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }()
}

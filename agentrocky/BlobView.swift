//
//  CatView.swift
//  agentrocky
//

import SwiftUI

enum BlobState {
    case idle, thinking, excited, hurt, dragging, sleeping
}

struct BlobView: View {
    let blobState: BlobState
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, cs in
                let t = tl.date.timeIntervalSinceReferenceDate
                CatDrawer(state: blobState, time: t).draw(ctx: ctx, size: cs)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Paleta

private struct Palette {
    // Gato negro — gradiente casi negro con toque azul oscuro
    static let bodyLight  = Color(red: 0.18, green: 0.18, blue: 0.24)
    static let bodyMid    = Color(red: 0.09, green: 0.09, blue: 0.13)
    static let bodyDark   = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let earInner   = Color(red: 0.35, green: 0.12, blue: 0.18)
    // Iris fino: ámbar dorado
    static let irisColor  = Color(red: 0.90, green: 0.65, blue: 0.10)
    static let nose       = Color(red: 0.70, green: 0.35, blue: 0.42)
    static let lines      = Color(red: 0.05, green: 0.02, blue: 0.08)
    static let whisker    = Color.white.opacity(0.70)
}

// MARK: - Dibujante

private struct CatDrawer {
    let state: BlobState
    let time: Double

    var tailSpeed: Double {
        switch state {
        case .idle: return 0.9;     case .thinking: return 1.8
        case .excited: return 4.5;  case .hurt: return 9.0
        case .dragging: return 1.2; case .sleeping: return 0.3
        }
    }
    var tailAmp: Double {
        switch state {
        case .idle: return 0.22;    case .thinking: return 0.35
        case .excited: return 0.55; case .hurt: return 0.65
        case .dragging: return 0.20; case .sleeping: return 0.10
        }
    }
    var breathe: Double { sin(time * 0.7) * (state == .sleeping ? 0.022 : 0.008) }
    var isBlinking: Bool { time.truncatingRemainder(dividingBy: 3.5) < 0.12 }

    func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // Proporciones — cabeza grande, cuerpo compacto
        let headCY = h * 0.38 + breathe * h
        let headC  = CGPoint(x: w * 0.46, y: headCY)
        let headR  = w * 0.29          // cabeza más grande

        let bodyRect = CGRect(
            x: w * 0.24,
            y: h * 0.58 + breathe * h,
            width: w * 0.50,
            height: h * 0.28          // cuerpo más compacto
        )

        // Orden: cuerpo, orejas, cabeza, cara, bigotes
        drawBody(ctx: ctx, rect: bodyRect, size: size)
        drawEar(ctx: ctx, head: headC, r: headR, left: true)
        drawEar(ctx: ctx, head: headC, r: headR, left: false)
        drawHead(ctx: ctx, center: headC, r: headR, size: size)
        drawFace(ctx: ctx, center: headC, r: headR)
        drawWhiskers(ctx: ctx, center: headC, r: headR)
    }

    // MARK: Cola — curlea visible a la derecha del cuerpo

    func drawTail(ctx: GraphicsContext, bodyRect: CGRect, size: CGSize) {
        let swing = sin(time * tailSpeed) * tailAmp
        let w = size.width, h = size.height

        // La cola sale del costado derecho del cuerpo y curlea dentro del canvas
        let origin = CGPoint(x: bodyRect.maxX - 2, y: bodyRect.midY + 2)
        let mid    = CGPoint(x: w * 0.88, y: h * 0.62 + swing * h * 0.12)
        let tip    = CGPoint(x: w * 0.82, y: h * 0.42 + swing * h * 0.18)

        // Bezier cúbico para la curva de la cola
        var tail = Path()
        tail.move(to: origin)
        tail.addCurve(to: tip,
                      control1: CGPoint(x: mid.x + 4, y: mid.y - 8),
                      control2: CGPoint(x: tip.x + 10, y: tip.y + 12))

        ctx.stroke(tail, with: .color(Palette.bodyDark),
                   style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        ctx.stroke(tail, with: .color(Palette.bodyMid),
                   style: StrokeStyle(lineWidth: 7,  lineCap: .round, lineJoin: .round))
        ctx.stroke(tail, with: .color(Palette.bodyLight.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 3,  lineCap: .round, lineJoin: .round))

        // Punta de la cola — bola redondeada
        let tipBall = CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)
        ctx.fill(Path(ellipseIn: tipBall), with: .color(Palette.bodyLight.opacity(0.6)))
    }

    // MARK: Cuerpo

    func drawBody(ctx: GraphicsContext, rect: CGRect, size: CGSize) {
        let path = Path(ellipseIn: rect)
        ctx.drawLayer { layer in
            layer.clip(to: path)
            layer.fill(
                Path(rect.insetBy(dx: -12, dy: -12)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Palette.bodyLight, location: 0.0),
                        .init(color: Palette.bodyMid,   location: 0.5),
                        .init(color: Palette.bodyDark,  location: 1.0),
                    ]),
                    center: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY),
                    startRadius: 0, endRadius: rect.width * 0.72
                )
            )
        }
    }

    // MARK: Oreja redondeada

    func drawEar(ctx: GraphicsContext, head: CGPoint, r: CGFloat, left: Bool) {
        let sign: CGFloat = left ? -1 : 1

        // Base de la oreja en el borde de la cabeza
        let base1 = CGPoint(x: head.x + sign * r * 0.28, y: head.y - r * 0.72)
        let base2 = CGPoint(x: head.x + sign * r * 0.78, y: head.y - r * 0.60)
        // Punta redondeada — menos extrema
        let tip   = CGPoint(x: head.x + sign * r * 0.58, y: head.y - r * 1.12)
        let tipCP = CGPoint(x: head.x + sign * r * 0.53, y: head.y - r * 1.20)

        // Oreja exterior con punta en bezier (más suave)
        var outer = Path()
        outer.move(to: base1)
        outer.addQuadCurve(to: tip,   control: tipCP)
        outer.addQuadCurve(to: base2, control: tipCP)
        outer.closeSubpath()
        ctx.fill(outer, with: .color(Palette.bodyMid))

        // Interior rosa
        let ic    = CGPoint(x: (base1.x + base2.x + tip.x) / 3,
                            y: (base1.y + base2.y + tip.y) / 3)
        let ib1   = lerp(base1, ic, 0.38)
        let ib2   = lerp(base2, ic, 0.38)
        let itip  = lerp(tip,   ic, 0.32)
        let iCP   = lerp(tipCP, ic, 0.32)

        var inner = Path()
        inner.move(to: ib1)
        inner.addQuadCurve(to: itip, control: iCP)
        inner.addQuadCurve(to: ib2,  control: iCP)
        inner.closeSubpath()
        ctx.fill(inner, with: .color(Palette.earInner.opacity(0.80)))
    }

    // MARK: Cabeza

    func drawHead(ctx: GraphicsContext, center: CGPoint, r: CGFloat, size: CGSize) {
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: rect))
            layer.fill(
                Path(rect.insetBy(dx: -10, dy: -10)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Palette.bodyLight, location: 0.0),
                        .init(color: Palette.bodyMid,   location: 0.55),
                        .init(color: Palette.bodyDark,  location: 1.0),
                    ]),
                    center: CGPoint(x: center.x - r * 0.18, y: center.y - r * 0.18),
                    startRadius: 0, endRadius: r * 1.3
                )
            )
        }
    }

    // MARK: Cara

    func drawFace(ctx: GraphicsContext, center: CGPoint, r: CGFloat) {
        let eyeLX = center.x - r * 0.32
        let eyeRX = center.x + r * 0.32
        let eyeY  = center.y - r * 0.08

        switch state {
        case .hurt:
            drawXEye(ctx: ctx, at: CGPoint(x: eyeLX, y: eyeY), r: r)
            drawXEye(ctx: ctx, at: CGPoint(x: eyeRX, y: eyeY), r: r)
        case .sleeping:
            drawSleepEye(ctx: ctx, at: CGPoint(x: eyeLX, y: eyeY), r: r)
            drawSleepEye(ctx: ctx, at: CGPoint(x: eyeRX, y: eyeY), r: r)
        default:
            // Ojos grandes — pupila muy dilatada (noche)
            let eyeR2 = isBlinking ? r * 0.03 : r * 0.20   // radio del ojo
            let eyeL = CGRect(x: eyeLX - eyeR2, y: eyeY - eyeR2, width: eyeR2 * 2, height: eyeR2 * 2)
            let eyeRR = CGRect(x: eyeRX - eyeR2, y: eyeY - eyeR2, width: eyeR2 * 2, height: eyeR2 * 2)

            // Iris ámbar (anillo fino)
            ctx.fill(Path(ellipseIn: eyeL),  with: .color(Palette.irisColor))
            ctx.fill(Path(ellipseIn: eyeRR), with: .color(Palette.irisColor))

            if !isBlinking {
                // Pupila dilatada — ocupa el 88% del ojo
                let pR = eyeR2 * 0.88
                let pL2  = CGRect(x: eyeLX - pR, y: eyeY - pR, width: pR * 2, height: pR * 2)
                let pR2  = CGRect(x: eyeRX - pR, y: eyeY - pR, width: pR * 2, height: pR * 2)
                ctx.fill(Path(ellipseIn: pL2), with: .color(.black))
                ctx.fill(Path(ellipseIn: pR2), with: .color(.black))

                // Reflejo pequeño (luz ambiental mínima)
                let gR = eyeR2 * 0.22
                let gL3 = CGRect(x: eyeLX - eyeR2 * 0.38, y: eyeY - eyeR2 * 0.50, width: gR * 2, height: gR * 2)
                let gR3 = CGRect(x: eyeRX - eyeR2 * 0.38, y: eyeY - eyeR2 * 0.50, width: gR * 2, height: gR * 2)
                ctx.fill(Path(ellipseIn: gL3), with: .color(.white.opacity(0.55)))
                ctx.fill(Path(ellipseIn: gR3), with: .color(.white.opacity(0.55)))
            }
        }

        // Nariz triangular pequeña y redondeada
        let ns = r * 0.10
        var nose = Path()
        nose.move(to: CGPoint(x: center.x, y: center.y + r * 0.22))
        nose.addQuadCurve(to: CGPoint(x: center.x - ns, y: center.y + r * 0.12),
                          control: CGPoint(x: center.x - ns * 0.5, y: center.y + r * 0.22))
        nose.addLine(to: CGPoint(x: center.x + ns, y: center.y + r * 0.12))
        nose.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r * 0.22),
                          control: CGPoint(x: center.x + ns * 0.5, y: center.y + r * 0.22))
        ctx.fill(nose, with: .color(Palette.nose))

        // Boca
        var mouth = Path()
        let mY = center.y + r * 0.24
        mouth.move(to: CGPoint(x: center.x - r * 0.12, y: mY))
        mouth.addQuadCurve(to: CGPoint(x: center.x, y: mY + r * 0.09),
                           control: CGPoint(x: center.x - r * 0.04, y: mY + r * 0.13))
        mouth.addQuadCurve(to: CGPoint(x: center.x + r * 0.12, y: mY),
                           control: CGPoint(x: center.x + r * 0.04, y: mY + r * 0.13))
        ctx.stroke(mouth, with: .color(Palette.lines.opacity(0.65)),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
    }

    func drawXEye(ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        let s = r * 0.13
        var x = Path()
        x.move(to: CGPoint(x: p.x - s, y: p.y - s)); x.addLine(to: CGPoint(x: p.x + s, y: p.y + s))
        x.move(to: CGPoint(x: p.x + s, y: p.y - s)); x.addLine(to: CGPoint(x: p.x - s, y: p.y + s))
        ctx.stroke(x, with: .color(Palette.lines), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    func drawSleepEye(ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        var arc = Path()
        arc.move(to: CGPoint(x: p.x - r * 0.13, y: p.y))
        arc.addQuadCurve(to: CGPoint(x: p.x + r * 0.13, y: p.y),
                         control: CGPoint(x: p.x, y: p.y + r * 0.11))
        ctx.stroke(arc, with: .color(Palette.lines.opacity(0.75)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    // MARK: Bigotes

    func drawWhiskers(ctx: GraphicsContext, center: CGPoint, r: CGFloat) {
        let nY = center.y + r * 0.14
        let pairs: [(CGPoint, CGPoint)] = [
            (CGPoint(x: center.x - r * 0.07, y: nY - r * 0.05),
             CGPoint(x: center.x - r * 0.88, y: nY - r * 0.14)),
            (CGPoint(x: center.x - r * 0.07, y: nY + r * 0.02),
             CGPoint(x: center.x - r * 0.92, y: nY + r * 0.02)),
            (CGPoint(x: center.x - r * 0.07, y: nY + r * 0.09),
             CGPoint(x: center.x - r * 0.88, y: nY + r * 0.18)),
            (CGPoint(x: center.x + r * 0.07, y: nY - r * 0.05),
             CGPoint(x: center.x + r * 0.88, y: nY - r * 0.14)),
            (CGPoint(x: center.x + r * 0.07, y: nY + r * 0.02),
             CGPoint(x: center.x + r * 0.92, y: nY + r * 0.02)),
            (CGPoint(x: center.x + r * 0.07, y: nY + r * 0.09),
             CGPoint(x: center.x + r * 0.88, y: nY + r * 0.18)),
        ]
        for (a, b) in pairs {
            var w = Path(); w.move(to: a); w.addLine(to: b)
            ctx.stroke(w, with: .color(Palette.whisker),
                       style: StrokeStyle(lineWidth: 0.85, lineCap: .round))
        }
    }

    func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

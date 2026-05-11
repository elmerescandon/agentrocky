//
//  MetricsView.swift
//  agentrocky
//

import SwiftUI

struct MetricsView: View {
    let metrics: UsageMetrics?
    let isLoading: Bool

    var body: some View {
        if isLoading || metrics == nil {
            VStack {
                Spacer()
                Text("cargando métricas…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let m = metrics {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerGrid(m)
                    sectionDivider()
                    sectionLabel("proyectos activos")
                    projectBars(m.topProjects)
                    sectionDivider()
                    sectionLabel("hora pico")
                    hourHistogram(m)
                    sectionDivider()
                    sectionLabel("skills invocados")
                    skillsList(m.topSkills)
                    Spacer(minLength: 8)
                    loadedLabel(m.loadedAt)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header grid

    private func headerGrid(_ m: UsageMetrics) -> some View {
        let streakLabel = m.streak >= 3 ? "🔥 \(m.streak)d" : "\(m.streak)d"
        let cols: [(String, String)] = [
            ("sesiones",  "\(m.totalSessions)"),
            ("preguntas", shortNum(m.totalQuestions)),
            ("tokens",    shortTokens(m.totalTokens)),
            ("racha",     streakLabel),
        ]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 6
        ) {
            ForEach(cols, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.system(size: 15, design: .monospaced).weight(.semibold))
                        .foregroundColor(.white)
                    Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Projects

    private func projectBars(_ projects: [(name: String, count: Int)]) -> some View {
        let maxVal = projects.first?.count ?? 1
        return VStack(alignment: .leading, spacing: 5) {
            if projects.isEmpty {
                Text("sin datos aún")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                ForEach(projects, id: \.name) { name, count in
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.55))
                                .frame(width: geo.size.width * CGFloat(count) / CGFloat(maxVal))
                        }
                        .frame(height: 7)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(2)
                        Text("\(count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Hour histogram

    private func hourHistogram(_ m: UsageMetrics) -> some View {
        let levels = Array("▁▂▃▄▅▆▇█".unicodeScalars)
        let maxVal = m.hourDistribution.values.max() ?? 1

        let barStr = String((0..<24).map { hour -> Character in
            let val = m.hourDistribution[hour] ?? 0
            let idx = val == 0 ? 0 : max(1, Int(Double(val) / Double(maxVal) * Double(levels.count - 1)))
            return Character(levels[min(idx, levels.count - 1)])
        })

        return VStack(alignment: .leading, spacing: 4) {
            Text(barStr)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.8))
                .tracking(1.5)
            HStack {
                Text("0h")
                Spacer()
                if let peak = m.peakHour {
                    Text("pico: \(peak)h")
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("23h")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.32))
        }
        .padding(.bottom, 4)
    }

    // MARK: - Skills

    private func skillsList(_ skills: [(name: String, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if skills.isEmpty {
                Text("sin datos aún")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                ForEach(skills, id: \.name) { skill, count in
                    HStack {
                        Text(skill)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                        Spacer()
                        Text("\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Section helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.32))
            .padding(.bottom, 6)
    }

    private func sectionDivider() -> some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.vertical, 8)
    }

    private func loadedLabel(_ date: Date) -> some View {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return Text("actualizado \(fmt.string(from: date))")
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.2))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Number formatters

    private func shortNum(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private func shortTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000      { return String(format: "%.0fk", Double(n) / 1000) }
        return "\(n)"
    }
}

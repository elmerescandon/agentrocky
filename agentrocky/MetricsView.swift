//
//  MetricsView.swift
//  agentrocky
//

import SwiftUI

struct MetricsView: View {
    let metrics: UsageMetrics?
    let isLoading: Bool

    @State private var selectedMonth = ""

    private let monthNames = ["","ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"]
    private let blue = Color(red: 0.4, green: 0.8, blue: 1.0)

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
            let month = effectiveMonth(m)
            let data  = m.months[month] ?? MonthMetrics()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    monthSelector(m, selected: month)
                    monthStatGrid(data)
                    insightLine(data)
                    sectionDivider()
                    sectionLabel("actividad — \(monthLabel(month))")
                    activityHeatmap(month, data)
                    sectionDivider()
                    sectionLabel("por hora — \(monthLabel(month))")
                    hourBarChart(data)
                    sectionDivider()
                    globalFooter(m)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Month selector

    private func monthSelector(_ m: UsageMetrics, selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(m.availableMonths, id: \.self) { mk in
                    Button { selectedMonth = mk } label: {
                        Text(monthLabel(mk))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(mk == selected ? .white : .white.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(mk == selected ? Color.white.opacity(0.1) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Month stat grid

    private func monthStatGrid(_ data: MonthMetrics) -> some View {
        let cols: [(String, String)] = [
            ("out tokens", shortTokens(data.totalTokens)),
            ("preguntas", shortNum(data.totalQuestions)),
            ("sesiones",  "\(data.totalSessions)"),
        ]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
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
        .padding(.bottom, 6)
    }

    // MARK: - Insight line

    private func insightLine(_ data: MonthMetrics) -> some View {
        let calendar = Calendar.current
        let dayNames = ["dom","lun","mar","mié","jue","vie","sáb"]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        var dowCounts = [Int: Int]()
        for (ds, count) in data.dailyQuestions {
            if let date = fmt.date(from: ds) {
                let dow = calendar.component(.weekday, from: date) - 1
                dowCounts[dow, default: 0] += count
            }
        }
        let peakDowName = dowCounts.max(by: { $0.value < $1.value })
            .map { dayNames[$0.key] } ?? "—"
        let peakHourStr = data.peakHour.map { "\($0)h" } ?? "—"
        let peakDayStr: String = {
            guard let ds = data.peakDay, let date = fmt.date(from: ds) else { return "—" }
            let df = DateFormatter()
            df.dateFormat = "d MMM"
            df.locale = Locale(identifier: "es_ES")
            return df.string(from: date)
        }()

        return HStack(spacing: 0) {
            stat("semana", peakDowName)
            Text("  ·  ").foregroundColor(.white.opacity(0.2))
            stat("hora",   peakHourStr)
            Text("  ·  ").foregroundColor(.white.opacity(0.2))
            stat("día",    peakDayStr)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.bottom, 4)
    }

    // MARK: - Activity heatmap (días del mes)

    private func activityHeatmap(_ monthKey: String, _ data: MonthMetrics) -> some View {
        let calendar = Calendar.current
        let parts    = monthKey.split(separator: "-")
        guard parts.count == 2,
              let yr = Int(parts[0]), let mo = Int(parts[1]),
              let firstDay = calendar.date(from: DateComponents(year: yr, month: mo, day: 1))
        else { return AnyView(EmptyView()) }

        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let today       = calendar.startOfDay(for: Date())
        let fmt         = DateFormatter()
        fmt.dateFormat  = "yyyy-MM-dd"
        let dayFmt      = DateFormatter()
        dayFmt.dateFormat = "d"

        let dates: [Date] = (0..<daysInMonth).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }
        let maxVal = max(1, data.dailyQuestions.values.max() ?? 1)
        let cellH: CGFloat = 18
        let gap:   CGFloat = 3

        return AnyView(
            GeometryReader { geo in
                let cellW = max(4, (geo.size.width - gap * CGFloat(daysInMonth - 1)) / CGFloat(daysInMonth))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: gap) {
                        ForEach(0..<daysInMonth, id: \.self) { i in
                            let date     = dates[i]
                            let isFuture = date > today
                            let v        = isFuture ? 0 : (data.dailyQuestions[fmt.string(from: date)] ?? 0)
                            let dow      = calendar.component(.weekday, from: date)
                            let isWknd   = dow == 1 || dow == 7
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isFuture
                                      ? Color.clear
                                      : v == 0
                                          ? Color.white.opacity(isWknd ? 0.04 : 0.07)
                                          : blue.opacity(0.2 + Double(v) / Double(maxVal) * 0.72))
                                .frame(width: cellW, height: cellH)
                        }
                    }
                    HStack(spacing: gap) {
                        ForEach(0..<daysInMonth, id: \.self) { i in
                            let show = i == 0 || (i + 1) % 5 == 0 || i == daysInMonth - 1
                            Text(show ? dayFmt.string(from: dates[i]) : "")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(.white.opacity(0.28))
                                .frame(width: cellW, alignment: .center)
                        }
                    }
                }
            }
            .frame(height: cellH + 14)
            .padding(.bottom, 4)
        )
    }

    // MARK: - Hour bar chart

    private func hourBarChart(_ data: MonthMetrics) -> some View {
        let maxVal   = max(1, data.hourDistribution.values.max() ?? 1)
        let barMaxH: CGFloat = 40
        let labelH:  CGFloat = 12
        let gap:     CGFloat = 2

        return GeometryReader { geo in
            let barW = max(2, (geo.size.width - gap * 23) / 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<24, id: \.self) { hour in
                        let val    = data.hourDistribution[hour] ?? 0
                        let h      = CGFloat(val) / CGFloat(maxVal) * barMaxH
                        let isPeak = hour == data.peakHour
                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(blue.opacity(val == 0 ? 0.07 : (isPeak ? 0.9 : 0.42)))
                                .frame(width: barW, height: max(1, h))
                        }
                        .frame(width: barW, height: barMaxH)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        let show = hour == 0 || hour == 6 || hour == 12 || hour == 18 || hour == 23
                        Text(show ? "\(hour)h" : "")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.white.opacity(0.28))
                            .frame(width: barW + gap, alignment: .leading)
                    }
                }
                .frame(height: labelH)
            }
        }
        .frame(height: barMaxH + labelH + 4)
        .padding(.bottom, 4)
    }

    // MARK: - Global footer

    private func globalFooter(_ m: UsageMetrics) -> some View {
        let streakLabel = m.streak >= 3 ? "🔥 \(m.streak)d" : "\(m.streak)d"
        return HStack(spacing: 16) {
            statSmall("racha",    streakLabel)
            statSmall("sesiones", "\(m.totalSessions)")
            statSmall("out tkns", shortTokens(m.totalTokens))
            Spacer()
            loadedLabel(m.loadedAt)
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private func effectiveMonth(_ m: UsageMetrics) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        let current = fmt.string(from: Date())
        if !selectedMonth.isEmpty && m.months[selectedMonth] != nil { return selectedMonth }
        return m.availableMonths.contains(current) ? current : (m.availableMonths.first ?? current)
    }

    private func monthLabel(_ mk: String) -> String {
        let parts = mk.split(separator: "-")
        guard parts.count == 2, let mo = Int(parts[1]) else { return mk }
        let yr = String(parts[0].suffix(2))
        return "\(monthNames[mo]) \(yr)"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label + " ").foregroundColor(.white.opacity(0.32))
            Text(value).foregroundColor(.white.opacity(0.85))
        }
    }

    private func statSmall(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.white.opacity(0.28))
            Text(value)
                .foregroundColor(.white.opacity(0.55))
        }
        .font(.system(size: 9, design: .monospaced))
    }

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
    }

    private func shortNum(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private func shortTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000      { return String(format: "%.0fk", Double(n) / 1000) }
        return "\(n)"
    }
}

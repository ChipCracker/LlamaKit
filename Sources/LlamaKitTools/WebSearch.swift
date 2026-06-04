//
//  WebSearch.swift
//  Real web search via the DuckDuckGo "Lite" HTML endpoint (no API key).
//
//  Parses the HTML result list from lite.duckduckgo.com → real web hits
//  (title · snippet · URL).
//
//  Caveats:
//  - HTML scraping is FRAGILE: if DuckDuckGo changes its markup the parser must
//    be updated. Also a ToS grey area.
//  - Sends the query to DuckDuckGo → not offline anymore.
//  - A browser User-Agent is required, otherwise a block page is returned.
//
import Foundation

public enum WebSearch {
    /// Runs the search and returns a compact, model-readable result (title ·
    /// snippet · URL of the top hits, truncated to stay token-budget friendly).
    public static func run(query: String, maxResults: Int = 5) async -> String {
        var comps = URLComponents(string: "https://lite.duckduckgo.com/lite/")!
        comps.queryItems = [.init(name: "q", value: query)]
        guard let url = comps.url else { return "Error: invalid search query" }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                       + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return "Error: HTTP \(http.statusCode) from DuckDuckGo"
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return "Error: response not readable"
            }
            let results = parse(html, maxResults: maxResults)
            guard !results.isEmpty else {
                return "No web results for \"\(query)\"."
            }
            let text = results.enumerated().map { i, r in
                "\(i + 1). \(r.title)\n   \(r.snippet)\n   \(r.url)"
            }.joined(separator: "\n")
            return text.count > 1800 ? String(text.prefix(1800)) + " …" : text
        } catch {
            return "Error during web search: \(error.localizedDescription)"
        }
    }

    // MARK: - HTML parsing (lite endpoint) — `internal` for tests

    struct Result: Equatable { let title: String; let snippet: String; let url: String }

    private enum Token { case link(href: String, title: String); case snippet(String) }

    static func parse(_ html: String, maxResults: Int) -> [Result] {
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        var tokens: [(loc: Int, tok: Token)] = []

        if let re = try? NSRegularExpression(
            pattern: "<a[^>]*href=\"([^\"]*)\"[^>]*class=['\"]result-link['\"][^>]*>(.*?)</a>",
            options: [.dotMatchesLineSeparators]) {
            re.enumerateMatches(in: html, range: full) { m, _, _ in
                guard let m else { return }
                tokens.append((m.range.location,
                               .link(href: ns.substring(with: m.range(at: 1)),
                                     title: clean(ns.substring(with: m.range(at: 2))))))
            }
        }
        if let re = try? NSRegularExpression(
            pattern: "class=['\"]result-snippet['\"][^>]*>(.*?)</td>",
            options: [.dotMatchesLineSeparators]) {
            re.enumerateMatches(in: html, range: full) { m, _, _ in
                guard let m else { return }
                tokens.append((m.range.location, .snippet(clean(ns.substring(with: m.range(at: 1))))))
            }
        }
        tokens.sort { $0.loc < $1.loc }

        // Walk linearly: a real (non-ad) link binds the next snippet.
        var results: [Result] = []
        var pending: (href: String, title: String)?
        for (_, tok) in tokens {
            switch tok {
            case .link(let href, let title):
                if isAd(href) || title.isEmpty || title.lowercased() == "more info" {
                    pending = nil
                } else {
                    pending = (href, title)
                }
            case .snippet(let s):
                if let p = pending, !s.isEmpty {
                    results.append(Result(title: p.title, snippet: snippetTrim(s), url: realURL(p.href)))
                    pending = nil
                    if results.count >= maxResults { return results }
                }
            }
        }
        return results
    }

    private static func isAd(_ href: String) -> Bool {
        href.contains("ad_provider") || href.contains("ad_domain") || href.contains("y.js")
    }

    /// Unwraps the real target URL from the DuckDuckGo redirect (`…?uddg=<enc>&…`).
    private static func realURL(_ href: String) -> String {
        guard let r = href.range(of: "uddg=") else { return href }
        let enc = href[r.upperBound...].prefix { $0 != "&" }
        return String(enc).removingPercentEncoding ?? String(enc)
    }

    private static func snippetTrim(_ s: String) -> String {
        s.count > 220 ? String(s.prefix(220)) + "…" : s
    }

    /// Strips HTML tags and resolves the most common entities.
    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                       "&#39;": "'", "&#x27;": "'", "&nbsp;": " ", "&#x2F;": "/"] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

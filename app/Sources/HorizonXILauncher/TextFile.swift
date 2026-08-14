import Foundation

/// Splitting and rejoining the config files the launcher edits, without caring which line ending
/// they use.
///
/// **Why this exists.** Swift treats `"\r\n"` as a *single* `Character` — a grapheme cluster —
/// so `text.split(separator: "\n")` does not split a CRLF file at all. It returns the whole file
/// as one element. Every line-based rewrite in this app was written that way, which meant:
///
///   * `horizonxi.ini` ships with CRLF endings, so **nothing the graphics panel wrote ever
///     reached it.** Changing the resolution or the interface size appeared to work, saved
///     correctly, and then did nothing in game.
///   * `GraphicsSettings.read` returned nil on the same file, so the panel could not show the
///     real state either — the two bugs hid each other.
///   * The same silent no-op applied to writing the account into a CRLF profile, and to the
///     addon script and pivot.ini if either ever arrived with CRLF.
///
/// Profiles the launcher creates itself are LF, which is why this went unnoticed: every test
/// against the local server's `lsb.ini` passed.
///
/// Writes preserve whatever ending the file already had, because these files are read by Windows
/// programs under Wine and by the servers' own launchers, and quietly rewriting the whole file's
/// endings is a change nobody asked for.
enum TextFile {
    /// The line ending `text` uses. CRLF wins if there is any, since a mixed file came from a
    /// Windows tool that will keep writing CRLF.
    static func terminator(of text: String) -> String {
        text.contains("\r\n") ? "\r\n" : "\n"
    }

    /// Split into lines regardless of ending, keeping empty lines so indices stay meaningful.
    static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// Rejoin with the ending the original file used.
    static func join(_ lines: [String], terminator: String) -> String {
        lines.joined(separator: terminator)
    }
}

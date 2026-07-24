//
//  StringExtensionsWrapperTests.swift
//  RepoPromptTests
//
//  Tests for C wrapper functions in string_extensions_wrapper.c
//

import XCTest
@testable import ApplyEditsKit

final class StringExtensionsWrapperTests: XCTestCase {
    
    // MARK: - Levenshtein Distance Tests
    
    func testLevenshteinDistanceBasic() throws {
        // Test exact match
        XCTAssertEqual("hello".levenshteinDistance(to: "hello"), 0)
        
        // Test empty strings
        XCTAssertEqual("".levenshteinDistance(to: "hello"), 5)
        XCTAssertEqual("hello".levenshteinDistance(to: ""), 5)
        XCTAssertEqual("".levenshteinDistance(to: ""), 0)
        
        // Test classic example
        XCTAssertEqual("kitten".levenshteinDistance(to: "sitting"), 3)
        
        // Test single character changes
        XCTAssertEqual("hello".levenshteinDistance(to: "hallo"), 1)
        XCTAssertEqual("test".levenshteinDistance(to: "tent"), 1)
        XCTAssertEqual("saturday".levenshteinDistance(to: "sunday"), 3)
    }
    
    func testLevenshteinDistanceWithCap() throws {
        let str1 = "kitten"
        let str2 = "sitting"
        
        // Cap higher than actual distance
        XCTAssertEqual(str1.levenshteinDistance(to: str2, maxAllowedDistance: 5), 3)
        
        // Cap equal to actual distance
        XCTAssertEqual(str1.levenshteinDistance(to: str2, maxAllowedDistance: 3), 3)
        
        // Cap lower than actual distance
        XCTAssertEqual(str1.levenshteinDistance(to: str2, maxAllowedDistance: 2), 3)
        
        // Very small cap
        XCTAssertEqual("completely".levenshteinDistance(to: "different", maxAllowedDistance: 1), 2)
    }
    
    func testLevenshteinDistancePathOptimization() throws {
        // Common prefix
        let path1 = "/Users/john/Documents/project/src/main.swift"
        let path2 = "/Users/john/Documents/project/src/test.swift"
        XCTAssertEqual(path1.levenshteinDistance(to: path2), 4)
        
        // Common suffix
        let file1 = "ComponentA.swift"
        let file2 = "ComponentB.swift"
        XCTAssertEqual(file1.levenshteinDistance(to: file2), 1)
        
        // Both prefix and suffix
        let str1 = "prefix_middle1_suffix"
        let str2 = "prefix_middle2_suffix"
        XCTAssertEqual(str1.levenshteinDistance(to: str2), 1)
    }
    
    func testLevenshteinDistanceUnicode() throws {
        // Accented characters
        XCTAssertEqual("café".levenshteinDistance(to: "cafe"), 1)
        XCTAssertEqual("naïve".levenshteinDistance(to: "naive"), 1)
        
        // Emoji
        XCTAssertEqual("Hello 👋".levenshteinDistance(to: "Hello 🌍"), 1)
        XCTAssertEqual("👍".levenshteinDistance(to: "👎"), 1)
        
        // Mixed scripts
        XCTAssertEqual("hello世界".levenshteinDistance(to: "hello世间"), 1)
    }
    
    // MARK: - Dice Coefficient Tests
    
    func testDiceCoefficientBasic() throws {
        // Identical strings
        XCTAssertEqual("hello".diceCoefficient(against: "hello"), 1.0, accuracy: 0.0001)
        
        // Empty strings
        XCTAssertEqual("".diceCoefficient(against: "hello"), 0.0)
        XCTAssertEqual("hello".diceCoefficient(against: ""), 0.0)
        XCTAssertEqual("".diceCoefficient(against: ""), 0.0)
        
        // Single character
        XCTAssertEqual("a".diceCoefficient(against: "a"), 1.0)
        XCTAssertEqual("a".diceCoefficient(against: "b"), 0.0)
        
        // Two character minimum for bigrams
        XCTAssertEqual("ab".diceCoefficient(against: "ab"), 1.0)
        XCTAssertEqual("ab".diceCoefficient(against: "ba"), 0.0)
        // For "ab" vs "ac": bigrams are ["ab"] and ["ac"], no intersection, so 0.0
        XCTAssertEqual("ab".diceCoefficient(against: "ac"), 0.0, accuracy: 0.0001)
    }
    
    func testDiceCoefficientSimilarity() throws {
        // High similarity
        let score1 = "Foundation".diceCoefficient(against: "Foundational")
        XCTAssertTrue(score1 > 0.6 && score1 < 1.0)
        
        // Moderate similarity
        let score2 = "hello".diceCoefficient(against: "hallo")
        XCTAssertTrue(score2 > 0.4 && score2 < 0.8)
        
        // Low similarity
        let score3 = "abc".diceCoefficient(against: "xyz")
        XCTAssertTrue(score3 < 0.3)
        
        // Case insensitive
        XCTAssertEqual("HELLO".diceCoefficient(against: "hello"), 1.0, accuracy: 0.0001)
    }
    
    func testDiceCoefficientPerformance() throws {
        // Long strings
        let longStr1 = String(repeating: "abcdefghij", count: 100)
        let longStr2 = String(repeating: "abcdefghik", count: 100)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let score = longStr1.diceCoefficient(against: longStr2)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertTrue(score > 0.8)
        XCTAssertTrue(elapsed < 0.01, "Dice coefficient should be fast")
    }
    
    // MARK: - Longest Common Subsequence Tests
    
    func testLongestCommonSubsequence() throws {
        // Basic test
        XCTAssertEqual("abcdef".longestCommonSubsequence(with: "axbdf"), "abdf")
        
        // Empty strings
        XCTAssertEqual("".longestCommonSubsequence(with: "hello"), "")
        XCTAssertEqual("hello".longestCommonSubsequence(with: ""), "")
        XCTAssertEqual("".longestCommonSubsequence(with: ""), "")
        
        // No common subsequence
        XCTAssertEqual("abc".longestCommonSubsequence(with: "xyz"), "")
        
        // Identical strings
        XCTAssertEqual("hello".longestCommonSubsequence(with: "hello"), "hello")
        
        // Interleaved
        XCTAssertEqual("ABCDGH".longestCommonSubsequence(with: "AEDFHR"), "ADH")
        XCTAssertEqual("AGGTAB".longestCommonSubsequence(with: "GXTXAYB"), "GTAB")
    }
    
    func testLongestCommonSubsequenceUnicode() throws {
        // Unicode characters
        XCTAssertEqual("café".longestCommonSubsequence(with: "cafe"), "caf")
        XCTAssertEqual("hello👋world".longestCommonSubsequence(with: "hello🌍world"), "helloworld")
        
        // Chinese characters
        XCTAssertEqual("你好世界".longestCommonSubsequence(with: "你好地球"), "你好")
    }
    
    // MARK: - Similarity Score Tests
    
    func testSimilarityScore() throws {
        // Identical strings
        XCTAssertEqual("hello".similarityFast(to: "hello"), 1.0)
        
        // Short strings (uses Levenshtein)
        let shortSim = "hello".similarityFast(to: "hallo")
        XCTAssertEqual(shortSim, 0.8, accuracy: 0.01)
        
        // Long strings (uses Dice coefficient)
        let longStr1 = String(repeating: "abc", count: 25) + "test"
        let longStr2 = String(repeating: "abc", count: 25) + "best"
        let longSim = longStr1.similarityFast(to: longStr2)
        XCTAssertTrue(longSim > 0.85)
        
        // Edge case: exactly 64 characters
        let str64a = String(repeating: "a", count: 64)
        let str64b = String(repeating: "a", count: 63) + "b"
        let sim64 = str64a.similarityFast(to: str64b)
        XCTAssertTrue(sim64 > 0.95)
        
        // Edge case: 65 characters (triggers Dice)
        let str65a = String(repeating: "a", count: 65)
        let str65b = String(repeating: "a", count: 64) + "b"
        let sim65 = str65a.similarityFast(to: str65b)
        XCTAssertTrue(sim65 > 0.90)
    }
    
    // MARK: - HTML Entity Decoding Tests
    
    func testHTMLEntityDecoding() throws {
        // Basic entities
        XCTAssertEqual("&lt;div&gt;".decodingHTMLEntities(), "<div>")
        XCTAssertEqual("&amp;&amp;".decodingHTMLEntities(), "&&")
        XCTAssertEqual("&quot;hello&quot;".decodingHTMLEntities(), "\"hello\"")
        XCTAssertEqual("it&#39;s".decodingHTMLEntities(), "it's")
        
        // Spaces
        XCTAssertEqual("hello&nbsp;world".decodingHTMLEntities(), "hello world")
        XCTAssertEqual("hello&#160;world".decodingHTMLEntities(), "hello world")
        
        // Mixed content
        XCTAssertEqual("&lt;p&gt;Hello &amp; welcome&lt;/p&gt;".decodingHTMLEntities(), 
                      "<p>Hello & welcome</p>")
        
        // No entities
        XCTAssertEqual("plain text".decodingHTMLEntities(), "plain text")
        
        // Empty string
        XCTAssertEqual("".decodingHTMLEntities(), "")
        
        // Partial entities (should not be decoded)
        XCTAssertEqual("&incomplete".decodingHTMLEntities(), "&incomplete")
        XCTAssertEqual("&lt incomplete".decodingHTMLEntities(), "&lt incomplete")
    }
    
    // MARK: - Whitespace Condensing Tests
    
    func testWhitespaceCondensing() throws {
        // Multiple spaces
        XCTAssertEqual("hello    world".condensingWhitespace(), "hello world")
        
        // Tabs and spaces
        XCTAssertEqual("hello\t\tworld".condensingWhitespace(), "hello world")
        XCTAssertEqual("hello \t \t world".condensingWhitespace(), "hello world")
        
        // Newlines
        XCTAssertEqual("hello\n\nworld".condensingWhitespace(), "hello world")
        XCTAssertEqual("hello\r\nworld".condensingWhitespace(), "hello world")
        
        // Mixed whitespace
        XCTAssertEqual("hello   \t\n\r\n   world".condensingWhitespace(), "hello world")
        
        // Leading/trailing whitespace
        XCTAssertEqual("   hello   ".condensingWhitespace(), " hello ")
        XCTAssertEqual("\t\nhello\n\t".condensingWhitespace(), " hello ")
        
        // NBSP (non-breaking space)
        XCTAssertEqual("hello\u{00A0}\u{00A0}world".condensingWhitespace(), "hello world")
        
        // Empty string
        XCTAssertEqual("".condensingWhitespace(), "")
        
        // Only whitespace
        XCTAssertEqual("   \t\n   ".condensingWhitespace(), " ")
        
        // No whitespace
        XCTAssertEqual("helloworld".condensingWhitespace(), "helloworld")
    }
    
    // MARK: - FNV-1a Hash Tests
    
    func testFNV1a64Hash() throws {
        // Empty string
        XCTAssertEqual("".fnv1a64(), 0xcbf29ce484222325)
        
        // Consistent hashing
        let str = "hello world"
        let hash1 = str.fnv1a64()
        let hash2 = str.fnv1a64()
        XCTAssertEqual(hash1, hash2)
        
        // Different strings produce different hashes
        let hashA = "test".fnv1a64()
        let hashB = "test1".fnv1a64()
        XCTAssertNotEqual(hashA, hashB)
        
        // Known values (can be verified against other FNV-1a implementations)
        // These are example values - adjust based on your implementation
        XCTAssertNotEqual("a".fnv1a64(), "".fnv1a64())
        XCTAssertNotEqual("ab".fnv1a64(), "a".fnv1a64())
        
        // Hash distribution (basic check)
        let strings = ["file1.txt", "file2.txt", "file3.txt", "dir1/file.txt", "dir2/file.txt"]
        let hashes = strings.map { $0.fnv1a64() }
        let uniqueHashes = Set(hashes)
        XCTAssertEqual(uniqueHashes.count, strings.count, "All hashes should be unique")
    }
    
    // MARK: - Indentation Encoding/Decoding Tests
    
    func testIndentationEncoding() throws {
        // Test encoding spaces
        XCTAssertEqual(String.encodeIndentationAsSpaces("    hello"), "<s4>hello")
        XCTAssertEqual(String.encodeIndentationAsSpaces("\t\thello"), "<s8>hello")
        XCTAssertEqual(String.encodeIndentationAsSpaces("  \t  hello"), "<s8>hello") // 2 + 4 + 2 = 8
        
        // Test empty lines
        XCTAssertEqual(String.encodeIndentationAsSpaces("    "), "<s4>")
        XCTAssertEqual(String.encodeIndentationAsSpaces("\t\t"), "<s8>")
        
        // Test no indentation
        XCTAssertEqual(String.encodeIndentationAsSpaces("hello"), "<s0>hello")
        
        // Test decoding
        XCTAssertEqual(String.decodeIndentation("<s4>hello"), "    hello")
        XCTAssertEqual(String.decodeIndentation("<t2>hello"), "\t\thello")
        XCTAssertEqual(String.decodeIndentation("<s0>hello"), "hello")
        
        // Test round-trip
        let original = "    hello world"
        let encoded = String.encodeIndentationAsSpaces(original)
        let decoded = String.decodeIndentation(encoded)
        XCTAssertEqual(decoded, original)
    }
    
    // MARK: - String Escaping/Unescaping Tests
    
    func testStringEscaping() throws {
        // Basic escaping
        XCTAssertEqual("hello\nworld".escapedString(), "hello\\nworld")
        XCTAssertEqual("hello\tworld".escapedString(), "hello\\tworld")
        XCTAssertEqual("hello\rworld".escapedString(), "hello\\rworld")
        XCTAssertEqual("say \"hello\"".escapedString(), "say \\\"hello\\\"")
        XCTAssertEqual("path\\to\\file".escapedString(), "path\\\\to\\\\file")
        
        // Multiple escapes
        XCTAssertEqual("line1\nline2\ttab".escapedString(), "line1\\nline2\\ttab")
        
        // Empty string
        XCTAssertEqual("".escapedString(), "")
        
        // No escaping needed
        XCTAssertEqual("hello world".escapedString(), "hello world")
    }
    
    func testStringUnescaping() throws {
        // Basic unescaping
        XCTAssertEqual("hello\\nworld".unescaped(), "hello\nworld")
        XCTAssertEqual("hello\\tworld".unescaped(), "hello\tworld")
        XCTAssertEqual("hello\\rworld".unescaped(), "hello\rworld")
        XCTAssertEqual("say \\\"hello\\\"".unescaped(), "say \"hello\"")
        XCTAssertEqual("path\\\\to\\\\file".unescaped(), "path\\to\\file")
        
        // Multiple unescapes
        XCTAssertEqual("line1\\nline2\\ttab".unescaped(), "line1\nline2\ttab")
        
        // Empty string
        XCTAssertEqual("".unescaped(), "")
        
        // No unescaping needed
        XCTAssertEqual("hello world".unescaped(), "hello world")
        
        // Invalid escape sequences
        XCTAssertEqual("hello\\xworld".unescaped(), "hello\\xworld")
        XCTAssertEqual("trailing\\".unescaped(), "trailing\\")
    }
    
    func testEscapeUnescapeRoundTrip() throws {
        let testStrings = [
            "hello\nworld",
            "tabs\there\tand\tthere",
            "quotes \"everywhere\"",
            "backslash \\ path",
            "mixed\n\t\"content\"\\here",
            "unicode 你好 世界",
            "emoji 👋 🌍"
        ]
        
        for original in testStrings {
            let escaped = original.escapedString()
            let unescaped = escaped.unescaped()
            XCTAssertEqual(unescaped, original, "Round trip failed for: \(original)")
        }
    }
    
    // MARK: - Integration Tests
    
    func testIntegrationWithExistingAPI() throws {
        // Ensure the refactored functions still work with existing APIs
        
        // isSimilar uses similarityFast internally
        XCTAssertTrue("hello".isSimilar(to: "hallo", threshold: 0.7))
        XCTAssertFalse("hello".isSimilar(to: "world", threshold: 0.7))
        
        // similarity delegates to similarityFast
        XCTAssertEqual("test".similarity(to: "test"), 1.0)
        XCTAssertTrue("test".similarity(to: "tent") > 0.7)
        
        // isFuzzyMatch uses diceCoefficient
        XCTAssertTrue("ViewController".isFuzzyMatch(to: "controller", threshold: 0.5))
        XCTAssertFalse("abc".isFuzzyMatch(to: "xyz", threshold: 0.65))
    }
    
    // MARK: - Additional Levenshtein Tests
    
    func testLevenshteinCombiningCharacter() throws {
        // Note: Current implementation treats combining characters as separate from precomposed
        // "e\u{301}" (e + combining acute) vs "é" (precomposed) = 2 operations
        XCTAssertEqual("e\u{301}".levenshteinDistance(to: "é"), 2)
        XCTAssertEqual("café".levenshteinDistance(to: "cafe\u{301}"), 2)
        
        // Same combining character sequences should match
        XCTAssertEqual("e\u{301}".levenshteinDistance(to: "e\u{301}"), 0)
    }
    
    func testLevenshteinCapExceeded() throws {
        let a = String(repeating: "a", count: 50)
        let b = String(repeating: "b", count: 50)
        let dist = a.levenshteinDistance(to: b, maxAllowedDistance: 3)
        XCTAssertEqual(dist, 4) // cap + 1
    }
    
    func testLevenshteinVeryLongStringsWithTightCap() throws {
        let base = String(repeating: "x", count: 1000)
        let str1 = base + "a"
        let str2 = base + "b"
        
        let dist = str1.levenshteinDistance(to: str2, maxAllowedDistance: 10)
        XCTAssertEqual(dist, 1) // Should find the actual distance despite long strings
    }
    
    func testLevenshteinSymmetry() throws {
        let pairs = [
            ("hello", "world"),
            ("café", "naïve"),
            ("👋🌍", "🌍👋"),
            ("你好世界", "世界你好")
        ]
        
        for (a, b) in pairs {
            let distAB = a.levenshteinDistance(to: b)
            let distBA = b.levenshteinDistance(to: a)
            XCTAssertEqual(distAB, distBA, "Distance should be symmetric for \(a) and \(b)")
        }
    }
    
    // MARK: - Additional Dice Coefficient Tests
    
    func testDiceCoefficientEmojiBigrams() throws {
        // Test with emoji sequences
        let sim1 = "👩‍💻👩‍💻".diceCoefficient(against: "👩‍💻👨‍💻")
        XCTAssertTrue(sim1 > 0 && sim1 < 1.0, "Should have partial similarity")
        
        // Test with flag emojis
        let sim2 = "🇺🇸🇨🇦".diceCoefficient(against: "🇺🇸🇬🇧")
        XCTAssertTrue(sim2 > 0 && sim2 < 1.0)
    }
    
    func testDiceCoefficientVeryShortStrings() throws {
        // Single character - different
        XCTAssertEqual("a".diceCoefficient(against: "b"), 0.0)
        
        // Single character - same (already tested but for completeness)
        XCTAssertEqual("x".diceCoefficient(against: "x"), 1.0)
        
        // Empty vs single char
        XCTAssertEqual("".diceCoefficient(against: "z"), 0.0)
    }
    
    // MARK: - Additional LCS Tests
    
    func testLCSMultibyteCharacters() throws {
        // Flag emojis with different sports
        let lcs1 = "🇨🇦🍁".longestCommonSubsequence(with: "🇨🇦🏒")
        XCTAssertEqual(lcs1, "🇨🇦")
        
        // Mixed emoji and text  
        // LCS finds H (from Hello/Hi), 👋, r (from World/Earth), and 🌍
        let lcs2 = "Hello👋World🌍".longestCommonSubsequence(with: "Hi👋Earth🌍")
        XCTAssertEqual(lcs2, "H👋r🌍")
    }
    
    func testLCSOppositeOrderStress() throws {
        // Generate two strings with no common subsequence
        let str1 = String((0..<100).map { _ in "🌟🌙🌞".randomElement()! })
        let str2 = String((0..<100).map { _ in "🏔️🏖️🏝️".randomElement()! })
        
        let lcs = str1.longestCommonSubsequence(with: str2)
        // Might have some overlap by chance, but should be small
        XCTAssertTrue(lcs.count < 10, "Random emoji strings should have minimal overlap")
    }
    
    // MARK: - Additional Indentation Tests
    
    func testIndentationTabsEncoding() throws {
        // Tab-based encoding through the spaces function (converts to spaces)
        XCTAssertEqual(String.encodeIndentationAsSpaces("\t\tfoo"), "<s8>foo")
        XCTAssertEqual(String.encodeIndentationAsSpaces("\thello"), "<s4>hello")
        
        // Mixed tabs and spaces (1 space + 1 tab + 1 space = 6 spaces)
        XCTAssertEqual(String.encodeIndentationAsSpaces(" \t world"), "<s6>world")
    }
    
    func testIndentationMultiDigitCounts() throws {
        // Test with 10+ indentation
        let spaces12 = String(repeating: " ", count: 12) + "code"
        XCTAssertEqual(String.encodeIndentationAsSpaces(spaces12), "<s12>code")
        
        // Test decode
        XCTAssertEqual(String.decodeIndentation("<s15>text"), String(repeating: " ", count: 15) + "text")
        XCTAssertEqual(String.decodeIndentation("<t10>func"), String(repeating: "\t", count: 10) + "func")
    }
    
    func testIndentationMalformedTags() throws {
        // Missing closing >
        XCTAssertEqual(String.decodeIndentation("<s4 hello"), "<s4 hello")
        
        // Unknown type
        XCTAssertEqual(String.decodeIndentation("<x5>test"), "<x5>test")
        
        // No number
        XCTAssertEqual(String.decodeIndentation("<s>code"), "<s>code")
        
        // Not a tag at all
        XCTAssertEqual(String.decodeIndentation("regular text"), "regular text")
    }
    
    // MARK: - Additional Escape/Unescape Tests
    
    func testEscapeUnescapeMixedSequences() throws {
        let original = "Line1\nTab:\tQuote:\"End"
        let escaped = original.escapedString()
        XCTAssertEqual(escaped, "Line1\\nTab:\\tQuote:\\\"End")
        
        let unescaped = escaped.unescaped()
        XCTAssertEqual(unescaped, original)
    }
    
    func testEscapeUnescapeEdgeCases() throws {
        // Unknown escape code
        XCTAssertEqual("hello\\xworld".unescaped(), "hello\\xworld")
        XCTAssertEqual("test\\qvalue".unescaped(), "test\\qvalue")
        
        // Multiple backslashes
        XCTAssertEqual("\\\\\\\\".unescaped(), "\\\\")
        XCTAssertEqual("\\\\".escapedString(), "\\\\\\\\")
        
        // Escape at start
        XCTAssertEqual("\\nstart".unescaped(), "\nstart")
    }
    
    // MARK: - Additional HTML Entity Tests
    
    func testHTMLEntityUpperCaseAndNumeric() throws {
        // Upper case entities (not standard but sometimes seen)
        XCTAssertEqual("&LT;div&GT;".decodingHTMLEntities(), "&LT;div&GT;") // Should not decode uppercase
        
        // Numeric entities
        XCTAssertEqual("&#60;div&#62;".decodingHTMLEntities(), "&#60;div&#62;") // Not implemented in C version
        XCTAssertEqual("&#x3C;hex&#x3E;".decodingHTMLEntities(), "&#x3C;hex&#x3E;") // Not implemented
        
        // Multiple adjacent
        XCTAssertEqual("&lt;&gt;&amp;".decodingHTMLEntities(), "<>&")
        XCTAssertEqual("&quot;&nbsp;&quot;".decodingHTMLEntities(), "\" \"")
    }
    
    func testHTMLEntityIncomplete() throws {
        // Various incomplete entities
        XCTAssertEqual("&#".decodingHTMLEntities(), "&#")
        XCTAssertEqual("&am".decodingHTMLEntities(), "&am")
        XCTAssertEqual("&".decodingHTMLEntities(), "&")
        XCTAssertEqual("test&".decodingHTMLEntities(), "test&")
    }
    
    // MARK: - Additional Whitespace Tests
    
    func testCondenseUnicodeSpaceCharacters() throws {
        // EM SPACE (U+2003) and EN SPACE (U+2002) are not standard ASCII whitespace
        // The current implementation only handles NBSP specifically
        let emSpace = "\u{2003}"
        let enSpace = "\u{2002}"
        
        // These Unicode spaces are not condensed by the current implementation
        XCTAssertEqual(("a" + emSpace + emSpace + "b").condensingWhitespace(), "a\u{2003}\u{2003}b")
        XCTAssertEqual(("x" + enSpace + "y").condensingWhitespace(), "x\u{2002}y")
        
        // Mix of NBSP and regular space
        let mixed = "hello \u{00A0} \u{00A0} world"
        XCTAssertEqual(mixed.condensingWhitespace(), "hello world")
        
        // NBSP mixed with other characters
        let nbspMixed = "a\u{00A0}b\u{00A0}c"
        XCTAssertEqual(nbspMixed.condensingWhitespace(), "a b c")
        
        // Thin space (U+2009) - not handled by current implementation
        let thinSpace = "\u{2009}"
        XCTAssertEqual(("a" + thinSpace + "b").condensingWhitespace(), "a\u{2009}b") // Not condensed
    }
    
    // MARK: - Additional FNV Tests
    
    func testFNV1aLargeInput() throws {
        // Generate a large string (64KB)
        let largeString = String(repeating: "Lorem ipsum dolor sit amet ", count: 2400)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let hash = largeString.fnv1a64()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertNotEqual(hash, 0)
        XCTAssertTrue(elapsed < 0.01, "Hashing 64KB should be fast")
    }
    
    func testFNV1aCollisionCheck() throws {
        // Generate multiple distinct strings and ensure different hashes
        var hashes = Set<UInt64>()
        
        for i in 0..<100 {
            let str = "testString_\(i)_withSomeMoreContent_\(UUID().uuidString)"
            let hash = str.fnv1a64()
            XCTAssertTrue(hashes.insert(hash).inserted, "Hash collision detected for string \(i)")
        }
    }
    
    // MARK: - Additional Similarity Score Tests
    
    func testSimilarityScoreFallbackToDice() throws {
        // Two 63-char strings differing significantly
        let str1 = String(repeating: "a", count: 63)
        let str2 = String(repeating: "b", count: 63)
        
        // With max 15% difference allowed, this should fallback to Dice
        let sim = str1.similarityFast(to: str2)
        XCTAssertTrue(sim < 0.1) // Dice coefficient should be very low
    }
    
    func testSimilarityScoreLongHighSimilarity() throws {
        // 80-char strings with high similarity
        let base = String(repeating: "hello ", count: 13) // 78 chars
        let str1 = base + "ab"
        let str2 = base + "ac"
        
        let sim = str1.similarityFast(to: str2)
        XCTAssertTrue(sim > 0.9, "Long similar strings should have high similarity")
    }
    
    // MARK: - Performance Tests
    
    func testLevenshteinPerformance() throws {
        let str1 = String(repeating: "a", count: 100)
        let str2 = String(repeating: "a", count: 99) + "b"
        
        measure {
            _ = str1.levenshteinDistance(to: str2)
        }
    }
    
    func testDicePerformance() throws {
        let str1 = String(repeating: "abc", count: 100)
        let str2 = String(repeating: "abd", count: 100)
        
        measure {
            _ = str1.diceCoefficient(against: str2)
        }
    }
    
    func testLCSPerformance() throws {
        let str1 = "ABCDGHIJKLMNOPQRSTUVWXYZ"
        let str2 = "ACEDFHIKMOQSUWY"
        
        measure {
            _ = str1.longestCommonSubsequence(with: str2)
        }
    }
    
    func testWhitespaceCondensingPerformance() throws {
        // Generate 1MB of text with lots of whitespace
        let loremIpsum = "Lorem    ipsum  \t\t dolor   sit \n\n amet,   consectetur \r\n adipiscing   elit. "
        let largeText = String(repeating: loremIpsum, count: 15000)
        
        measure {
            _ = largeText.condensingWhitespace()
        }
    }
    
    func testEscapeUnescapePerformance() throws {
        // Generate 10KB source file-like content
        let sourceCode = """
        func example() {
            let str = "Hello\\nWorld"
            print("Tab:\\t Quote:\\"")
            // Comment with \\ backslash
            return "\\r\\n"
        }
        """
        let largeSource = String(repeating: sourceCode + "\n", count: 500)
        
        measure {
            let escaped = largeSource.escapedString()
            _ = escaped.unescaped()
        }
    }
    
    // MARK: - Split Content Tests
    
    func testSplitContentBasic() throws {
        // Unix line endings
        let unixContent = "line1\nline2\nline3"
        let (unixLines, unixEnding) = String.splitContentPreservingLineEndings(unixContent)
        XCTAssertEqual(unixLines, ["line1", "line2", "line3"])
        XCTAssertEqual(unixEnding, "\n")
        
        // Windows line endings
        let windowsContent = "line1\r\nline2\r\nline3"
        let (winLines, winEnding) = String.splitContentPreservingLineEndings(windowsContent)
        XCTAssertEqual(winLines, ["line1", "line2", "line3"])
        XCTAssertEqual(winEnding, "\r\n")
        
        // Mac line endings
        let macContent = "line1\rline2\rline3"
        let (macLines, macEnding) = String.splitContentPreservingLineEndings(macContent)
        XCTAssertEqual(macLines, ["line1", "line2", "line3"])
        XCTAssertEqual(macEnding, "\r")
    }
    
    func testSplitContentEdgeCases() throws {
        // Empty string
        let (emptyLines, emptyEnding) = String.splitContentPreservingLineEndings("")
        XCTAssertEqual(emptyLines, [])
        XCTAssertEqual(emptyEnding, "\n") // Default
        
        // Single line no ending
        let (singleLines, singleEnding) = String.splitContentPreservingLineEndings("hello")
        XCTAssertEqual(singleLines, ["hello"])
        XCTAssertEqual(singleEnding, "\n") // Default
        
        // Empty lines
        let (blankLines, _) = String.splitContentPreservingLineEndings("\n\n\n")
        XCTAssertEqual(blankLines, ["", "", ""])
        
        // Mixed endings (should detect last one used)
        let mixedContent = "line1\nline2\r\nline3\r"
        let (_, mixedEnding) = String.splitContentPreservingLineEndings(mixedContent)
        XCTAssertEqual(mixedEnding, "\r")
    }
    
    func testSplitContentPreservesWhitespace() throws {
        let content = "  line1  \n\tline2\t\n   "
        let (lines, _) = String.splitContentPreservingLineEndings(content)
        XCTAssertEqual(lines, ["  line1  ", "\tline2\t", "   "])
    }
    
    func testSplitContentPerformance() throws {
        // Generate large content with many lines
        let line = "This is a test line with some content"
        let largeContent = Array(repeating: line, count: 10000).joined(separator: "\n")
        
        measure {
            _ = String.splitContentPreservingLineEndings(largeContent)
        }
    }
    
    // MARK: - Canonical Key Tests
    
    func testCanonicalKeyBasic() throws {
        // Basic normalization
        XCTAssertEqual(String.canonicalKey("Hello World"), "hello world")
        XCTAssertEqual(String.canonicalKey("  HELLO  WORLD  "), "hello world")
        
        // Empty results
        XCTAssertNil(String.canonicalKey(""))
        XCTAssertNil(String.canonicalKey("   "))
        XCTAssertNil(String.canonicalKey("\t\n"))
    }
    
    func testCanonicalKeyHTMLEntities() throws {
        XCTAssertEqual(String.canonicalKey("&lt;div&gt;"), "<div>")
        XCTAssertEqual(String.canonicalKey("hello&nbsp;world"), "hello world")
        
        // Upper case entities should not be decoded (current behavior)
        XCTAssertEqual(String.canonicalKey("&LT;div&GT;"), "&lt;div&gt;") // lowercased but not decoded
        
        // Numeric entities not supported yet
        XCTAssertEqual(String.canonicalKey("&#60;x&#62;"), "&#60;x&#62;")
    }
    
    func testCanonicalKeyQualifierStripping() throws {
        XCTAssertEqual(String.canonicalKey("public func test()"), "func test()")
        XCTAssertEqual(String.canonicalKey("private var name"), "var name")
        XCTAssertEqual(String.canonicalKey("static class Helper"), "helper") // both static and class are stripped
        XCTAssertEqual(String.canonicalKey("override func draw"), "func draw")
        
        // New qualifiers
        XCTAssertEqual(String.canonicalKey("mutating func update()"), "func update()")
        XCTAssertEqual(String.canonicalKey("async func fetch()"), "func fetch()")
        XCTAssertEqual(String.canonicalKey("throws func validate()"), "func validate()")
        XCTAssertEqual(String.canonicalKey("lazy var data"), "var data")
    }
    
    func testCanonicalKeySeparatorCollapsing() throws {
        XCTAssertEqual(String.canonicalKey("hello----world"), "hello-world")
        XCTAssertEqual(String.canonicalKey("test___case"), "test-case")
        XCTAssertEqual(String.canonicalKey("mixed--__--separators"), "mixed-separators")
        
        // Unicode separators
        XCTAssertEqual(String.canonicalKey("em—dash—test"), "em-dash-test")
        XCTAssertEqual(String.canonicalKey("en–dash–test"), "en-dash-test")
        
        // Long separator runs
        XCTAssertEqual(String.canonicalKey("foo———bar"), "foo-bar")
        XCTAssertEqual(String.canonicalKey("test————————case"), "test-case")
        
        // Mixed Unicode and ASCII separators
        XCTAssertEqual(String.canonicalKey("mixed—__—separators"), "mixed-separators")
        
        // Box drawing characters (if supported)
        XCTAssertEqual(String.canonicalKey("box─────drawing"), "box-drawing")
    }
    
    func testCanonicalKeyDelimiterStripping() throws {
        XCTAssertEqual(String.canonicalKey("function->"), "function")
        XCTAssertEqual(String.canonicalKey("arrow =>"), "arrow")
        XCTAssertEqual(String.canonicalKey("assign :="), "assign")
        XCTAssertEqual(String.canonicalKey("value ="), "value")
        XCTAssertEqual(String.canonicalKey("label:"), "label")
        
        // With trailing spaces
        XCTAssertEqual(String.canonicalKey("test ->  "), "test")
    }
    
    func testCanonicalKeyLengthCapping() throws {
        let longString = String(repeating: "a", count: 200)
        let result = String.canonicalKey(longString)
        XCTAssertEqual(result?.count, 150)
        XCTAssertEqual(result, String(repeating: "a", count: 150))
    }
    
    func testCanonicalKeyComplexExample() throws {
        let input = "PUBLIC  static  func___testMethod() ->  "
        let expected = "func-testmethod()"
        XCTAssertEqual(String.canonicalKey(input), expected)
    }
    
    func testCanonicalKeyEdgeCases() throws {
        // Multiple qualifiers
        XCTAssertEqual(String.canonicalKey("public static override func test()"), "func test()")
        
        // Qualifier-like words that aren't at the start
        XCTAssertEqual(String.canonicalKey("myPublic variable"), "mypublic variable")
        
        // Delimiter in middle of string
        XCTAssertEqual(String.canonicalKey("func test() -> String"), "func test() -> string")
        
        // Multiple delimiters
        XCTAssertEqual(String.canonicalKey("label: value =>"), "label: value")
        
        // NBSP handling - NBSPs get converted to regular spaces which then get condensed
        XCTAssertEqual(String.canonicalKey("hello\u{00A0}\u{00A0}world"), "hello world")
        // Leading/trailing NBSPs should be trimmed
        let nbspTest = String.canonicalKey("\u{00A0}\u{00A0}test\u{00A0}\u{00A0}")
        XCTAssertEqual(nbspTest, "test")
        
        // All whitespace after processing - check what we actually get
        let allWhitespace = String.canonicalKey("   \u{00A0}  \t  ")
        XCTAssertNil(allWhitespace, "Expected nil but got: \(allWhitespace?.debugDescription ?? "nil")")
        
        // Very short strings
        XCTAssertEqual(String.canonicalKey("a"), "a")
        XCTAssertEqual(String.canonicalKey("AB"), "ab")
        
        // Only separators
        XCTAssertEqual(String.canonicalKey("---___---"), "-")
        
        // Only delimiter
        XCTAssertNil(String.canonicalKey("->"))
        XCTAssertNil(String.canonicalKey("   =>   "))
    }
    
    // MARK: - Fuzzy Space Match Tests
    
    func testFuzzySpaceMatchBasic() throws {
        // Exact match
        XCTAssertTrue("hello world".fuzzySpaceMatch("hello world"))
        
        // Flexible whitespace
        XCTAssertTrue("hello world".fuzzySpaceMatch("hello  world"))
        XCTAssertTrue("hello world".fuzzySpaceMatch("hello\tworld"))
        XCTAssertTrue("hello world".fuzzySpaceMatch("hello\n\nworld"))
        
        // Multiple spaces in pattern
        XCTAssertTrue("hello  world".fuzzySpaceMatch("hello world"))
        XCTAssertTrue("hello  world".fuzzySpaceMatch("hello\t\tworld"))
        
        // No match
        XCTAssertFalse("hello world".fuzzySpaceMatch("helloworld"))
        XCTAssertFalse("hello world".fuzzySpaceMatch("hello"))
    }
    
    func testFuzzySpaceMatchCaseInsensitive() throws {
        XCTAssertTrue("Hello World".fuzzySpaceMatch("hello world", caseInsensitive: true))
        XCTAssertFalse("Hello World".fuzzySpaceMatch("hello world", caseInsensitive: false))
        
        XCTAssertTrue("HELLO world".fuzzySpaceMatch("hello WORLD", caseInsensitive: true))
    }
    
    func testFuzzySpaceMatchEdgeCases() throws {
        // Empty strings
        XCTAssertFalse("".fuzzySpaceMatch(""))
        XCTAssertFalse("".fuzzySpaceMatch("hello"))
        XCTAssertFalse("hello".fuzzySpaceMatch(""))
        
        // Only spaces
        XCTAssertTrue(" ".fuzzySpaceMatch("   "))
        XCTAssertTrue("   ".fuzzySpaceMatch(" "))
        
        // Trailing spaces in pattern
        XCTAssertTrue("hello ".fuzzySpaceMatch("hello"))
        XCTAssertTrue("hello  ".fuzzySpaceMatch("hello"))
        
        // Leading spaces
        XCTAssertFalse(" hello".fuzzySpaceMatch("hello")) // Space must match whitespace
        XCTAssertTrue(" hello".fuzzySpaceMatch("  hello"))
        
        // Tab handling
        XCTAssertTrue("hello\tworld".fuzzySpaceMatch("hello\tworld"))
        XCTAssertFalse("hello\tworld".fuzzySpaceMatch("hello world")) // Tab must match exactly
        
        // Newline handling
        XCTAssertTrue("line1\nline2".fuzzySpaceMatch("line1\nline2"))
        XCTAssertFalse("line1\nline2".fuzzySpaceMatch("line1 line2")) // Newline must match exactly
        
        // Pattern with only spaces should match text with only whitespace
        XCTAssertTrue("   ".fuzzySpaceMatch(" \t "))
    }
    
    func testFuzzySpaceMatchUnicode() throws {
        // NBSP is not treated as space by isspace()
        XCTAssertFalse("hello world".fuzzySpaceMatch("hello\u{00A0}world"))
        XCTAssertTrue("hello\u{00A0}world".fuzzySpaceMatch("hello\u{00A0}world"))
        
        // Unicode text
        XCTAssertTrue("你好 世界".fuzzySpaceMatch("你好  世界"))
        XCTAssertTrue("café crème".fuzzySpaceMatch("café   crème", caseInsensitive: true))
    }
    
    // MARK: - Bulk Dice Tests
    
    func testBulkDiceBestMatch() throws {
        let candidates = ["hello", "hallo", "hullo", "world", "help"]
        
        // Find best match
        let result = String.bulkDiceBestMatch(pattern: "hello", candidates: candidates, threshold: 0.5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.index, 0) // "hello" is exact match
        XCTAssertEqual(result?.score, 1.0)
        
        // Threshold filtering
        let result2 = String.bulkDiceBestMatch(pattern: "hello", candidates: candidates, threshold: 0.9)
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.index, 0) // Only exact match exceeds 0.9
        
        // No matches above threshold
        let result3 = String.bulkDiceBestMatch(pattern: "xyz", candidates: candidates, threshold: 0.5)
        XCTAssertNil(result3)
    }
    
    func testBulkDiceBestMatchCaseInsensitive() throws {
        let candidates = ["hi", "hallo", "HELLO", "world"]
        
        // Case insensitive via dice coefficient
        let result = String.bulkDiceBestMatch(pattern: "hello", candidates: candidates, threshold: 0.5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.index, 2) // "HELLO" matches
        if let score = result?.score {
            XCTAssertEqual(score, 1.0, accuracy: 0.01)
        }
    }
    
    func testBulkDiceEdgeCases() throws {
        // Empty candidates
        let result1 = String.bulkDiceBestMatch(pattern: "test", candidates: [], threshold: 0.5)
        XCTAssertNil(result1)
        
        // Single candidate
        let result2 = String.bulkDiceBestMatch(pattern: "test", candidates: ["test"], threshold: 0.5)
        XCTAssertEqual(result2?.index, 0)
        XCTAssertEqual(result2?.score, 1.0)
        
        // All candidates below threshold
        let candidates = ["abc", "def", "ghi"]
        let result3 = String.bulkDiceBestMatch(pattern: "xyz", candidates: candidates, threshold: 0.8)
        XCTAssertNil(result3)
        
        // Multiple good matches - should return best
        let candidates2 = ["test", "testing", "tester", "tests"]
        let result4 = String.bulkDiceBestMatch(pattern: "test", candidates: candidates2, threshold: 0.5)
        XCTAssertEqual(result4?.index, 0) // Exact match
        XCTAssertEqual(result4?.score, 1.0)
    }
    
    func testBulkDicePerformance() throws {
        // Generate many candidates
        let candidates = (0..<1000).map { "testString\($0)WithSomeContent" }
        let pattern = "testString500WithSomeContent"
        
        measure {
            _ = String.bulkDiceBestMatch(pattern: pattern, candidates: candidates, threshold: 0.8)
        }
    }
    
    // MARK: - Canonical Key Performance
    
    func testCanonicalKeyPerformance() throws {
        // Generate a large document fragment
        let largeDoc = """
        PUBLIC static func processLargeDocument() -> String {
            // This is a very long line with lots of content that needs normalization
            let result = "test----value" + "with___separators" + "and—dashes"
            return result
        }
        """ + String(repeating: " extra content ", count: 500)
        
        measure {
            _ = String.canonicalKey(largeDoc)
        }
    }
    
    func testCanonicalKeyWithManyNBSP() throws {
        // Test the NBSP fix - should be O(N) not O(N²)
        let nbspString = String(repeating: "hello\u{00A0}\u{00A0}world ", count: 100)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = String.canonicalKey(nbspString)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertTrue(elapsed < 0.01, "Should handle many NBSPs efficiently")
    }
    
    // MARK: - Integration Tests
    
    func testIntegrationCanonicalKeyAndDice() throws {
        // Simulate DiffGenerationUtility workflow
        let sourceLines = [
            "public static func calculateTotal() -> Int",
            "private func___updateCache()",
            "override func viewDidLoad() ->",
            "  func  processData()  :  "
        ]
        
        // Normalize all lines
        let canonicalKeys = sourceLines.compactMap { String.canonicalKey($0) }
        XCTAssertEqual(canonicalKeys.count, 4)
        XCTAssertEqual(canonicalKeys[0], "func calculatetotal() -> int")
        XCTAssertEqual(canonicalKeys[1], "func-updatecache()")
        XCTAssertEqual(canonicalKeys[2], "func viewdidload()")
        XCTAssertEqual(canonicalKeys[3], "func processdata()")
        
        // Find best match using bulk dice
        let pattern = "func updatecache"
        let result = String.bulkDiceBestMatch(pattern: pattern, candidates: canonicalKeys, threshold: 0.7)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.index, 1) // Should match the updateCache function
    }
    
    func testIntegrationFuzzySpaceAndCanonical() throws {
        // Test fuzzy space matching with canonical keys
        let input1 = "public  func   test() ->"
        let input2 = "PUBLIC FUNC TEST()"
        
        let key1 = String.canonicalKey(input1)
        let key2 = String.canonicalKey(input2)
        
        XCTAssertEqual(key1, "func test()")
        XCTAssertEqual(key2, "func test()")
        
        // They should fuzzy match even with different spacing
        XCTAssertTrue("func test".fuzzySpaceMatch("func  test"))
        XCTAssertTrue("func test".fuzzySpaceMatch("func\ttest"))
    }
    
    func testIntegrationRealWorldExample() throws {
        // Simulate a real diff generation scenario
        let fileContent = """
        public class ViewController {
            private var cache: [String: Any] = [:]
            
            override func viewDidLoad() {
                super.viewDidLoad()
                setupUI()
            }
            
            private func setupUI() -> Void {
                // Implementation
            }
        }
        """
        
        let lines = fileContent.components(separatedBy: .newlines)
        let canonicalLines = lines.compactMap { String.canonicalKey($0.trimmingCharacters(in: .whitespaces)) }
        
        // Should normalize class declaration - 'class' qualifier is stripped
        XCTAssertTrue(canonicalLines.contains("viewcontroller {"))
        XCTAssertTrue(canonicalLines.contains("var cache: [string: any] = [:]"))
        XCTAssertTrue(canonicalLines.contains("func viewdidload() {"))
        // The setupUI function declaration
        XCTAssertTrue(canonicalLines.contains("func setupui() -> void {"))
        
        // Test finding a method - look for any line containing setupui
        let searchPattern = "setupui"
        var foundIndex: Int?
        for (idx, line) in canonicalLines.enumerated() {
            if line.contains(searchPattern) {
                foundIndex = idx
                break
            }
        }
        XCTAssertNotNil(foundIndex, "Could not find setupui in canonical lines")
    }
    
    // MARK: - Robustness Tests for Bad Data
    
    func testRobustnessEmptyStrings() {
        // Test all functions with empty strings
        XCTAssertEqual("".levenshteinDistance(to: ""), 0)
        XCTAssertEqual("test".levenshteinDistance(to: ""), 4)
        XCTAssertEqual("".levenshteinDistance(to: "test"), 4)
        
        XCTAssertEqual("".diceCoefficient(against: ""), 0.0) // Empty strings return 0
        XCTAssertEqual("test".diceCoefficient(against: ""), 0.0)
        XCTAssertEqual("".diceCoefficient(against: "test"), 0.0)
        
        XCTAssertEqual("".longestCommonSubsequence(with: ""), "")
        XCTAssertEqual("test".longestCommonSubsequence(with: ""), "")
        XCTAssertEqual("".longestCommonSubsequence(with: "test"), "")
        
        XCTAssertEqual("".similarity(to: ""), 1.0)
        XCTAssertEqual("test".similarity(to: ""), 0.0)
        XCTAssertEqual("".similarity(to: "test"), 0.0)
        
        XCTAssertEqual(String.encodeIndentationAsSpaces(""), "<s0>")
        XCTAssertEqual(String.encodeIndentationAsTabs(""), "<t0>")
        XCTAssertEqual(String.decodeIndentation(""), "")
        
        XCTAssertEqual("".decodingHTMLEntities(), "")
        XCTAssertEqual("".condensingWhitespace(), "")
        XCTAssertEqual("".escapedString(), "")
        XCTAssertEqual("".unescaped(), "")
        
        XCTAssertEqual("".fnv1a64(), "".fnv1a64())
        
        XCTAssertNil(String.canonicalKey(""))
        XCTAssertFalse("".fuzzySpaceMatch(""))
        XCTAssertFalse("".fuzzySpaceMatch("test"))
        
        let (lines, ending) = String.splitContentPreservingLineEndings("")
        XCTAssertEqual(lines.count, 0)
        XCTAssertEqual(ending, "\n")
    }
    
    func testRobustnessNullCharacters() {
        // Test with strings containing null characters
        let nullString = "test\0string"
        let nullString2 = "test\0\0string"
        
        // These should handle null characters gracefully
        XCTAssertGreaterThan(nullString.levenshteinDistance(to: "teststring"), 0)
        XCTAssertGreaterThan(nullString.diceCoefficient(against: nullString2), 0)
        XCTAssertNotEqual(nullString.longestCommonSubsequence(with: nullString2), "")
        
        // Encoding functions should handle nulls
        XCTAssertNotEqual(String.encodeIndentationAsSpaces("\0\0test"), "")
        XCTAssertNotEqual(nullString.escapedString(), nullString)
        XCTAssertNotEqual(nullString.condensingWhitespace(), "")
        
        // Split should handle null gracefully
        let (lines, _) = String.splitContentPreservingLineEndings(nullString)
        XCTAssertGreaterThan(lines.count, 0)
    }
    
    func testRobustnessVeryLongStrings() {
        // Test with very long strings
        let longString = String(repeating: "a", count: 10000)
        let longString2 = String(repeating: "b", count: 10000)
        
        // Should not crash on long inputs
        _ = longString.levenshteinDistance(to: longString2, maxAllowedDistance: 100)
        _ = longString.diceCoefficient(against: longString2)
        _ = longString.similarity(to: longString2)
        
        // Canonical key caps at 300 chars
        if let canonical = String.canonicalKey(longString) {
            XCTAssertLessThanOrEqual(canonical.count, 300)
        }
        
        // Should handle long strings
        _ = longString.condensingWhitespace()
        _ = String.fnv1a64(longString)
    }
    
    func testRobustnessSpecialCharacters() {
        // Test with various special characters
        let specialChars = "🎉🎊😀 test\r\n\t\\\"'\u{0000}\u{FEFF}"
        let arabicText = "مرحبا بالعالم"
        let chineseText = "你好世界"
        let mixedText = "Hello 世界 🌍"
        
        // All functions should handle Unicode gracefully
        _ = specialChars.levenshteinDistance(to: arabicText)
        _ = chineseText.diceCoefficient(against: mixedText)
        _ = arabicText.longestCommonSubsequence(with: chineseText)
        
        // Encoding should preserve or properly handle special chars
        _ = specialChars.escapedString()
        _ = specialChars.condensingWhitespace()
        _ = specialChars.decodingHTMLEntities()
        
        // Split should handle various line endings
        let mixedEndings = "Line1\rLine2\nLine3\r\nLine4"
        let (lines, _) = String.splitContentPreservingLineEndings(mixedEndings)
        XCTAssertEqual(lines.count, 4)
    }
    
    func testRobustnessMalformedInput() {
        // Test with malformed HTML entities
        XCTAssertEqual("&notanentity;".decodingHTMLEntities(), "&notanentity;")
        XCTAssertEqual("&#999999999;".decodingHTMLEntities(), "&#999999999;")
        XCTAssertEqual("&#xGGGG;".decodingHTMLEntities(), "&#xGGGG;")
        XCTAssertEqual("&amp".decodingHTMLEntities(), "&amp") // Missing semicolon
        
        // Test with malformed escape sequences
        XCTAssertEqual("\\".unescaped(), "\\")
        XCTAssertEqual("\\x".unescaped(), "\\x")
        XCTAssertEqual("\\u".unescaped(), "\\u")
        
        // Test with malformed indentation encoding
        XCTAssertEqual(String.decodeIndentation("<s>test"), "<s>test")
        XCTAssertEqual(String.decodeIndentation("<sXYZ>test"), "<sXYZ>test")
        XCTAssertEqual(String.decodeIndentation("<t-5>test"), "<t-5>test")
    }
    
    func testRobustnessBulkOperations() {
        // Test bulk dice with empty arrays
        let emptyResult = String.bulkDiceBestMatch(pattern: "test", candidates: [], threshold: 0.5)
        XCTAssertNil(emptyResult)
        
        // Test with nil-like patterns
        let candidates = ["test", "testing", "tester"]
        let result1 = String.bulkDiceBestMatch(pattern: "", candidates: candidates, threshold: 0.5)
        XCTAssertNil(result1)
        
        // Test with very large candidate lists
        let largeCandidates = (0..<1000).map { "test\($0)" }
        let result2 = String.bulkDiceBestMatch(pattern: "test500", candidates: largeCandidates, threshold: 0.9)
        XCTAssertNotNil(result2)
        if let (index, score) = result2 {
            XCTAssertEqual(largeCandidates[index], "test500")
            XCTAssertEqual(score, 1.0)
        }
    }
    
    func testRobustnessFuzzySpaceMatch() {
        // Test edge cases for fuzzy space matching
        XCTAssertFalse("".fuzzySpaceMatch("", caseInsensitive: false))
        XCTAssertFalse("   ".fuzzySpaceMatch("", caseInsensitive: false))
        XCTAssertFalse("".fuzzySpaceMatch("   ", caseInsensitive: false))
        
        // Test with only whitespace
        XCTAssertTrue("   ".fuzzySpaceMatch("     ", caseInsensitive: false))
        XCTAssertTrue("\t\t".fuzzySpaceMatch("  ", caseInsensitive: false))
        XCTAssertTrue(" \t ".fuzzySpaceMatch("   ", caseInsensitive: false))
        
        // Test with special whitespace characters
        let nbsp = "\u{00A0}"
        let emSpace = "\u{2003}"
        XCTAssertTrue("test\(nbsp)word".fuzzySpaceMatch("test word", caseInsensitive: false))
        XCTAssertTrue("test\(emSpace)word".fuzzySpaceMatch("test word", caseInsensitive: false))
    }
    
    func testRobustnessMemorySafety() {
        // Test repeated operations to ensure no memory leaks
        for _ in 0..<100 {
            _ = "test".levenshteinDistance(to: "testing")
            _ = "hello".diceCoefficient(against: "world")
            _ = "abc".longestCommonSubsequence(with: "def")
            _ = "test string".escapedString()
            _ = "test\\nstring".unescaped()
            _ = String.canonicalKey("Test_String_123")
            _ = String.splitContentPreservingLineEndings("line1\nline2\nline3")
        }
        
        // Test with strings that might cause buffer overflows
        let veryLongIndent = String(repeating: " ", count: 1000) + "content"
        _ = String.encodeIndentationAsSpaces(veryLongIndent)
        
        let veryLongEscape = String(repeating: "\\n", count: 1000)
        _ = veryLongEscape.unescaped()
    }
}

// File: RepoPrompt/Utils/DiffEditCreator.swift

import Foundation

public struct DiffEdit {
	public enum EditType {
		case addition
		case deletion
		case equal
	}
	public let type: EditType
	public let lines: [String]
}

public class DiffEditCreator {
	/// Edit distance beyond which one Myers pass is not attempted on a
	/// region. Bounds the backtracking trace to about `maxEditDistance²` Ints
	/// (~32 MB) and the search to O((N + M) · maxEditDistance) steps.
	static let maxEditDistance = 2_048

	/// Line diff (one `DiffEdit` per line).
	///
	/// Each region is first trimmed of its common prefix and suffix. A region
	/// whose edit distance stays within `maxEditDistance` is diffed with
	/// Myers' algorithm (minimal), keeping only the `2d + 1` frontier of each
	/// step for the backtrack. A region with more differences is split on
	/// anchor lines that occur exactly once on each side, in order
	/// (patience diff), and each piece is diffed the same way; only a piece
	/// with no such anchor is emitted as one deletion run plus one addition
	/// run. The result is always a valid edit script.
	public static func myersDiff(oldLines: [String], newLines: [String]) -> [DiffEdit] {
		enum Work {
			case diff(Range<Int>, Range<Int>)
			case equal(Int)
		}

		var edits: [DiffEdit] = []
		edits.reserveCapacity(max(oldLines.count, newLines.count))
		var stack: [Work] = [.diff(0..<oldLines.count, 0..<newLines.count)]

		while let work = stack.popLast() {
			switch work {
			case .equal(let index):
				edits.append(DiffEdit(type: .equal, lines: [oldLines[index]]))

			case .diff(var old, var new):
				while !old.isEmpty, !new.isEmpty, oldLines[old.lowerBound] == newLines[new.lowerBound] {
					edits.append(DiffEdit(type: .equal, lines: [oldLines[old.lowerBound]]))
					old = (old.lowerBound + 1)..<old.upperBound
					new = (new.lowerBound + 1)..<new.upperBound
				}
				var suffix: [Int] = []
				while !old.isEmpty, !new.isEmpty, oldLines[old.upperBound - 1] == newLines[new.upperBound - 1] {
					suffix.append(old.upperBound - 1)
					old = old.lowerBound..<(old.upperBound - 1)
					new = new.lowerBound..<(new.upperBound - 1)
				}
				// Popped after the middle, in ascending order.
				stack.append(contentsOf: suffix.map(Work.equal))

				let a = oldLines[old]
				let b = newLines[new]
				if a.isEmpty || b.isEmpty {
					appendCoarse(a, b, into: &edits)
				} else if editDistanceLowerBound(a, b) <= maxEditDistance,
						  let middle = boundedMyers(Array(a), Array(b)) {
					edits.append(contentsOf: middle)
				} else {
					let anchors = uniqueCommonAnchors(a, b)
					if anchors.isEmpty {
						appendCoarse(a, b, into: &edits)
					} else {
						var pieces: [Work] = []
						var oldStart = old.lowerBound
						var newStart = new.lowerBound
						for anchor in anchors {
							pieces.append(.diff(oldStart..<anchor.old, newStart..<anchor.new))
							pieces.append(.equal(anchor.old))
							oldStart = anchor.old + 1
							newStart = anchor.new + 1
						}
						pieces.append(.diff(oldStart..<old.upperBound, newStart..<new.upperBound))
						stack.append(contentsOf: pieces.reversed())
					}
				}
			}
		}
		return edits
	}

	private static func appendCoarse(_ a: ArraySlice<String>, _ b: ArraySlice<String>, into edits: inout [DiffEdit]) {
		for line in a { edits.append(DiffEdit(type: .deletion, lines: [line])) }
		for line in b { edits.append(DiffEdit(type: .addition, lines: [line])) }
	}

	/// Lines of either side that the other side cannot match (multiset
	/// difference): every edit script needs at least this many edits.
	private static func editDistanceLowerBound(_ a: ArraySlice<String>, _ b: ArraySlice<String>) -> Int {
		var counts: [String: Int] = [:]
		for line in a { counts[line, default: 0] += 1 }
		var unmatchedNew = 0
		for line in b {
			if let count = counts[line], count > 0 {
				counts[line] = count - 1
			} else {
				unmatchedNew += 1
			}
		}
		return counts.values.reduce(unmatchedNew, +)
	}

	/// Lines occurring exactly once in `a` and once in `b`, as (old, new)
	/// index pairs forming the longest run increasing on both sides.
	private static func uniqueCommonAnchors(
		_ a: ArraySlice<String>,
		_ b: ArraySlice<String>
	) -> [(old: Int, new: Int)] {
		var oldCounts: [String: (count: Int, index: Int)] = [:]
		for index in a.indices {
			let entry = oldCounts[a[index]]
			oldCounts[a[index]] = ((entry?.count ?? 0) + 1, index)
		}
		var newCounts: [String: (count: Int, index: Int)] = [:]
		for index in b.indices {
			let entry = newCounts[b[index]]
			newCounts[b[index]] = ((entry?.count ?? 0) + 1, index)
		}
		var pairs: [(old: Int, new: Int)] = []
		for index in a.indices {
			guard let old = oldCounts[a[index]], old.count == 1,
				  let new = newCounts[a[index]], new.count == 1
			else { continue }
			pairs.append((index, new.index))
		}
		guard !pairs.isEmpty else { return [] }

		// Longest increasing subsequence of `new` (pairs are sorted by `old`).
		var tails: [Int] = []          // indices into `pairs`
		var previous = [Int](repeating: -1, count: pairs.count)
		for position in pairs.indices {
			var low = 0
			var high = tails.count
			while low < high {
				let mid = (low + high) / 2
				if pairs[tails[mid]].new < pairs[position].new { low = mid + 1 } else { high = mid }
			}
			if low > 0 { previous[position] = tails[low - 1] }
			if low == tails.count { tails.append(position) } else { tails[low] = position }
		}
		var result: [(old: Int, new: Int)] = []
		var cursor = tails.last ?? -1
		while cursor >= 0 {
			result.append(pairs[cursor])
			cursor = previous[cursor]
		}
		return result.reversed()
	}

	/// Minimal diff of `a` and `b`, or `nil` when it needs more than
	/// `maxEditDistance` edits.
	private static func boundedMyers(_ a: [String], _ b: [String]) -> [DiffEdit]? {
		let n = a.count
		let m = b.count
		let maxD = min(n + m, maxEditDistance)
		let offset = maxD + 1
		var v = [Int](repeating: 0, count: 2 * maxD + 3)
		// trace[d][k + d] = furthest x on diagonal k after step d.
		var trace: [[Int]] = []

		var finalD: Int?
		search: for d in 0...maxD {
			for k in stride(from: -d, through: d, by: 2) {
				var x: Int
				if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
					x = v[offset + k + 1]
				} else {
					x = v[offset + k - 1] + 1
				}
				var y = x - k
				while x < n, y < m, a[x] == b[y] {
					x += 1
					y += 1
				}
				v[offset + k] = x
				if x >= n, y >= m {
					trace.append(Array(v[(offset - d)...(offset + d)]))
					finalD = d
					break search
				}
			}
			trace.append(Array(v[(offset - d)...(offset + d)]))
		}
		guard let finalD else { return nil }

		var reversed: [DiffEdit] = []
		reversed.reserveCapacity(n + m)
		var x = n
		var y = m
		var d = finalD
		while d > 0 {
			let previous = trace[d - 1]
			let k = x - y
			let prevK: Int
			if k == -d || (k != d && previous[k - 1 + (d - 1)] < previous[k + 1 + (d - 1)]) {
				prevK = k + 1
			} else {
				prevK = k - 1
			}
			let prevX = previous[prevK + (d - 1)]
			let prevY = prevX - prevK
			while x > prevX, y > prevY {
				reversed.append(DiffEdit(type: .equal, lines: [a[x - 1]]))
				x -= 1
				y -= 1
			}
			if x == prevX {
				reversed.append(DiffEdit(type: .addition, lines: [b[y - 1]]))
				y -= 1
			} else {
				reversed.append(DiffEdit(type: .deletion, lines: [a[x - 1]]))
				x -= 1
			}
			d -= 1
		}
		while x > 0, y > 0 {
			reversed.append(DiffEdit(type: .equal, lines: [a[x - 1]]))
			x -= 1
			y -= 1
		}
		return reversed.reversed()
	}
}

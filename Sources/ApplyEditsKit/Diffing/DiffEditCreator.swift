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
	/// Edit distance beyond which the middle section is emitted as one
	/// deletion run followed by one addition run instead of a minimal diff.
	/// Bounds the backtracking trace to about `maxEditDistance²` Ints
	/// (~32 MB) and the search to O((N + M) · maxEditDistance) steps.
	static let maxEditDistance = 2_048

	/// Line diff (one `DiffEdit` per line). The common prefix and suffix are
	/// matched first; the remaining middle is diffed with Myers' algorithm,
	/// keeping only the frontier of each step (`2d + 1` Ints) for the
	/// backtrack instead of a full dictionary copy per step.
	public static func myersDiff(oldLines: [String], newLines: [String]) -> [DiffEdit] {
		let n = oldLines.count
		let m = newLines.count
		var prefix = 0
		while prefix < n, prefix < m, oldLines[prefix] == newLines[prefix] {
			prefix += 1
		}
		var suffix = 0
		while suffix < n - prefix, suffix < m - prefix,
			  oldLines[n - 1 - suffix] == newLines[m - 1 - suffix] {
			suffix += 1
		}

		var edits: [DiffEdit] = []
		edits.reserveCapacity(n + m - prefix - suffix)
		for i in 0..<prefix {
			edits.append(DiffEdit(type: .equal, lines: [oldLines[i]]))
		}
		appendMiddleDiff(
			old: oldLines[prefix..<(n - suffix)],
			new: newLines[prefix..<(m - suffix)],
			into: &edits
		)
		for i in (n - suffix)..<n {
			edits.append(DiffEdit(type: .equal, lines: [oldLines[i]]))
		}
		return edits
	}

	private static func appendMiddleDiff(
		old: ArraySlice<String>,
		new: ArraySlice<String>,
		into edits: inout [DiffEdit]
	) {
		let a = Array(old)
		let b = Array(new)
		let n = a.count
		let m = b.count

		func appendCoarse() {
			for line in a { edits.append(DiffEdit(type: .deletion, lines: [line])) }
			for line in b { edits.append(DiffEdit(type: .addition, lines: [line])) }
		}
		if n == 0 || m == 0 {
			appendCoarse()
			return
		}

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

		guard let finalD else {
			appendCoarse()
			return
		}

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
		edits.append(contentsOf: reversed.reversed())
	}
}

import Foundation
import Dispatch
import Synchronization

public class OptimalLineFinderUtility {
	public static func findOptimalLine(for change: FileChange, in content: [String], around startLine: Int, searchRadius: Int = 5) -> Int {
		// Check if the first context line has high similarity
		if let firstContextLine = change.diffChunk.lines.first(where: { $0.type == .context }) {
			if startLine < content.count &&
				firstContextLine.content.similarity(to: content[startLine]) > 0.99 {
				return startLine // Return original line if similarity is very high
			}
		}
		
		let lowerBound = max(0, startLine - searchRadius)
		let upperBound = min(content.count - 1, startLine + searchRadius)
		
		guard lowerBound <= upperBound else { return startLine } // Return original line if bounds are invalid
		
		let candidates = Array(lowerBound...upperBound)

		// Score every candidate line concurrently. The best (score, line) pair
		// lives behind one Mutex; ties go to the lower line number so the
		// result does not depend on which worker finishes first.
		let best = Mutex<(score: Int, line: Int)>((score: -1, line: startLine))
		DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
			let line = candidates[index]
			let score = scoreMatch(diffChunk: change.diffChunk, in: content, startingAt: line)
			best.withLock { current in
				if score > current.score || (score == current.score && line < current.line) {
					current = (score: score, line: line)
				}
			}
		}

		let result = best.withLock { $0 }
		return result.score > -1 ? result.line : startLine // Return original line if no better match found
	}
	
	private static func scoreMatch(diffChunk: DiffChunk, in content: [String], startingAt line: Int) -> Int {
		var score = 0
		var contentIndex = line
		var maxScore = 0  // To normalize the score
		
		for diffLine in diffChunk.lines {
			guard contentIndex < content.count else { break }
			
			switch diffLine.type {
			case .context, .removal:
				let distance = diffLine.content.levenshteinDistance(to: content[contentIndex])
				let lineScore = max(diffLine.content.count, content[contentIndex].count) - distance
				score += lineScore
				maxScore += max(diffLine.content.count, content[contentIndex].count)
				
				// Increment contentIndex for both context and removal lines
				contentIndex += 1
				
			case .addition:
				// Skip additions entirely
				continue
			}
		}
		
		// Normalize the score to be between 0 and 100
		return maxScore > 0 ? Int((Double(score) / Double(maxScore)) * 100) : 0
	}
	
	public static func findOptimalLinesInParallel(for changes: [FileChange], in content: [String], searchRadius: Int = 5) -> [UUID: Int] {
		// Each worker writes only its own slot; the Mutex makes those writes
		// safe to publish back to this thread.
		let slots = Mutex<[Int?]>(Array(repeating: nil, count: changes.count))
		DispatchQueue.concurrentPerform(iterations: changes.count) { index in
			let change = changes[index]
			let optimalLine = findOptimalLine(for: change, in: content, around: change.startLine, searchRadius: searchRadius)
			slots.withLock { $0[index] = optimalLine }
		}

		let lines = slots.withLock { $0 }
		var optimalLines = [UUID: Int](minimumCapacity: changes.count)
		for (change, line) in zip(changes, lines) {
			if let line { optimalLines[change.id] = line }
		}
		return optimalLines
	}
}

// `Sendable` is CHECKED, not asserted: a payload-free String-raw-value enum
// is trivially concurrency-safe. Declared explicitly because Swift does not
// infer Sendable for public types, which forced consumers to declare a
// retroactive conformance instead.
public enum FileAction: String, Sendable {
	case modify
	case create
	case delete
	case rewrite
	case delegateEdit
	
	public func printDetails() {
		print("File Action: \(self.rawValue)")
	}
}


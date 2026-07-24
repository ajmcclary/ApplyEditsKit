public enum FileAction: String {
	case modify
	case create
	case delete
	case rewrite
	case delegateEdit
	
	public func printDetails() {
		print("File Action: \(self.rawValue)")
	}
}


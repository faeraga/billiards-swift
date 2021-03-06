import Foundation
import Logging
import Dispatch
#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

import BilliardLib

func PathLessThan(_ path0: TurnPath, _ path1: TurnPath) -> Bool {
	if path0.count < path1.count {
		return true
	}
	if path0.count > path1.count {
		return false
	}
	let comp0 = path0.monoidalComponents().count
	let comp1 = path1.monoidalComponents().count
	if comp0 < comp1 {
		return true
	}
	return false
}

class Commands {
	let logger: Logger

	init(logger: Logger) {
		self.logger = logger
	}

	func run(_ args: [String]) {
		guard let command = args.first
		else {
			print("Usage: billiards [command]")
			exit(1)
		}
		switch command {
		case "pointset":
			let pointSetCommands = PointSetCommands(logger: logger)
			pointSetCommands.run(Array(args[1...]))
		case "repl":
			let repl = BilliardsRepl(logger: logger)
			repl.run()
		default:
			print("Unrecognized command '\(command)'")
		}
	}
}


extension Vec2: LosslessStringConvertible
	where R: LosslessStringConvertible
{
	public init?(_ description: String) {
		let components = description.split(separator: ",")
		if components.count != 2 {
			return nil
		}
		guard let x = R.self(String(components[0]))
		else { return nil }
		guard let y = R.self(String(components[1]))
		else { return nil }
		self.init(x, y)
	}

}

/*func colorForResult(_ result: PathFeasibility.Result) -> CGColor? {
	if result.feasible {
		return CGColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 0.4)
	} else if result.apexFeasible && result.baseFeasible {
		return CGColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 0.4)
	} else if result.apexFeasible {
		return CGColor(red: 0.1, green: 0.7, blue: 0.1, alpha: 0.4)
	} else if result.baseFeasible {
		return CGColor(red: 0.1, green: 0.1, blue: 0.7, alpha: 0.4)
	}
	return nil
}*/

class PointSetCommands {
	let logger: Logger
	let dataManager: DataManager

	public init(logger: Logger) {
		self.logger = logger
		let path = FileManager.default.currentDirectoryPath
		let dataURL = URL(fileURLWithPath: path).appendingPathComponent("data")
		dataManager = try! DataManager(
			rootURL: dataURL,
			logger: logger)
	}

	func cmd_create(_ args: [String]) {
		let params = ScanParams(args)

		guard let name: String = params["name"]
		else {
			fputs("pointset create: expected name\n", stderr)
			return
		}
		guard let count: Int = params["count"]
		else {
			fputs("pointset create: expected count\n", stderr)
			return
		}
		let gridDensity: UInt = params["gridDensity"] ?? 32

		let pointSet = RandomApexesWithGridDensity(
			gridDensity, count: count)
		logger.info("Generated point set with density: 2^\(gridDensity), count: \(count)")
		try! dataManager.savePointSet(pointSet, name: name)
	}

	func cmd_list() {
		let sets = try! dataManager.listPointSets()
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		dateFormatter.locale = .current
		dateFormatter.timeZone = .current
		let sortedNames = sets.keys.sorted(by: { (a: String, b: String) -> Bool in
			return a.lowercased() < b.lowercased()
		})
		for name in sortedNames {
			guard let metadata = sets[name]
			else { continue }
			var line = name
			if let count = metadata.count {
				line += " (\(count))"
			}
			if let created = metadata.created {
				let localized = dateFormatter.string(from: created)
				line += " \(localized)"
			}
			print(line)
		}
	}

	func cmd_print(_ args: [String]) {
		let params = ScanParams(args)

		guard let name: String = params["name"]
		else {
			fputs("pointset print: expected name\n", stderr)
			return
		}
		let pointSet = try! dataManager.loadPointSet(name: name)
		for p in pointSet.elements {
			print("\(p.x),\(p.y)")
		}
	}

	func cmd_cycleFilter(_ args: [String]) {
		/*let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset cycleFilter: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset cycleFilter: expected index\n", stderr)
			return
		}
		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles: [Int: TurnCycle] =
			(try? dataManager.loadPath(["pointset", name, "cycles"])) ?? [:]
		guard let cycle = knownCycles[index]
		else {
			fputs("point \(index) has no known cycle", stderr)
			return
		}

		//SimpleCycleFeasibilityForTurnPath
		for coords in pointSet.elements {

		}*/
	}

	func cmd_info(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset info: expected name\n", stderr)
			return
		}
		let indexParam: Int? = params["index"]

		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles: [Int: TurnPath] =
			(try? dataManager.loadPath(["pointset", name, "cycles"])) ?? [:]

		if let index = indexParam {
			pointSet.printPointIndex(
				index,
				knownCycles: knownCycles,
				precision: 8)
		} else {
			pointSet.summarize(name: name,
				knownCycles: knownCycles)
		}
	}

	func cmd_copyCycles(
		_ args: [String]
	) {
		let shouldCancel = captureSigint()
		let params = ScanParams(args)
		guard let fromName: String = params["from"]
		else {
			fputs("pointset copyCycles: expected from\n", stderr)
			return
		}
		guard let toName: String = params["to"]
		else {
			fputs("pointset copyCycles: expected to\n", stderr)
			return
		}
		let neighborCount: Int = params["neighbors"] ?? 1

		let fromSet = try! dataManager.loadPointSet(name: fromName)
		let toSet = try! dataManager.loadPointSet(name: toName)
		let fromPaths = dataManager.knownCyclesForPointSet(
			name: fromName)
		var toPaths = dataManager.knownCyclesForPointSet(
			name: toName)

		let fromRadii = fromSet.elements.map(biradialFromApex)
		let fromPolar = fromSet.elements.map {
			 polarFromCartesian($0.asDoubleVec()) }
		let toRadii = toSet.elements.map(biradialFromApex)
		let toPolar = toSet.elements.map {
			polarFromCartesian($0.asDoubleVec()) }
		func pDistance(fromIndex: Int, toIndex: Int) -> Double {
			let d0 = toPolar[toIndex][.B0] - fromPolar[fromIndex][.B0]
			let d1 = toPolar[toIndex][.B1] - fromPolar[fromIndex][.B1]
			return d0 * d0 + d1 * d1
		}
		func rDistance(fromIndex: Int, toIndex: Int) -> Double {
			let rFrom = fromRadii[fromIndex]
			let rTo = toRadii[toIndex]
			let dr0 = rTo[.B0].asDouble() - rFrom[.B0].asDouble()
			let dr1 = rTo[.B1].asDouble() - rFrom[.B1].asDouble()
			return dr0 * dr0 + dr1 * dr1
		}

		let copyQueue = DispatchQueue(
			label: "me.faec.billiards.copyQueue",
			attributes: .concurrent)
		let resultsQueue = DispatchQueue(
			label: "me.faec.billiards.resultsQueue")
		let copyGroup = DispatchGroup()

		var foundCount = 0
		var updatedCount = 0
		var unchangedCount = 0
		for targetIndex in toSet.elements.indices {
			let targetApex = toSet.elements[targetIndex]
			if shouldCancel() { break }

			copyGroup.enter()
			copyQueue.async {
				defer { copyGroup.leave() }
				if shouldCancel() { return }
				let ctx = BilliardsContext(apex: targetApex)

				let candidates = Array(fromSet.elements.indices).sorted {
					pDistance(fromIndex: $0, toIndex: targetIndex) <
					pDistance(fromIndex: $1, toIndex: targetIndex)
				}.prefix(neighborCount).compactMap
				{ (index: Int) -> TurnPath? in
					if let path = fromPaths[index] {
						if let knownPath = toPaths[targetIndex] {
							if !PathLessThan(path, knownPath) {
								return nil
							}
						}
						return path
					}
					return nil
				}.sorted {
					return PathLessThan($0, $1)
				}

				var foundCycle: TurnPath? = nil
				var checked: Set<TurnPath> = []
				for path in candidates {
					if shouldCancel() { return }
					if checked.contains(path) { continue }
					checked.insert(path)

					let result = SimpleCycleFeasibilityForPath(
						path, context: ctx)
					if result?.feasible == true {
						foundCycle = path
						break
					}
				}
				resultsQueue.sync(flags: .barrier) {
					var caption: String
					if let newCycle = foundCycle {
						if let oldCycle = toPaths[targetIndex] {
							updatedCount += 1
							caption = Magenta("updated ") +
								"length \(oldCycle.count) -> \(newCycle.count)"
						} else {
							foundCount += 1
							caption = "cycle found"
						}
						toPaths[targetIndex] = newCycle
						toSet.printPointIndex(
							targetIndex,
							knownCycles: toPaths,
							precision: 8,
							caption: caption)
					} else {
						unchangedCount += 1
					}
				}
			}
		}
		copyGroup.wait()
		if foundCount > 0 || updatedCount > 0 {
			print("\(foundCount) found, \(updatedCount) updated, \(unchangedCount) unchanged")
			print("saving...")
			try! dataManager.saveKnownCycles(
				toPaths, pointSetName: toName)
		}
	}

	func cmd_validate(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset validate: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset validate: expected index\n", stderr)
			return
		}

		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)

		if index < 0 || index >= pointSet.elements.count {
			fputs("\(name) has no element at index \(index)", stderr)
			return
		}
		let point = pointSet.elements[index]
		guard let path = knownCycles[index]
		else {
			fputs("\(name)[\(index)] has no known cycle", stderr)
			return
		}
		let ctx = BilliardsContext(apex: point)
		let result = SimpleCycleFeasibilityForPath(
			path, context: ctx)
		if result?.feasible == true {
			print("Passed!")
		} else {
			print("Failed!")
		}
	}

	func cmd_search(
		_ args: [String]
	) {
		let cancel = captureSigint()
		var searchOptions = TrajectorySearchOptions()

		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset search: expected name\n", stderr)
			return
		}
		if let attemptCount: Int = params["attemptCount"] {
			searchOptions.attemptCount = attemptCount
		}
		if let maxPathLength: Int = params["maxPathLength"] {
			searchOptions.maxPathLength = maxPathLength
		}
		if let stopAfterSuccess: Bool = params["stopAfterSuccess"] {
			searchOptions.stopAfterSuccess = stopAfterSuccess
		}
		if let skipKnownPoints: Bool = params["skipKnownPoints"] {
			searchOptions.skipKnownPoints = skipKnownPoints
		}
		let pointSet = try! dataManager.loadPointSet(name: name)
		var knownCycles = dataManager.knownCyclesForPointSet(name: name)
		let targetIndex: Int? = params["index"]
		
		let searchQueue = DispatchQueue(
			label: "me.faec.billiards.searchQueue",
			attributes: .concurrent)
		let resultsQueue = DispatchQueue(label: "me.faec.billiards.resultsQueue")
		let searchGroup = DispatchGroup()

		var activeSearches: [Int: Bool] = [:]
		var searchResults: [Int: TrajectorySearchResult] = [:]
		var foundCount = 0
		var updatedCount = 0
		for (index, point) in pointSet.elements.enumerated() {
			if cancel() { break }
			if targetIndex != nil && targetIndex != index {
				continue
			}

			searchGroup.enter()
			searchQueue.async {
				defer { searchGroup.leave() }
				var options = searchOptions
				var skip = false

				resultsQueue.sync(flags: .barrier) {
					// starting search
					if let cycle = knownCycles[index] {
						if options.skipKnownPoints {
							skip = true
							return
						}
						options.maxPathLength = min(
							options.maxPathLength, cycle.count - 1)
					}
					if !cancel() {
						activeSearches[index] = true
					}
				}
				if skip || cancel() { return }

				let searchResult = TrajectorySearchForApexCoords(
					point, options: options, cancel: cancel)
				resultsQueue.sync(flags: .barrier) {
					// search is finished
					activeSearches.removeValue(forKey: index)
					searchResults[index] = searchResult
					var caption = ""
					if let newCycle = searchResult.shortestCycle?.anyPath() {
						if let oldCycle = knownCycles[index] {
							if PathLessThan(newCycle, oldCycle) {
								knownCycles[index] = newCycle
								caption = Magenta("found smaller cycle ") +
									"[\(oldCycle.count) -> \(newCycle.count)]"
								updatedCount += 1
							} else {
								caption = DarkGray("no change")
							}
						} else {
							knownCycles[index] = newCycle
							caption = "cycle found"
							foundCount += 1
						}
					} else if knownCycles[index] != nil {
						caption = DarkGray("no change")
					} else {
						caption = Red("no cycle found")
					}
					
					// reset the current line
					print(ClearCurrentLine(), terminator: "\r")

					pointSet.printPointIndex(
						index,
						knownCycles: knownCycles,
						precision: 4,
						caption: caption)
					
					let failedCount = searchResults.count -
						(foundCount + updatedCount)
					print("found \(foundCount), updated \(updatedCount),",
						"failed \(failedCount).",
						"still active:",
						Cyan("\(activeSearches.keys.sorted())"),
						"...",
						terminator: "")
					fflush(stdout)
				}
			}
		}
		searchGroup.wait()
		print(ClearCurrentLine(), terminator: "\r")
		let failedCount = searchResults.count -
			(foundCount + updatedCount)
		print("found \(foundCount), updated \(updatedCount),",
			"failed \(failedCount).")
		try! dataManager.saveKnownCycles(
			knownCycles, pointSetName: name)
	}

	func cmd_phaseplot(_ args: [String]) {
		/*let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset phaseplot: expected name\n", stderr)
			return
		}*/
		//guard let 
	}

	func cmd_plotConstraint(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset plotConstraint: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset plotConstraint: expected index\n", stderr)
			return
		}
		//let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)
		guard let cycle = knownCycles[index]
		else {
			fputs("no cycle known for index \(index)\n", stderr)
			return
		}
		guard let constraint: ConstraintSpec = params["constraint"]
		else {
			fputs("pointset plotConstraint: expected constraint\n", stderr)
			return
		}
		let path = FileManager.default.currentDirectoryPath
		let paletteURL = URL(fileURLWithPath: path)
			.appendingPathComponent("media")
			.appendingPathComponent("gradient3.png")
		guard let palette = PaletteFromImageFile(paletteURL)
		else {
			fputs("can't load palette\n", stderr)
			return
		}

		let width = 2000
		let height = 1000
		//let pCenter = Vec2()
		let center = Vec2(0.5, 0.25)
		let scale = 1.0 / 1000.0 //0.00045//1.0 / 2200.0
		let image = ImageData(width: width, height: height)

		func colorForCoords(_ z: Vec2<Double>) -> RGB {
			// angle scaled to +-1
			let angle = atan2(z.y, z.x) / Double.pi
			if angle < 0 {
				let positiveAngle = angle + 1.0
				let paletteIndex = Int(positiveAngle * Double(palette.count))
				let rawColor = palette[paletteIndex]
				return RGB(
					r: rawColor.r / 2.0,
					g: rawColor.g / 2.0,
					b: rawColor.b / 2.0)
			}
			let paletteIndex = Int(angle * Double(palette.count - 1))
			return palette[paletteIndex]
		}

		func offsetForTurnPath(
			_ turnPath: TurnPath,
			constraint: ConstraintSpec,
			apex: Vec2<Double>
		) -> Vec2<Double> {
			let baseAngles = BaseValues(
				atan2(apex.y, apex.x) * 2.0,
				atan2(apex.y, 1.0 - apex.x) * 2.0)
			var leftTotal = Vec2(0.0, 0.0)
			var rightTotal = Vec2(0.0, 0.0)

			var curAngle = 0.0
			//var curOrientation = turnPath.initialOrientation
			//for (index, turn) in turnPath.turns.enumerated() {
			for turn in turnPath {
				let delta = Vec2(cos(curAngle), sin(curAngle))
				let summand = turn.singularity == .B1//(curOrientation == .forward)
					? delta
					: -delta
				var side: Side
				if constraint.left.index < constraint.right.index {
					if index <= constraint.left.index ||
						index > constraint.right.index
					{
						side = .left
					} else {
						side = .right
					}
				} else if index <= constraint.left.index &&
					index > constraint.right.index
				{
					side = .left
				} else {
					side = .right
				}

				switch side {
					case .left: leftTotal = leftTotal + summand
					case .right: rightTotal = rightTotal + summand
				}
				
				curAngle += baseAngles[turn.singularity] * Double(turn.degree)
			}
			return Vec2(
				x: leftTotal.x * rightTotal.x + leftTotal.y * rightTotal.y,
				y: -leftTotal.x * rightTotal.y + leftTotal.y * rightTotal.x)
		}

		for py in 0..<height {
			let y = center.y + Double(height/2 - py) * scale
			for px in 0..<width {
				let x = center.x + Double(px - width/2) * scale
				let z = offsetForTurnPath(cycle, constraint: constraint, apex: Vec2(x, y))
				let color = colorForCoords(z)
				image.setPixel(row: py, column: px, color: color)
			}
		}

		let imageURL = URL(fileURLWithPath: path)
			.appendingPathComponent("constraint-plot.png")
		image.savePngToUrl(imageURL)

		print("pretending to plot constraint: \(constraint)")
		print("from cycle \(cycle)")
	}

	func cmd_plotOffset(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset plotOffset: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset plotOffset: expected index\n", stderr)
			return
		}
		//let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)
		guard let cycle = knownCycles[index]
		else {
			fputs("no cycle known for index \(index)\n", stderr)
			return
		}
		let path = FileManager.default.currentDirectoryPath
		let paletteURL = URL(fileURLWithPath: path)
			.appendingPathComponent("media")
			.appendingPathComponent("gradient3.png")
		guard let palette = PaletteFromImageFile(paletteURL)
		else {
			fputs("can't load palette\n", stderr)
			return
		}

		let width = 2000
		let height = 1000
		//let pCenter = Vec2()
		let center = Vec2(0.5, 0.25)
		let scale = 1.0 / 1000.0 //0.00045//1.0 / 2200.0
		let image = ImageData(width: width, height: height)

		/*func colorForCoords(_ z: Vec2<Double>) -> RGB {
			// angle scaled to +-1
			var angle = atan2(-z.x, z.y) / Double.pi//atan2(z.y, z.x) / Double.pi
			if angle < 0 {
				let positiveAngle = angle + 1.0
				let paletteIndex = Int(positiveAngle * Double(palette.count))
				let rawColor = palette[paletteIndex]
				return RGB(
					r: rawColor.r / 2.0,
					g: rawColor.g / 2.0,
					b: rawColor.b / 2.0)
			}
			let paletteIndex = Int(angle * Double(palette.count - 1))
			return palette[paletteIndex]
		}*/
		func colorForCoords(_ z: Vec2<Double>) -> RGB {
			let angle = 0.5 + 0.5 * atan2(-z.x, z.y) / Double.pi//atan2(z.y, z.x) / Double.pi
			let paletteIndex = Int(angle * Double(palette.count - 1))
			return palette[paletteIndex]
		}

		func offsetForTurnPath(
			_ turnPath: TurnPath, withApex apex: Vec2<Double>
		) -> Vec2<Double> {
			let baseAngles = BaseValues(
				atan2(apex.y, apex.x) * 2.0,
				atan2(apex.y, 1.0 - apex.x) * 2.0)
			var x = 0.0
			var y = 0.0
			var curAngle = 0.0
			for turn in turnPath {
				let dx = cos(curAngle)
				let dy = sin(curAngle)
				switch turn.singularity {
					case .B1:
						x += dx
						y += dy
					case .B0:
						x -= dx
						y -= dy
				}

				curAngle += baseAngles[turn.singularity] * Double(turn.degree)
			}
			return Vec2(x, y)
		}

		print("Plotting cycle: \(cycle)")

		for py in 0..<height {
			let y = center.y + Double(height/2 - py) * scale
			for px in 0..<width {
				let x = center.x + Double(px - width/2) * scale
				let z = offsetForTurnPath(cycle, withApex: Vec2(x, y))
				let color = colorForCoords(z)
				image.setPixel(row: py, column: px, color: color)
			}
		}

		let imageURL = URL(fileURLWithPath: path)
			.appendingPathComponent("offset-plot.png")
		image.savePngToUrl(imageURL)
	}

	func cmd_plot(_ args: [String]) {
		/*let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset plot: expected name\n", stderr)
			return
		}
		//let pointSet = try! dataManager.loadPointSet(name: name)

		//let outputURL = URL(fileURLWithPath: "plot.png")
		let width = 2000
		let height = 1000
		let scale = Double(width) * 0.9
		let imageCenter = Vec2(Double(width) / 2, Double(height) / 2)
		let modelCenter = Vec2(0.5, 0.25)
		//let pointRadius = CGFloat(4)

		func toImageCoords(_ v: Vec2<Double>) -> Vec2<Double> {
			return (v - modelCenter) * scale + imageCenter
		}
		*/
		//let filter = PathFilter(path: [-2, 2, 2, -2])
		//let feasibility = PathFeasibility(path: [-2, 2, 2, -2])
		//let path = [-2, 2, 2, -2]
		//let path = [4, -3, -5, 3, -4, -4, 5, 4]
		//let turns = [3, -1, 1, -1, -3, 1, -2, 1, -3, -1, 1, -1, 3, 2]
		//let feasibility = SimpleCycleFeasibility(turns: turns)

		/*ContextRenderToURL(outputURL, width: width, height: height)
		{ (context: CGContext) in
			var i = 0
			for point in pointSet.elements {
				//print("point \(i)")
				i += 1
				let modelCoords = point//point.asDoubleVec()

				let color = CGColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 0.6)
				let imageCoords = toImageCoords(modelCoords.asDoubleVec())
				
				context.beginPath()
				//print("point: \(imageCoords.x), \(imageCoords.y)")
				context.addArc(
					center: CGPoint(x: imageCoords.x, y: imageCoords.y),
					radius: pointRadius,
					startAngle: 0.0,
					endAngle: CGFloat.pi * 2.0,
					clockwise: false
				)
				context.closePath()
				context.setFillColor(color)
				context.drawPath(using: .fill)
			}

			// draw the containing half-circle
			context.beginPath()
			let circleCenter = toImageCoords(Vec2(0.5, 0.0))
			context.addArc(center: CGPoint(x: circleCenter.x, y: circleCenter.y),
				radius: CGFloat(0.5 * scale),
				startAngle: 0.0,
				endAngle: CGFloat.pi,
				clockwise: false
			)
			context.closePath()
			context.setStrokeColor(red: 0.1, green: 0.0, blue: 0.2, alpha: 1.0)
			context.setLineWidth(2.0)
			context.drawPath(using: .stroke)
		}*/
	}

	enum CoordinateSystem: String, LosslessStringConvertible {
		case euclidean
		case polar

		public init?(_ str: String) {
			self.init(rawValue: str)
		}

		public var description: String {
			return self.rawValue
		}
	}


	func cmd_probe(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset probe: expected name\n", stderr)
			return
		}
		guard let targetCoords: Vec2<Double> = params["coords"]
		else {
			fputs("pointset probe: expected coords\n", stderr)
			return
		}
		let metric: CoordinateSystem =
			params["metric"] ?? .euclidean
		let count: Int = params["count"] ?? 1
		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)
		let distance: [Double] = pointSet.elements.indices.map { index in
			let point = pointSet.elements[index].asDoubleVec()
			var coords: Vec2<Double>
			switch metric {
				case .euclidean:
					coords = point
				case .polar:
					let angle0 = atan2(point.y, point.x)
					let angle1 = atan2(point.y, 1.0 - point.x)
					coords = Vec2(
						Double.pi / (2.0 * angle0),
						Double.pi / (2.0 * angle1)
					)

			}
			let offset = coords - targetCoords
			return sqrt(offset.x * offset.x + offset.y * offset.y)
		}
		let sortedIndices = pointSet.elements.indices.sorted {
			distance[$0] < distance[$1]
		}

		for index in sortedIndices.prefix(count) {
			let distanceStr = String(format: "%.6f", distance[index])
			pointSet.printPointIndex(index,
				knownCycles: knownCycles,
				precision: 6,
				caption: "(distance \(distanceStr))")
		}
	}

	func cmd_delete(_ args: [String]) {
		guard let name = args.first
		else {
			print("pointset delete: expected point set name")
			exit(1)
		}
		do {
			try dataManager.deletePath(["pointset", name])
			logger.info("Deleted point set '\(name)'")
		} catch {
			logger.error("Couldn't delete point set '\(name)': \(error)")
		}
	}
	
	func run(_ args: [String]) {
		guard let command = args.first
		else {
			fputs("pointset: expected command", stderr)
			exit(1)
		}

		switch command {
		case "copyCycles":
			cmd_copyCycles(Array(args[1...]))
		case "create":
			cmd_create(Array(args[1...]))
		case "cycleFilter":
			cmd_cycleFilter(Array(args[1...]))
		case "delete":
			cmd_delete(Array(args[1...]))
		case "info":
			cmd_info(Array(args[1...]))
		case "list":
			cmd_list()
		case "plot":
			cmd_plot(Array(args[1...]))
		case "plotOffset":
			cmd_plotOffset(Array(args[1...]))
		case "plotConstraint":
			cmd_plotConstraint(Array(args[1...]))
		case "print":
			cmd_print(Array(args[1...]))
		case "probe":
			cmd_probe(Array(args[1...]))
		case "search":
			cmd_search(Array(args[1...]))
		case "validate":
			cmd_validate(Array(args[1...]))
		default:
			print("Unrecognized command '\(command)'")
		}
	}
}



class CycleStats {
	let cycle: TurnPath
	var pointCount = 0
	init(_ cycle: TurnPath) {
		self.cycle = cycle
	}
}

struct AggregateStats {
	var totalLength: Int = 0
	var totalWeight: Int = 0
	var totalSegments: Int = 0

	var maxLength: Int = 0
	var maxWeight: Int = 0
	var maxSegments: Int = 0
	
	var symmetricCount: Int = 0
}

extension Vec2 where R: Numeric {
	func asBiphase() -> BaseValues<Double> {
		let xApprox = x.asDouble()
		let yApprox = y.asDouble()
		return BaseValues(
			b0: Double.pi / (2.0 * atan2(yApprox, xApprox)),
			b1: Double.pi / (2.0 * atan2(yApprox, 1.0 - xApprox)))
	}
}

func polarFromCartesian(_ coords: Vec2<Double>) -> BaseValues<Double> {
	return BaseValues(
		Double.pi / (2.0 * atan2(coords.y, coords.x)),
		Double.pi / (2.0 * atan2(coords.y, 1.0 - coords.x)))
}

func biradialFromApex<k: Field>(_ coords: Vec2<k>) -> BaseValues<k> {
	return BaseValues(coords.x / coords.y, (k.one - coords.x) / coords.y)
}

/*func cartesianFromPolar(_ coords: Vec2<Double>) -> Vec2<Double> {
}*/

struct ConstraintSpec: LosslessStringConvertible {
	let left: Boundary
	let right: Boundary

	enum BoundaryType: String {
		case base
		case apex
	}
	struct Boundary: LosslessStringConvertible {
		let index: Int
		let type: BoundaryType
		init?(_ str: String) {
			let entries = str.split(separator: ",")
			if entries.count != 2 {
				return nil
			}
			guard let index = Int(entries[0])
			else { return nil }
			guard let type = BoundaryType(
				rawValue: String(entries[1]))
			else { return nil }
			self.index = index
			self.type = type
		}

		public var description: String {
			return "\(index),\(type)"
		}
	}

	public init?(_ str: String) {
		let boundaries = str.split(separator: "-")
		if boundaries.count != 2 {
			return nil
		}
		guard let left = Boundary(String(boundaries[0]))
		else { return nil }
		guard let right = Boundary(String(boundaries[1]))
		else { return nil }
		self.left = left
		self.right = right
	}

	public var description: String {
		return "\(left)-\(right)"
	}

}

extension PointSet {
	func printPointIndex(
		_ index: Int,
		knownCycles: [Int: TurnPath],
		precision: Int = 6,
		caption: String = ""
	) {
		func FloatStr<T: Numeric>(_ val: T) -> String {
			return String(format: "%.\(precision)f", val.asDouble())
		}
		func S2Str<T: Numeric>(_ s: BaseValues<T>) -> String {
			let strs = s.map { FloatStr($0.asDouble()) }
			
			return "(\(DarkGray(strs[.B0])), \(strs[.B1]))"
		}
		func CFStr(_ cf: ContinuedFrac) -> String {
			return cf.approximations().map {$0.description}.joined(separator: " -> ")
		}
		let point = self.elements[index]
		let pointApprox = point.asDoubleVec()
		let angles = BaseValues(
			atan2(pointApprox.y, pointApprox.x) * 2.0 / Double.pi,
			atan2(pointApprox.y, 1.0 - pointApprox.x) * 2.0 / Double.pi)
		let angleRatio = angles[.B0] / angles[.B1]
		let angleRatioCF = ContinuedFrac(angleRatio, length:8)
		let angleRatioStr = CFStr(angleRatioCF)
		let inverseLog = pointApprox.asBiphase()
		let cotangents = biradialFromApex(point)//.map(FloatStr)
		let x = FloatStr(point.x)
		let y = FloatStr(point.y)
		let coordsStr = "(\(x), \(y))"
		print(Cyan("[\(index)]"), caption)
		print(Green("  cartesian coords"), coordsStr)
		print(Green("  angles over pi/2"), S2Str(angles))
		print(Green("  inverse angle"), S2Str(inverseLog))
		print(Green("  angle ratio"), angleRatioStr)
		print(Green("  cotangent"), S2Str(cotangents))
		//print(DarkGray("    S0: \(cotangents[.B0])"))
		//print("    S1: \(cotangents[.B1])")
		/*print(Green("  1 / log"))
		print(DarkGray("    S0: \(inverseLog[.B0])"))
		print("    S1: \(inverseLog[.B1])")*/
		if let cycle = knownCycles[index] {
			print(Green("  cycle"), cycle)
			// for now we divide cycle weight by 2 since it's always doubled
			let weight = cycle.weight().map { $0 / 2 }
			let weightRatio = GmpRational(weight[.B1], over: UInt(weight[.B0]))
			let weightRatioApprox = ContinuedFrac(weightRatio).approximations()
			let approxStr = weightRatioApprox.map {$0.description}.joined(separator: " -> ")
			//let weightStr = DarkGray(String(weight[.B0])) + " " + String(weight[.B1])
			print(Green("    weight ratio: "), approxStr)
			/*let bounds: RadiusBounds = BoundsOrSomething(cycle: cycle)
			let minRadii = bounds.min.map {
				String(format: "%.\(precision)f", $0)}
			let maxRadii = bounds.max.map {
				String(format: "%.\(precision)f", $0)}
			print(Green("    minRadii: (\(minRadii[.B0]), \(minRadii[.B1]))"))
			print(Green("    maxRadii: (\(maxRadii[.B0]), \(maxRadii[.B1]))"))*/
		}
	}

	func summarize(name: String, knownCycles: [Int: TurnPath]) {
		var aggregate = AggregateStats()
		var statsTable: [TurnPath: CycleStats] = [:]
		for (i, path) in knownCycles {
			aggregate.totalLength += path.count
			aggregate.maxLength = max(aggregate.maxLength, path.count)

			let weight = path.totalWeight()
			aggregate.totalWeight += weight
			aggregate.maxWeight = max(aggregate.maxWeight, weight)
 
			let componentCount = path.monoidalComponents().count
			aggregate.totalSegments += componentCount
			aggregate.maxSegments = max(aggregate.maxSegments, componentCount)
			
			var curStats: CycleStats
			if let entry = statsTable[path] {
				curStats = entry
				if path.isSymmetric() {
					aggregate.symmetricCount += 1
					//printPointIndex(i, knownCycles: knownCycles)
				}
			} else {
				curStats = CycleStats(path)
				statsTable[path] = curStats
			}
			curStats.pointCount += 1
		}
		let averageLength = String(format: "%.2f",
			Double(aggregate.totalLength) / Double(knownCycles.count))
		let averageWeight = String(format: "%.2f",
			Double(aggregate.totalWeight) / Double(knownCycles.count))
		let averageSegments = String(format: "%.2f",
			Double(aggregate.totalSegments) / Double(knownCycles.count))


		var oddBuckets = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		var overflow = 0
		for (cycle, _) in statsTable {
			var oddCount = 0
			for segment in cycle.monoidalComponents() {
				if segment.count % 2 != 0 {
					oddCount += 1
				}
			}
			if oddCount/2 < oddBuckets.count {
				oddBuckets[oddCount/2] += 1
			} else {
				overflow += 1
			}
		}
		let oddBucketStr =
			oddBuckets.enumerated().map { "\($0*2):\($1)" }.joined(separator: " ")
		

		print("pointset: \(name)")
		print("  known cycles: \(knownCycles.keys.count) / \(self.elements.count)")
		print("  distinct cycles: \(statsTable.count)")
		print("  symmetric cycles: \(aggregate.symmetricCount)")
		print("  length: average \(averageLength), maximum \(aggregate.maxLength)")
		print("  weight: average \(averageWeight), maximum \(aggregate.maxWeight)")
		print("  segments: average \(averageSegments), maximum \(aggregate.maxSegments)")
		print("  odd segment counts: \(oddBucketStr) more:\(overflow)")
	}
}


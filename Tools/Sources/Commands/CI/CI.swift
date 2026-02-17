import ArgumentParser
import Foundation
import Subprocess

struct CI: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "CI workflow commands that can be run both locally and in CI environments.",
                                                    subcommands: [
                                                        UnitTests.self,
                                                        RunTests.self
                                                    ])
    
    static let testOutputDirectory = "test_output"
    
    // MARK: - Logging
    
    /// Logs a release message.
    static func log(_ message: String) {
        // Use stderr as it's unbuffered
        fputs(message + "\n", stderr)
    }
    
    // MARK: - Linting
    
    /// Runs SwiftFormat in lint mode against the current directory.
    static func lint() async throws {
        print("\n🔍 Running SwiftFormat lint…\n")
        
        do {
            _ = try await run(.name("swiftformat"), ["--lint", "."])
        } catch {
            print("\n❌ SwiftFormat failed.\n")
            throw error
        }
        print("\n✅ SwiftFormat passed.\n")
    }
    
    // MARK: - Coverage & Test Result Collection
    
    /// Collects coverage from an xcresult bundle using xcresultparser (cobertura format).
    /// Failures are non-fatal — the output file simply won't be created.
    static func collectCoverage(resultBundle: String, target: String = "ElementX", outputName: String) async {
        let projectPath = URL.projectDirectory.path
        let resultBundlePath = "\(testOutputDirectory)/\(resultBundle)"
        let outputPath = "\(testOutputDirectory)/\(outputName)"
        
        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            print("\n❌ Result bundle not found at \(resultBundlePath), skipping coverage collection.\n")
            return
        }
        
        do {
            _ = try await run(.path("/bin/zsh"), ["-cu", "xcresultparser -q -o cobertura -t \(target) -p \(projectPath) \(resultBundlePath) > \(outputPath)"])
            print("\n📊 Coverage report: \(outputPath)\n")
        } catch {
            print("\n❌ Failed to collect coverage for \(resultBundle): \(error.localizedDescription)\n")
        }
    }
    
    /// Collects test results from an xcresult bundle using xcresultparser (junit format).
    /// Failures are non-fatal — the output file simply won't be created.
    static func collectTestResults(resultBundle: String, outputName: String) async {
        let projectPath = URL.projectDirectory.path
        let resultBundlePath = "\(testOutputDirectory)/\(resultBundle)"
        let outputPath = "\(testOutputDirectory)/\(outputName)"
        
        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            print(" Result bundle not found at \(resultBundlePath), skipping test result collection.")
            return
        }
        
        do {
            _ = try await run(.path("/bin/zsh"), ["-cu", "xcresultparser -q -o junit -p \(projectPath) \(resultBundlePath) > \(outputPath)"])
            print("📋 Test results: \(outputPath)")
        } catch {
            print("\n❌ Failed to collect test results for \(resultBundle): \(error.localizedDescription)\n")
        }
    }
    
    // MARK: - Result Zipping
    
    /// Zips xcresult bundles in the test output directory for faster artifact uploads.
    static func zipResults(bundles: [String], outputName: String) async {
        let bundleArgs = bundles.joined(separator: " ")
        do {
            print("\n📦 Zipping test results…")
            _ = try await run(.path("/bin/zsh"), ["-cu", "cd \(testOutputDirectory) && zip -rq \(outputName) \(bundleArgs)"])
            print("📦 Zipped: \(testOutputDirectory)/\(outputName)\n")
        } catch {
            print("\n❌ Failed to zip results: \(error.localizedDescription)\n")
        }
    }
    
    // MARK: - Shell Interaction
    
    @discardableResult
    static func run<Output: OutputProtocol, Error: ErrorOutputProtocol>(_ executable: Executable,
                                                                        _ arguments: Arguments = [],
                                                                        environment: Environment = .inherit,
                                                                        output: Output = .standardOutput,
                                                                        error: Error = .standardError) async throws -> CollectedResult<Output, Error> {
        let result = try await Subprocess.run(executable,
                                              arguments: arguments,
                                              environment: environment,
                                              output: output,
                                              error: error)
        
        if case let .exited(code) = result.terminationStatus, code != 0 {
            throw ExitCode.failure
        }
        
        return result
    }
}

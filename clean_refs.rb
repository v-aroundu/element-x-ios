content = File.read("ElementX.xcodeproj/project.pbxproj")

# Remove "includeInIndex = 1; " from our new file references
# and remove "name = X.swift; " when it's redundant (same as path)
files = [
  "AppLockPromptScreenModels.swift",
  "AppLockPromptScreenViewModelProtocol.swift",
  "AppLockPromptScreenViewModel.swift",
  "AppLockPromptScreenCoordinator.swift",
  "AppLockPromptScreen.swift",
]

files.each do |f|
  # Remove "includeInIndex = 1; " for this file's reference line
  old = "includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = #{f}; path = #{f};"
  new_val = "lastKnownFileType = sourcecode.swift; path = #{f};"
  if content.include?(old)
    content = content.gsub(old, new_val)
    puts "Cleaned: #{f}"
  else
    puts "Pattern not found for: #{f}"
    # Try to show what's there
    content.scan(/.*#{Regexp.escape(f)}.*/).each { |l| puts "  Found: #{l.strip}" }
  end
end

File.write("ElementX.xcodeproj/project.pbxproj", content)
puts "Done."

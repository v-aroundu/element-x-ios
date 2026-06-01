content = File.read("ElementX.xcodeproj/project.pbxproj")

fixes = {
  "path = ElementX/Sources/Screens/AppLock/AppLockPromptScreen/AppLockPromptScreenModels.swift;" =>
    "path = AppLockPromptScreenModels.swift;",
  "path = ElementX/Sources/Screens/AppLock/AppLockPromptScreen/AppLockPromptScreenViewModelProtocol.swift;" =>
    "path = AppLockPromptScreenViewModelProtocol.swift;",
  "path = ElementX/Sources/Screens/AppLock/AppLockPromptScreen/AppLockPromptScreenViewModel.swift;" =>
    "path = AppLockPromptScreenViewModel.swift;",
  "path = ElementX/Sources/Screens/AppLock/AppLockPromptScreen/AppLockPromptScreenCoordinator.swift;" =>
    "path = AppLockPromptScreenCoordinator.swift;",
  "path = ElementX/Sources/Screens/AppLock/AppLockPromptScreen/View/AppLockPromptScreen.swift;" =>
    "path = AppLockPromptScreen.swift;",
}

fixes.each do |old, new_val|
  if content.include?(old)
    content = content.gsub(old, new_val)
    puts "Fixed: " + old.split("/").last
  else
    puts "NOT FOUND: " + old
  end
end

File.write("ElementX.xcodeproj/project.pbxproj", content)
puts "Done."

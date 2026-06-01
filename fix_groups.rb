content = File.read("ElementX.xcodeproj/project.pbxproj")

# Remove "name = AppLockPromptScreen;" from the group (keep only path)
old1 = "\t\t\tname = AppLockPromptScreen;\n\t\t\tpath = AppLockPromptScreen;"
new1 = "\t\t\tpath = AppLockPromptScreen;"
if content.include?(old1)
  content = content.gsub(old1, new1)
  puts "Removed redundant name from AppLockPromptScreen group"
else
  puts "Pattern not found for AppLockPromptScreen name removal"
end

# The View subgroup also has name = View AND path = View - check if other View groups have name
# Looking at existing: they just have "path = View;" - remove name from our View subgroup too  
old2 = "529301AF30361CEE4EDD5F92 /* View */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t118960A6D50E7C910E87FE36 /* AppLockPromptScreen.swift */,\n\t\t\t);\n\t\t\tname = View;\n\t\t\tpath = View;"
new2 = "529301AF30361CEE4EDD5F92 /* View */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t118960A6D50E7C910E87FE36 /* AppLockPromptScreen.swift */,\n\t\t\t);\n\t\t\tpath = View;"
if content.include?(old2)
  content = content.gsub(old2, new2)
  puts "Removed redundant name from View subgroup"
else
  puts "Pattern not found for View name removal"
  # Show what we have
  idx = content.index("529301AF30361CEE4EDD5F92")
  puts content[idx, 300] if idx
end

File.write("ElementX.xcodeproj/project.pbxproj", content)
puts "Done."

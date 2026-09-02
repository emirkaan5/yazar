project := "yazar.xcodeproj"
scheme := "yazar"
derived_data := justfile_directory() / ".build/DerivedData"

# Open this worktree's project in Xcode for development.
dev:
    open {{project}}

# Build the shared yazar scheme with worktree-local build artifacts.
build:
    @xcodebuild -quiet \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath {{derived_data}} \
        build
    @echo "Built {{derived_data}}/Build/Products/Debug/yazar.app"

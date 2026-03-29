# Homebrew Cask for FocusFlow
#
# SETUP INSTRUCTIONS
# ──────────────────
# 1. Run `VERSION=1.0.0 ./Scripts/build-dmg.sh` — note the SHA-256 printed at the end.
# 2. Upload Artifacts/FocusFlow-1.0.0.dmg to a GitHub Release.
# 3. Fill in `sha256` and `url` below with those values.
# 4. Create a public GitHub repo named `homebrew-focusflow` (the "tap" repo).
# 5. Place this file at: homebrew-focusflow/Casks/focusflow.rb
# 6. Users can then install with:
#      brew tap <your-github-username>/focusflow
#      brew install --cask focusflow

cask "focusflow" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_build-dmg.sh"

  # Replace <owner> with your GitHub username / org
  url "https://github.com/<owner>/FocusFlow/releases/download/v#{version}/FocusFlow-#{version}.dmg"

  name "FocusFlow"
  desc "Menu bar Pomodoro focus timer with on-device AI coaching"
  homepage "https://github.com/<owner>/FocusFlow"

  # FocusFlow requires macOS 26 (Tahoe)
  depends_on macos: ">= :sequoia"

  app "FocusFlow.app"

  # Clean up all app data on uninstall
  zap trash: [
    "~/Library/Application Support/FocusFlow",
    "~/Library/Containers/com.focusflow.app",
    "~/Library/Preferences/com.focusflow.app.plist",
    "~/Library/Caches/com.focusflow.app",
    "~/Library/Logs/FocusFlow",
  ]
end

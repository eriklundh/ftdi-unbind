# packaging/homebrew/ftdi-unbind.rb
#
# Homebrew formula for ftdi-unbind / ftdi-bind.
#
# This file is the canonical source; the Homebrew tap repo
# (compelcon/homebrew-tools or similar) contains a copy that is
# updated by the release workflow on every v* tag.
#
# Manual tap install:
#   brew tap compelcon/tools https://github.com/compelcon/homebrew-tools
#   brew install ftdi-unbind
#
# Or, for a one-off tap from this repo root:
#   brew tap compelcon/tools <path-to-tap-repo>
#   brew install ftdi-unbind
#
# To update after a new release:
#   brew upgrade ftdi-unbind
#
# To uninstall:
#   brew uninstall ftdi-unbind
#   brew untap compelcon/tools      # optional, removes the tap itself

class FtdiUnbind < Formula
  desc "Unbind/rebind the OS FTDI serial driver to give libusb exclusive access"
  homepage "https://github.com/compelcon/ftdi-unbind"
  # The URL and sha256 below are updated automatically by the release workflow.
  # To update manually: compute sha256 of the linux-macos tarball and paste here.
  url "https://github.com/compelcon/ftdi-unbind/releases/download/v0.1.0/ftdi-tools-v0.1.0-linux-macos.tar.gz"
  sha256 "PLACEHOLDER_SHA256_UPDATED_BY_RELEASE_WORKFLOW"
  license "GPL-2.0-or-later"
  version "0.1.0"

  # No dependencies — pure bash scripts.

  def install
    bin.install "ftdi-unbind"
    bin.install "ftdi-bind"
  end

  test do
    # --about exits 0 and prints a version line.
    assert_match "ftdi-unbind", shell_output("#{bin}/ftdi-unbind --about")
  end
end

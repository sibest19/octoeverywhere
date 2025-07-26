#!/bin/bash
# Format all files in the project

set -e

echo "🔧 Formatting project files..."

# Format shell scripts
echo "📝 Formatting shell scripts..."
if command -v shfmt &>/dev/null; then
  shfmt -w -i 2 *.sh
  echo "✅ Shell scripts formatted"
else
  echo "⚠️  shfmt not found, skipping shell script formatting"
fi

# Format YAML files
echo "📝 Formatting YAML files..."
if command -v yamlfmt &>/dev/null; then
  yamlfmt .github/workflows/*.yml
  echo "✅ YAML files formatted"
else
  echo "⚠️  yamlfmt not found, skipping YAML formatting"
fi

# Format Dockerfiles
echo "📝 Formatting Dockerfiles..."
if command -v hadolint &>/dev/null; then
  # Use hadolint to check Dockerfile best practices
  for dockerfile in Dockerfile*; do
    if [ -f "$dockerfile" ]; then
      echo "🔍 Checking $dockerfile with hadolint..."
      hadolint "$dockerfile" || echo "⚠️  hadolint found issues in $dockerfile"
    fi
  done
  echo "✅ Dockerfiles checked with hadolint"
else
  echo "⚠️  hadolint not found, skipping Dockerfile linting"
  echo "💡 Install hadolint for Dockerfile best practices checking"
fi

# Check for changes
if git diff --quiet; then
  echo "🎉 No formatting changes needed - all files already properly formatted!"
else
  echo "📊 Formatting changes made:"
  git diff --name-only
  echo ""
  echo "💡 Review the changes with: git diff"
  echo "💡 Commit the changes with: git add . && git commit -m 'Format files'"
fi

echo "✨ Formatting complete!"

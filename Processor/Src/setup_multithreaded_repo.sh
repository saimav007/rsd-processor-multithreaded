#!/bin/bash

# Script to create and push multithreaded RSD code to a new GitHub repository
# Usage: ./setup_multithreaded_repo.sh <github-repo-name>
# Example: ./setup_multithreaded_repo.sh rsd-processor-multithreaded

set -e

REPO_NAME=$1

if [ -z "$REPO_NAME" ]; then
    echo "Usage: $0 <github-repo-name>"
    echo "Example: $0 rsd-processor-multithreaded"
    exit 1
fi

echo "=== Setting up multithreaded RSD repository ==="

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Initializing new git repository..."
    git init
fi

# Check current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "master")

echo "Current branch: $CURRENT_BRANCH"

# Create a new branch for multithreaded work (if not already on it)
if [ "$CURRENT_BRANCH" != "multithreaded" ]; then
    echo "Creating new branch 'multithreaded'..."
    git checkout -b multithreaded
fi

# Stage all modified files
echo "Staging modified files..."
git add -A

# Check if there are changes to commit
if git diff --staged --quiet; then
    echo "No changes to commit."
else
    # Commit the changes
    echo "Committing multithreaded changes..."
    git commit -m "Add multithreading support with round-robin scheduling to RSD core

- Added ThreadID support throughout front-end pipeline stages
- Implemented round-robin thread scheduler in NextPCStage
- Added thread-aware PC module with per-thread PC arrays
- Propagated threadID through FetchStage, PreDecodeStage, and DecodeStage
- Added threadID assignment to decoded micro-ops
- NUM_THREADS = 2"
fi

# Create repository on GitHub (requires GitHub CLI)
if command -v gh &> /dev/null; then
    echo "Creating GitHub repository '$REPO_NAME'..."
    gh repo create "$REPO_NAME" --public --source=. --remote=github-multithreaded --push
    echo "Repository created and code pushed!"
else
    echo "GitHub CLI (gh) not found. Please create the repository manually:"
    echo "1. Go to https://github.com/new"
    echo "2. Create a repository named: $REPO_NAME"
    echo "3. Then run these commands:"
    echo ""
    echo "   git remote add origin https://github.com/YOUR_USERNAME/$REPO_NAME.git"
    echo "   git push -u origin multithreaded"
fi

echo ""
echo "=== Setup complete! ==="
echo "Repository: $REPO_NAME"
echo "Branch: multithreaded"


#!/bin/zsh
set -euo pipefail

if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
else
    echo "Error: .env file not found. Copy .env.example to .env and set GITHUB_TOKEN."
    exit 1
fi

REPO_NAME="${GITHUB_REPO_NAME:-PulseMatrix-Pro}"
VISIBILITY="${GITHUB_REPO_VISIBILITY:-public}"
IS_PRIVATE="false"
if [[ "${VISIBILITY:l}" == "private" ]]; then
    IS_PRIVATE="true"
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Notice: GITHUB_TOKEN is not set in .env."
    echo "To automatically create and push to GitHub:"
    echo "  1. Add GITHUB_TOKEN=\"ghp_...\" (and optionally GITHUB_USERNAME) to .env"
    echo "  2. Run: zsh scripts/publish_github.sh"
    echo ""
    echo "Alternatively, if you already created an empty repository on GitHub, run:"
    echo "  git remote add origin https://github.com/<your-username>/${REPO_NAME}.git"
    echo "  git push -u origin main"
    exit 1
fi

echo "Creating GitHub repository '${REPO_NAME}' (private=${IS_PRIVATE})..."
CREATE_RESP=$(curl -sS -X POST "https://api.github.com/user/repos" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "{\"name\":\"${REPO_NAME}\",\"description\":\"Native Swift 6 & SwiftUI macOS Hardware Telemetry, AI Inference Profiler & Liquid Glass Monitor\",\"private\":${IS_PRIVATE}}")

OWNER_LOGIN=$(echo "${CREATE_RESP}" | sed -n 's/.*"login":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
if [[ -z "${OWNER_LOGIN}" ]]; then
    OWNER_LOGIN="${GITHUB_USERNAME:-}"
fi

if [[ -z "${OWNER_LOGIN}" ]]; then
    echo "Could not resolve GitHub owner login. Response:"
    echo "${CREATE_RESP}"
    exit 1
fi

REMOTE_URL="https://github.com/${OWNER_LOGIN}/${REPO_NAME}.git"
if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "${REMOTE_URL}"
else
    git remote add origin "${REMOTE_URL}"
fi

# Push using transient HTTP header so the token is never stored in .git/config
git -c http.extraHeader="Authorization: Basic $(printf "x-access-token:%s" "${GITHUB_TOKEN}" | base64)" push -u origin main

echo "Successfully published clean repository to: https://github.com/${OWNER_LOGIN}/${REPO_NAME}"

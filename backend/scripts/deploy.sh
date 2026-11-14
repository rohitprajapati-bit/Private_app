#!/usr/bin/env bash
# Deploys the Firestore rules and the Cloudflare Worker. Asks before doing anything.
# Usage: backend/scripts/deploy.sh [--yes]
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

# Load project id from the admin CLI env if present.
PROJECT="${GCP_PROJECT_ID:-}"
if [ -z "$PROJECT" ] && [ -f backend/admin-cli/.env ]; then
  PROJECT="$(grep -E '^GCP_PROJECT_ID=' backend/admin-cli/.env | cut -d= -f2- | tr -d '"' || true)"
fi

echo "This will deploy:"
echo "  1) Firestore security rules  (project: ${PROJECT:-<unknown>})"
echo "  2) Cloudflare Worker         (backend/worker)"
echo
if [ "${1:-}" != "--yes" ]; then
  read -r -p "Proceed? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Aborted."; exit 0; }
fi

if [ -n "$PROJECT" ]; then
  echo "==> Deploying Firestore rules…"
  npx --yes firebase-tools deploy --only firestore:rules --project "$PROJECT"
else
  echo "!! Skipping Firestore rules: no GCP_PROJECT_ID. Set it in backend/admin-cli/.env."
fi

echo "==> Deploying Worker…"
( cd backend/worker && npx --yes wrangler deploy )

echo "✓ Done. Run the smoke test:  node backend/scripts/smoke-test.mjs <your-worker-url>"

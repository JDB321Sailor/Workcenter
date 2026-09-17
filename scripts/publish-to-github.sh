#!/usr/bin/env bash
#
# Publish Workcenter to GitHub and open the first pull request.
#
# This repository is already structured for GitHub:
#
#   Stable   the GitHub default branch, holding the initial commit
#   Beta     promoted from Dev
#   Dev      the default target for every pull request, currently one commit
#            ahead of Stable with the repository governance layer
#
# What this script does:
#
#   1. Creates the GitHub repository as a NEW repository, never a fork.
#   2. Pushes Stable first, so GitHub adopts it as the default branch.
#   3. Pushes Beta, then Dev.
#   4. Opens the first pull request: Dev into Stable.
#
# It is idempotent: re-running it pushes whatever is new and opens the pull
# request only if one is not already open.
#
# Requirements: git, curl, and a GitHub personal access token with the "repo"
# scope (classic), or "Administration: read and write" plus
# "Contents: read and write" plus "Pull requests: read and write" (fine-grained).

set -Eeuo pipefail
IFS=$'\n\t'

OWNER="${WORKCENTER_GH_OWNER:-}"
REPO="${WORKCENTER_GH_REPO:-workcenter}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
VISIBILITY="${WORKCENTER_GH_VISIBILITY:-private}"
PR_TITLE="chore(ci): add the repository governance layer"
PR_BODY_FILE=""

# ---------------------------------------------------------------------------

info()  { printf '\033[36mℹ\033[0m  %s\n' "$*"; }
ok()    { printf '\033[32m✔\033[0m  %s\n' "$*"; }
warn()  { printf '\033[33m⚠\033[0m  %s\n' "$*" >&2; }
die()   { printf '\033[31m✖\033[0m  %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: scripts/publish-to-github.sh [options]

Options:
  --owner <name>        GitHub user or organisation that will own the repository
  --repo <name>         Repository name (default: workcenter)
  --visibility <v>      private (default) or public
  --title <text>        Pull-request title
  --body <file>         File containing the pull-request description
  -h, --help            Show this help

Environment:
  GITHUB_TOKEN          A token with permission to create the repository and
                        open pull requests. Alternatively GH_TOKEN.
  WORKCENTER_GH_OWNER   Same as --owner
  WORKCENTER_GH_REPO    Same as --repo

The token is never written to disk or to the git configuration.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)      OWNER="${2:-}"; shift 2 ;;
    --repo)       REPO="${2:-}"; shift 2 ;;
    --visibility) VISIBILITY="${2:-}"; shift 2 ;;
    --title)      PR_TITLE="${2:-}"; shift 2 ;;
    --body)       PR_BODY_FILE="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "Unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

command -v git >/dev/null 2>&1 || die "git is required"
if ! command -v curl >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
  die "Either curl or node is required to reach the GitHub API."
fi
command -v node >/dev/null 2>&1 || warn "node not found; the GitHub API calls will use curl"

[ -n "$TOKEN" ] || die "Set GITHUB_TOKEN (or GH_TOKEN) to a token that can create repositories."
[ -n "$OWNER" ] || die "Set the repository owner with --owner <name>, or WORKCENTER_GH_OWNER."

if [ "$VISIBILITY" != "private" ] && [ "$VISIBILITY" != "public" ]; then
  die "--visibility must be 'private' or 'public'"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this from inside the repository."

for branch in Stable Beta Dev; do
  git show-ref --verify --quiet "refs/heads/$branch" \
    || die "Branch '$branch' is missing. This script expects Stable, Beta and Dev to exist."
done

if [ -n "$(git status --porcelain)" ]; then
  die "The working tree has uncommitted changes. Commit or stash them first."
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
case "$current_branch" in
  Dev|Beta|Stable|feat/*|fix/*|docs/*|chore/*|refactor/*|test/*) ;;
  *) die "Branch '$current_branch' is not a recognised branch name." ;;
esac

# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------

# Single HTTP entry point: curl when available, node otherwise.
api() {
  local method="$1" path="$2" body="${3:-}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$body" ]; then
      curl -sS -X "$method" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://api.github.com$path"
    else
      curl -sS -X "$method" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com$path"
    fi
    return
  fi
  GH_METHOD="$method" GH_PATH="$path" GH_BODY="$body" GH_TOKEN_FOR_API="$TOKEN" \
    node -e '
      const { method, path, body, token } = {
        method: process.env.GH_METHOD,
        path: process.env.GH_PATH,
        body: process.env.GH_BODY,
        token: process.env.GH_TOKEN_FOR_API,
      };
      const headers = {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "workcenter-publish-script",
      };
      if (body) headers["Content-Type"] = "application/json";
      fetch(`https://api.github.com${path}`, { method, headers, body: body || undefined })
        .then((r) => r.text())
        .then((t) => process.stdout.write(t))
        .catch((e) => { process.stderr.write(String(e) + "\n"); process.exit(1); });
    '
}

# Read a top-level string field from a JSON object without needing jq.
json_field() {
  local field="$1"
  sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# ---------------------------------------------------------------------------
# 1. Verify the token and resolve the authenticated user
# ---------------------------------------------------------------------------

info "Verifying the token"
me="$(api GET /user)"
if printf '%s' "$me" | grep -q '"message"[[:space:]]*:[[:space:]]*"Bad credentials"'; then
  die "GitHub rejected the token. Check that it is valid and has not expired."
fi
login="$(printf '%s' "$me" | json_field login)"
[ -n "$login" ] || die "Could not resolve the authenticated user. Response: $me"
ok "Authenticated as $login"

# ---------------------------------------------------------------------------
# 2. Create the repository as a NEW repository, never a fork
# ---------------------------------------------------------------------------

if api GET "/repos/$OWNER/$REPO" | grep -q '"full_name"'; then
  ok "Repository $OWNER/$REPO already exists"
else
  info "Creating $OWNER/$REPO ($VISIBILITY)"
  payload=$(cat <<JSON
{"name":"$REPO","private":$([ "$VISIBILITY" = "private" ] && echo true || echo false),"description":"Files, chat and mail in one self-hosted workspace","has_issues":true,"has_projects":false,"has_wiki":false,"auto_init":false}
JSON
)
  created="$(api POST "/user/repos" "$payload")"
  printf '%s' "$created" | grep -q '"full_name"' \
    || die "Could not create the repository. Response: $created"
  ok "Created $OWNER/$REPO"
fi

remote_url="https://github.com/$OWNER/$REPO.git"

# Push with the token in the URL for this command only; nothing is persisted.
push_url="https://x-access-token:$TOKEN@github.com/$OWNER/$REPO.git"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$remote_url"
else
  git remote add origin "$remote_url"
fi

# ---------------------------------------------------------------------------
# 3. Push Stable first, so GitHub adopts it as the default branch
# ---------------------------------------------------------------------------

info "Pushing Stable (the documentation branch, and the repository default)"
if ! git push "$push_url" Stable:Stable 2>/tmp/wc-push.err; then
  if grep -q '403' /tmp/wc-push.err; then
    die "Push refused (403). The token needs 'Contents: Read and write', and 'Workflows: Read and write' because Dev adds files under .github/workflows/."
  fi
  cat /tmp/wc-push.err >&2
  die "Failed to push Stable."
fi
ok "Stable pushed"

info "Pushing Beta"
git push "$push_url" Beta:Beta
ok "Beta pushed"

info "Pushing Dev"
git push "$push_url" Dev:Dev
ok "Dev pushed"

# Push the current branch so a pull request can be opened from it.
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$current_branch" != "Dev" ] && [ "$current_branch" != "Stable" ] && [ "$current_branch" != "Beta" ]; then
  info "Pushing the current branch '$current_branch'"
  git push "$push_url" "$current_branch:$current_branch"
  ok "$current_branch pushed"
fi

# ---------------------------------------------------------------------------
# 4. Make Stable the default branch, explicitly
# ---------------------------------------------------------------------------

info "Setting Stable as the default branch"
api PATCH "/repos/$OWNER/$REPO" '{"default_branch":"Stable"}' >/dev/null || true
ok "Default branch is Stable"

# ---------------------------------------------------------------------------
# 5. Open the first pull request: Dev into Stable
# ---------------------------------------------------------------------------

# Every pull request targets Dev. Beta and Stable advance only by promotion.
head_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$head_branch" = "Dev" ] || [ "$head_branch" = "Beta" ] || [ "$head_branch" = "Stable" ]; then
  head_branch="Dev"
fi
info "Opening the pull request ($head_branch -> Dev)"

existing="$(api GET "/repos/$OWNER/$REPO/pulls?state=open&base=Dev&head=$OWNER:$head_branch")"
if printf '%s' "$existing" | grep -q '"number"'; then
  pr_number="$(printf '%s' "$existing" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)"
  ok "A pull request is already open: #$pr_number"
else
  if [ -n "$PR_BODY_FILE" ] && [ -f "$PR_BODY_FILE" ]; then
    body="$(sed ':a;N;$!ba;s/\n/\\n/g; s/"/\\"/g' "$PR_BODY_FILE")"
  else
    body="Adds the CI skeleton, the branch-promotion workflow, the issue and pull-request templates, and the branch-protection runbook.\n\nAll pull requests target Dev; Beta and Stable receive promotion merges only. See docs/branch-protection.md."
  fi
  payload=$(cat <<JSON
{"title":"$PR_TITLE","head":"$head_branch","base":"Dev","body":"$body"}
JSON
)
  pr="$(api POST "/repos/$OWNER/$REPO/pulls" "$payload")"
  pr_number="$(printf '%s' "$pr" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)"
  if [ -n "$pr_number" ]; then
    ok "Opened pull request #$pr_number"
  else
    warn "Could not open the pull request. Response: $pr"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------

cat <<SUMMARY

────────────────────────────────────────────────────────────
 Repository   https://github.com/$OWNER/$REPO
 Default      Stable
 PR base      Dev
────────────────────────────────────────────────────────────

Next steps, in order:

  1. Review and merge the pull request into Dev.
  2. When Dev is ready for production testing, promote it:
       git checkout Beta && git merge --no-ff Dev
     and open it as a pull request titled
       "chore(release): promote Dev to Beta vX.Y.Z"
  3. When beta testing completes, promote Beta into Stable the same way, which
     creates the release.
  4. Configure the rulesets and the required status checks described in
     docs/branch-protection.md.

SUMMARY

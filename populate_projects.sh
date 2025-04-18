#!/usr/bin/env bash

set -e -u -o pipefail

cd "$(dirname "$0")"

curl -sfL https://raw.githubusercontent.com/mkdocs/catalog/refs/heads/main/projects.yaml -o projects.yaml
cat extra_projects.yaml >>projects.yaml

cd projects

github_auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  github_auth=(--header "Authorization: Bearer $GITHUB_TOKEN")
fi

if [[ $# -eq 0 ]]; then
  projects=(*/)
else
  projects="$@"
fi

for d in "${projects[@]}"; do
  d="${d%/}"
  cd "$d"
  printf "%s -> " "$d" >&2
  if [[ -f 'project.txt' ]]; then
    [[ "$(head -1 'project.txt')" =~ ^https://github.com/([^/]+/[^/]+)/blob/([^/]+)/(.+)$ ]]
    repo="${BASH_REMATCH[1]}"
    branch="${BASH_REMATCH[2]}"
    mkdocs_yml="${BASH_REMATCH[3]}"
  else
    repo="${d//--//}"
    branch=$(curl -sfL "${github_auth[@]}" "https://api.github.com/repos/$repo" | jq -r '.default_branch')
    mkdocs_yml='mkdocs.yml'
  fi
  [[ "$(curl -sfL "${github_auth[@]}" "https://api.github.com/repos/$repo/commits?per_page=1&sha=$branch" | jq -r '.[0].commit.url')" =~ ^https://api.github.com/repos/([^/]+/[^/]+)/git/commits/([0-9a-f]+)$ ]]
  repo="${BASH_REMATCH[1]}"
  commit="${BASH_REMATCH[2]}"
  echo "https://github.com/$repo/blob/$branch/$mkdocs_yml" | tee /dev/stderr >project.txt
  echo "https://github.com/$repo/raw/$commit/$mkdocs_yml" >>project.txt
  tail -1 project.txt | xargs curl -sfL | mkdocs-get-deps -p ../../projects.yaml -f - | grep . >requirements.in.new
  (grep ' ' requirements.in 2>/dev/null || true) >>requirements.in.new
  mv requirements.in.new requirements.in
  cd ..
  # Rename the directory in case the repository has been renamed
  dir_name="${repo//\//--}"
  if [[ "$d" != "$dir_name" ]]; then
    rm -rf "$dir_name"
    mv "$d" "$dir_name"
  fi
done

printf "%s/requirements\n" "${projects[@]}" | xargs -t -P4 -I'{}' uv pip compile -q --universal --allow-unsafe --strip-extras --no-annotate --no-header -U '{}.in' -o '{}.txt'

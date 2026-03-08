#!/usr/bin/env bash
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────
TEAL='\033[38;2;93;228;199m'
DIM='\033[2m'
GREEN='\033[32m'
BOLD='\033[1m'
RESET='\033[0m'

# ── ASCII Logo ──────────────────────────────────────────────────────
echo ""
echo -e "${TEAL}  ██████╗  ██████╗ ██████╗ ${RESET}"
echo -e "${TEAL} ██╔════╝ ██╔════╝ ██╔══██╗${RESET}"
echo -e "${TEAL} ██║  ███╗██║      ██║  ██║${RESET}"
echo -e "${TEAL} ██║   ██║██║      ██║  ██║${RESET}"
echo -e "${TEAL} ╚██████╔╝╚██████╗ ██████╔╝${RESET}"
echo -e "${TEAL}  ╚═════╝  ╚═════╝ ╚═════╝ ${RESET}"
echo ""
echo -e "${DIM}Get Content Done v1.2.0${RESET}"
echo -e "A skill-based content production framework for Claude Code."
echo ""

# ── Resolve paths ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/skills"
AGENTS_SRC="${SCRIPT_DIR}/agents"

CLAUDE_DIR="${HOME}/.claude"
SKILLS_DEST="${CLAUDE_DIR}/skills"
AGENTS_DEST="${CLAUDE_DIR}/agents"

# ── Validate source ────────────────────────────────────────────────
if [[ ! -d "${SKILLS_SRC}" ]] || [[ ! -d "${AGENTS_SRC}" ]]; then
  echo -e "\033[31mError: skills/ or agents/ directory not found in ${SCRIPT_DIR}\033[0m"
  echo "Make sure you're running this from the get-content-done repo root."
  exit 1
fi

# ── Create destinations ────────────────────────────────────────────
mkdir -p "${SKILLS_DEST}"
mkdir -p "${AGENTS_DEST}"

# ── Install skills ─────────────────────────────────────────────────
SKILL_COUNT=0
for skill_dir in "${SKILLS_SRC}"/*/; do
  skill_name="$(basename "${skill_dir}")"
  cp -r "${skill_dir}" "${SKILLS_DEST}/${skill_name}"
  SKILL_COUNT=$((SKILL_COUNT + 1))
done

# ── Install agents ─────────────────────────────────────────────────
AGENT_COUNT=0
for agent_file in "${AGENTS_SRC}"/*.md; do
  cp "${agent_file}" "${AGENTS_DEST}/"
  AGENT_COUNT=$((AGENT_COUNT + 1))
done

# ── Summary ────────────────────────────────────────────────────────
echo -e " ${GREEN}✔${RESET} Installed /gcd slash commands"
echo -e " ${GREEN}✔${RESET} Installed ${BOLD}${SKILL_COUNT} skills${RESET}"
echo -e " ${GREEN}✔${RESET} Installed ${BOLD}${AGENT_COUNT} agents${RESET}"
echo ""
echo -e "${TEAL}Ready. Let's get started...${RESET}"
echo ""

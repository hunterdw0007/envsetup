# shellcheck shell=bash
# shellcheck disable=SC2034 # a palette for other files and your own shell: unused here by design
# ANSI color and style variables, loaded by functions.sh.
# Usage: echo -e "${RED}This is red text${RESET}"; run show_colors to see them all.

# Reset
RESET='\033[0m'       # Text Reset

# Regular Colors
BLACK='\033[0;30m'        # Black
RED='\033[0;31m'          # Red
GREEN='\033[0;32m'        # Green
YELLOW='\033[0;33m'       # Yellow
BLUE='\033[0;34m'         # Blue
PURPLE='\033[0;35m'       # Purple
CYAN='\033[0;36m'         # Cyan
WHITE='\033[0;37m'        # White

# Bold Colors
BOLD_BLACK='\033[1;30m'   # Bold Black
BOLD_RED='\033[1;31m'     # Bold Red
BOLD_GREEN='\033[1;32m'   # Bold Green
BOLD_YELLOW='\033[1;33m'  # Bold Yellow
BOLD_BLUE='\033[1;34m'    # Bold Blue
BOLD_PURPLE='\033[1;35m'  # Bold Purple
BOLD_CYAN='\033[1;36m'    # Bold Cyan
BOLD_WHITE='\033[1;37m'   # Bold White

# Underlined Colors
UNDERLINE_BLACK='\033[4;30m'   # Underlined Black
UNDERLINE_RED='\033[4;31m'     # Underlined Red
UNDERLINE_GREEN='\033[4;32m'   # Underlined Green
UNDERLINE_YELLOW='\033[4;33m'  # Underlined Yellow
UNDERLINE_BLUE='\033[4;34m'    # Underlined Blue
UNDERLINE_PURPLE='\033[4;35m'  # Underlined Purple
UNDERLINE_CYAN='\033[4;36m'    # Underlined Cyan
UNDERLINE_WHITE='\033[4;37m'   # Underlined White

# Background Colors
BG_BLACK='\033[40m'       # Black Background
BG_RED='\033[41m'         # Red Background
BG_GREEN='\033[42m'       # Green Background
BG_YELLOW='\033[43m'      # Yellow Background
BG_BLUE='\033[44m'        # Blue Background
BG_PURPLE='\033[45m'      # Purple Background
BG_CYAN='\033[46m'        # Cyan Background
BG_WHITE='\033[47m'       # White Background

# High Intensity (Bright) Colors
BRIGHT_BLACK='\033[0;90m'     # Bright Black (Gray)
BRIGHT_RED='\033[0;91m'       # Bright Red
BRIGHT_GREEN='\033[0;92m'     # Bright Green
BRIGHT_YELLOW='\033[0;93m'    # Bright Yellow
BRIGHT_BLUE='\033[0;94m'      # Bright Blue
BRIGHT_PURPLE='\033[0;95m'    # Bright Purple
BRIGHT_CYAN='\033[0;96m'      # Bright Cyan
BRIGHT_WHITE='\033[0;97m'     # Bright White

# High Intensity Background Colors
BG_BRIGHT_BLACK='\033[0;100m'   # Bright Black Background
BG_BRIGHT_RED='\033[0;101m'     # Bright Red Background
BG_BRIGHT_GREEN='\033[0;102m'   # Bright Green Background
BG_BRIGHT_YELLOW='\033[0;103m'  # Bright Yellow Background
BG_BRIGHT_BLUE='\033[0;104m'    # Bright Blue Background
BG_BRIGHT_PURPLE='\033[0;105m'  # Bright Purple Background
BG_BRIGHT_CYAN='\033[0;106m'    # Bright Cyan Background
BG_BRIGHT_WHITE='\033[0;107m'   # Bright White Background

# Text Styles
BOLD='\033[1m'            # Bold
DIM='\033[2m'             # Dim/Faint
ITALIC='\033[3m'          # Italic
UNDERLINE='\033[4m'       # Underline
BLINK='\033[5m'           # Blink
REVERSE='\033[7m'         # Reverse/Invert
STRIKETHROUGH='\033[9m'   # Strikethrough

# Reset Styles (turn off specific formatting)
RESET_BOLD='\033[21m'         # Reset Bold
RESET_DIM='\033[22m'          # Reset Dim
RESET_ITALIC='\033[23m'       # Reset Italic
RESET_UNDERLINE='\033[24m'    # Reset Underline
RESET_BLINK='\033[25m'        # Reset Blink
RESET_REVERSE='\033[27m'      # Reset Reverse
RESET_STRIKETHROUGH='\033[29m' # Reset Strikethrough

# Convenience aliases
NC=$RESET                 # No Color (same as RESET)
GRAY=$BRIGHT_BLACK        # Gray alias
GREY=$BRIGHT_BLACK        # Grey alias

# Function to display all colors (optional demo function)
show_colors() {
	echo -e "${BOLD}Regular Colors:${RESET}"
	echo -e "${BLACK}BLACK${RESET} ${RED}RED${RESET} ${GREEN}GREEN${RESET} ${YELLOW}YELLOW${RESET}"
	echo -e "${BLUE}BLUE${RESET} ${PURPLE}PURPLE${RESET} ${CYAN}CYAN${RESET} ${WHITE}WHITE${RESET}"

	echo -e "\n${BOLD}Bold Colors:${RESET}"
	echo -e "${BOLD_BLACK}BOLD_BLACK${RESET} ${BOLD_RED}BOLD_RED${RESET} ${BOLD_GREEN}BOLD_GREEN${RESET} ${BOLD_YELLOW}BOLD_YELLOW${RESET}"
	echo -e "${BOLD_BLUE}BOLD_BLUE${RESET} ${BOLD_PURPLE}BOLD_PURPLE${RESET} ${BOLD_CYAN}BOLD_CYAN${RESET} ${BOLD_WHITE}BOLD_WHITE${RESET}"

	echo -e "\n${BOLD}Bright Colors:${RESET}"
	echo -e "${BRIGHT_BLACK}BRIGHT_BLACK${RESET} ${BRIGHT_RED}BRIGHT_RED${RESET} ${BRIGHT_GREEN}BRIGHT_GREEN${RESET} ${BRIGHT_YELLOW}BRIGHT_YELLOW${RESET}"
	echo -e "${BRIGHT_BLUE}BRIGHT_BLUE${RESET} ${BRIGHT_PURPLE}BRIGHT_PURPLE${RESET} ${BRIGHT_CYAN}BRIGHT_CYAN${RESET} ${BRIGHT_WHITE}BRIGHT_WHITE${RESET}"

	echo -e "\n${BOLD}Text Styles:${RESET}"
	echo -e "${BOLD}BOLD${RESET} ${DIM}DIM${RESET} ${ITALIC}ITALIC${RESET} ${UNDERLINE}UNDERLINE${RESET}"
	echo -e "${BLINK}BLINK${RESET} ${REVERSE}REVERSE${RESET} ${STRIKETHROUGH}STRIKETHROUGH${RESET}"

	echo -e "\n${BOLD}Background Colors:${RESET}"
	echo -e "${BG_RED}${WHITE} RED BG ${RESET} ${BG_GREEN}${BLACK} GREEN BG ${RESET} ${BG_BLUE}${WHITE} BLUE BG ${RESET}"
}

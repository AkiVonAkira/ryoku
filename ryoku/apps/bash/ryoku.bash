# shellcheck shell=bash disable=SC1090,SC1091,SC1094
[[ ${__RYOKU_BASH_LOADED:-0} == 1 ]] && return
__RYOKU_BASH_LOADED=1

_ryoku_env=${XDG_CONFIG_HOME:-$HOME/.config}/ryoku-terminal/env.sh
[[ -r $_ryoku_env ]] || _ryoku_env=$(cd "$(dirname "${BASH_SOURCE[0]}")/../terminal-shell" 2>/dev/null && pwd)/env.sh
[[ -r $_ryoku_env ]] && . "$_ryoku_env"
unset _ryoku_env

[[ $- == *i* ]] || return

command -v ryoku-fastfetch >/dev/null 2>&1 && ryoku-fastfetch
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash --cmd cd)"
command -v mise >/dev/null 2>&1 && eval "$(mise activate bash)"
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"

[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
# command and keyword faces follow the active colour scheme (rendered by the
# theme daemon); vermillion is only the default palette's value.
_ryoku_colors=${XDG_CONFIG_HOME:-$HOME/.config}/ryoku-terminal/colors.sh
[[ -r $_ryoku_colors ]] && . "$_ryoku_colors"
_ryoku_cmd=${RYOKU_SYNTAX_COMMAND:-#e2342a}
_ryoku_kw=${RYOKU_SYNTAX_KEYWORD:-#e83b30}
unset _ryoku_colors RYOKU_SYNTAX_COMMAND RYOKU_SYNTAX_KEYWORD
if [[ -r /usr/share/blesh/ble.sh ]]; then
  . /usr/share/blesh/ble.sh --noattach
  ble-face -s syntax_default fg=#F1F3E4 2>/dev/null || true
  ble-face -s syntax_command fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s syntax_function_name fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s command_builtin fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s command_alias fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s command_function fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s command_file fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s command_jobs fg="$_ryoku_cmd" 2>/dev/null || true
  ble-face -s command_keyword fg="$_ryoku_kw" 2>/dev/null || true
  ble-face -s syntax_varname fg=#93D4E0 2>/dev/null || true
  ble-face -s syntax_param_expansion fg=#93D4E0 2>/dev/null || true
  ble-face -s syntax_history_expansion fg=#93D4E0 2>/dev/null || true
  ble-face -s syntax_glob fg=#93D4E0 2>/dev/null || true
  ble-face -s syntax_brace fg=#93D4E0 2>/dev/null || true
  ble-face -s syntax_delimiter fg=#93D4E0 2>/dev/null || true
  ble-face -s syntax_quoted fg=#A3C293 2>/dev/null || true
  ble-face -s syntax_quotation fg=#A3C293 2>/dev/null || true
  ble-face -s syntax_error fg=#FF6B6B 2>/dev/null || true
  ble-face -s syntax_comment fg=#949699 2>/dev/null || true
  ble-face -s auto_complete fg=#949699 2>/dev/null || true
fi
unset _ryoku_cmd _ryoku_kw
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"

if command -v eza >/dev/null 2>&1; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

_ryoku_cfg=${XDG_CONFIG_HOME:-$HOME/.config}
[[ -r $_ryoku_cfg/bash/rashin.bash ]] && . "$_ryoku_cfg/bash/rashin.bash"
[[ -r $_ryoku_cfg/bash/user.bash ]] && . "$_ryoku_cfg/bash/user.bash"
unset _ryoku_cfg

if declare -F ble-attach >/dev/null; then
  ble-attach || true
fi

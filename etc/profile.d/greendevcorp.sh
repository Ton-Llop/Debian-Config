#!/usr/bin/env bash
# GSX Week 4 - shared shell environment for GreenDevCorp developers
# Loaded by login shells via /etc/profile.d/

if id -nG 2>/dev/null | grep -qw greendevcorp; then
  case ":${PATH}:" in
    *:/home/greendevcorp/bin:*) ;;
    *) PATH="/home/greendevcorp/bin:${PATH}" ;;
  esac
  export PATH

  # Safer default permissions for new files outside shared directories.
  umask 0027

  alias ll='ls -alF --color=auto'
  alias cdtm='cd /home/greendevcorp/shared'
  alias donelog='tail -n 20 /home/greendevcorp/done.log'
  alias teambin='ls -l /home/greendevcorp/bin'
fi

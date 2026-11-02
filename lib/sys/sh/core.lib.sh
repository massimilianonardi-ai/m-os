
loadlib()
{
  [ "$#" -eq 1 ] || return 1

  set -- "$m_LIB_DIR/${1}.lib.sh"
  [ -f "$1" ] && [ -r "$1" ] || return 2

  . "$1"
}

loadlib "sys/sh/base"
loadlib "sys/sh/context"

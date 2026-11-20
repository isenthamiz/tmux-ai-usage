# shellcheck shell=bash
# personal vs ebay: which acquire/normalize pair refresh and smoke use.

valid_profile() { # value
  case $1 in
    personal|ebay) return 0 ;;
  esac
  return 1
}

_acquire_basename() { # profile
  case $1 in
    ebay) echo acquire.ebay.sh ;;
    *) echo acquire.sh ;;
  esac
}

_normalize_basename() { # profile
  case $1 in
    ebay) echo normalize.ebay.jq ;;
    *) echo normalize.jq ;;
  esac
}

provider_acquire_path() { # scripts-dir provider profile
  local root=$1 prov=$2 prof=$3 base path
  base=$(_acquire_basename "$prof")
  path="$root/providers/$prov/$base"
  [ -f "$path" ] || return 1
  printf '%s' "$path"
}

provider_normalize_path() { # scripts-dir provider profile
  local root=$1 prov=$2 prof=$3 base path
  if [ "$prof" = ebay ] && [ -f "$root/lib/normalize.ebay.jq" ]; then
    printf '%s' "$root/lib/normalize.ebay.jq"
    return 0
  fi
  base=$(_normalize_basename "$prof")
  path="$root/providers/$prov/$base"
  [ -f "$path" ] || return 1
  printf '%s' "$path"
}
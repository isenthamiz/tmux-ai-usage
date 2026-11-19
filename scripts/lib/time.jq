# ISO-8601 timestamp -> epoch seconds. jq's fromdateiso8601 only accepts
# "YYYY-MM-DDTHH:MM:SSZ", but providers also send fractional seconds and UTC
# offsets (Claude: "2026-11-19T12:00:00.182838+00:00"). Numbers pass through as
# epoch seconds; anything unparseable becomes null.
def iso_epoch:
  if type == "number" then floor
  elif type == "string" then
    (capture("^(?<base>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<tz>Z|[+-][0-9]{2}:?[0-9]{2})$") // null) as $m
    | if $m == null then null
      else
        ($m.base + "Z" | fromdateiso8601) as $local
        | if $m.tz == "Z" then $local
          else ($m.tz | gsub(":"; "")) as $tz
            | (if ($tz | startswith("-")) then -1 else 1 end) as $sign
            | ($tz[1:3] | tonumber) as $h | ($tz[3:5] | tonumber) as $min
            | $local - $sign * ($h * 3600 + $min * 60)
          end
      end
  else null end;

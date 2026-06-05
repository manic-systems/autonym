use parse.nu

export def "signatures" [lines: list<string>]: nothing -> list {
  $lines | each {|l| parse line $l } | flatten
}

export def "group" [sigs: list]: nothing -> list {
  $sigs
  | group-by key
  | items {|key, rows|
      let canonical = (
        $rows | group-by body
        | items {|b, occ| { row: ($occ | first), n: ($occ | length) } }
        | sort-by n --reverse | first | get row
      )
      {
        key: $key
        count: ($rows | length)
        body: $canonical.body
        head: $canonical.head
        subcommands: $canonical.subcommands
        flags: $canonical.flags
        body_len: ($canonical.body | str length)
      }
    }
}

def worth-keeping [cand: record, min_count: int]: nothing -> bool {
  if $cand.count < $min_count { return false }
  if (not ($cand.body | str contains " ")) and ($cand.body | str length) <= 3 {
    return false
  }
  true
}

export def "prepare" [
  lines: list<string>
  --min-count: int = 8
]: nothing -> record {
  let sigs = (signatures $lines)
  let aliases = (try { scope aliases | get name } catch { [] })
  let ranked = (
    group $sigs
    | where {|c| worth-keeping $c $min_count }
    | where {|c| $c.head not-in $aliases }
    | insert score {|c| $c.count * ([($c.body_len - 2) 1] | math max) }
    | sort-by score count --reverse
  )
  { ranked: $ranked, heads: ($sigs | get head | uniq) }
}

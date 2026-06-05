use syllable.nu

def split-words [token: string]: nothing -> list<string> {
  $token | str downcase | split row --regex '[-_]+' | where {|w| $w != "" }
}

def flag-words [cand: record]: nothing -> list<string> {
  $cand.flags
    | each {|f| $f | str trim --left --char '-' | str downcase | str replace --all --regex '[-_]+' '' }
    | where {|w| $w != "" }
}

export def "candidates" [cand: record]: nothing -> list<string> {
  let core = ([$cand.head] ++ $cand.subcommands | each {|t| split-words $t } | flatten)
  if ($core | is-empty) { return [] }

  let core_cands = (syllable candidates $core)
  if ($core_cands | is-empty) { return [] }

  let flags = (flag-words $cand)
  let pool = (
    if ($flags | is-empty) {
      $core_cands
    } else {
      let flaghead = ($flags | each {|f| $f | str substring 0..0 } | str join)
      $core_cands | each {|c| $c + $flaghead }
    }
  )
  # digit fallback on the shortest candidate, for when everything collides
  let base = ($pool | first)
  $pool | append ([2 3 4 5 6 7 8 9] | each {|d| $"($base)($d)" }) | uniq
}

export def "collision-base" [heads: list<string>]: nothing -> list<string> {
  let cmds = (try { scope commands | get name } catch { [] })
  let aliases = (try { scope aliases | get name } catch { [] })
  let path_bins = (
    $env.PATH? | default []
    | each {|d| try { ls $d | get name | path basename } catch { [] } }
    | flatten
  )
  $cmds ++ $aliases ++ $path_bins ++ $heads | uniq
}

export def "assign" [
  ranked: list
  --min-savings: int = 3
  --reserved-heads: list<string> = []
]: nothing -> list {
  let heads = ($reserved_heads | append ($ranked | get head) | uniq)
  let reserved = (collision-base $heads)

  mut taken = ($reserved | reduce --fold {} {|n, acc| $acc | insert $n true })
  mut results = []

  for cand in $ranked {
    let names = (candidates $cand)
    let chosen = (
      $names
      | where {|n| ($n | str length) >= 2 }
      | where {|n| ($cand.body_len - ($n | str length)) >= $min_savings }
      | where {|n| ($taken | get -o $n) != true }
      | first
    )
    if ($chosen == null) { continue }
    $taken = ($taken | insert $chosen true)
    $results = ($results | append (
      $cand | insert name $chosen | insert savings ($cand.body_len - ($chosen | str length))
    ))
  }
  $results
}

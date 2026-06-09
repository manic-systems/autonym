use ingest.nu
use analyze.nu
use name.nu
use emit.nu
use review.nu
use hook.nu

export use hook.nu

def fmt-row [r: record]: nothing -> string {
  let name = ($r.name | fill --alignment left --width 8)
  let body = ($r.body | fill --alignment left --width 32)
  $"  ($name) ($body) (ansi attr_dimmed)($r.count)×, saves ($r.savings)(ansi reset)"
}

# dry run of `generate`
export def "scan" [
  --min-count: int = 8
  --min-savings: int = 3
  --top: int = 40
  --history: string
  --limit: int = -1
]: nothing -> nothing {
  let lines = (ingest read --source $history --limit $limit)
  let prep = (analyze prepare $lines --min-count $min_count)
  let named = (name assign $prep.ranked --min-savings $min_savings --reserved-heads $prep.heads)
  let shown = ($named | first ([$top ($named | length)] | math min))
  print $"  (ansi attr_bold)($named | length) candidate aliases(ansi reset) from ($lines | length) history lines"
  $shown | each {|r| print (fmt-row $r) }
  null
}

export def "generate" [
  --min-count: int = 8
  --min-savings: int = 3
  --top: int
  --history: string
  --out: string
  --limit: int = -1
  --no-review  # only write file
]: nothing -> nothing {
  let res = (hook rescan --min-count $min_count --min-savings $min_savings --top $top --source $history --out $out --limit $limit)
  let s = $res.summary
  print $"  (ansi green)wrote ($s.path)(ansi reset)"
  print $"  ($s.enabled) enabled · ($s.suggested) suggested · ($s.rejected) rejected"

  let interactive = ((is-terminal --stdin) and (is-terminal --stdout))
  if $no_review or ($out != null) or (not $interactive) {
    print ""
    print $"  (ansi attr_dimmed)enabled aliases will load in new shells from:(ansi reset)"
    print $"    ($s.path)"
    print $"  (ansi attr_dimmed)for this shell, run:(ansi reset) source ($s.path)"
    return
  }

  print ""
  main
  # remind to load freshly-enabled aliases into the current shell
  if (emit read-state | get enabled | length) > 0 {
    print $"  (ansi attr_dimmed)for this shell, run:(ansi reset) source ($s.path)"
  }
  null
}

export def "status" []: nothing -> nothing {
  let st = (emit read-state)
  let p = (emit read-pending)
  print $"  enabled   ($st.enabled | length)"
  print $"  rejected  ($st.rejected | length)"
  print $"  pending   ($p.count)"
  null
}

export def "enable" [name: string]: nothing -> nothing {
  if (emit enable $name) {
    print $"  (ansi green)enabled ($name)(ansi reset)"
  } else {
    print $"  (ansi red)no suggestion named ($name)(ansi reset)"
  }
  null
}

export def "reject" [name: string]: nothing -> nothing {
  if (emit reject $name) {
    print $"  (ansi yellow)rejected ($name)(ansi reset)"
  } else {
    print $"  (ansi red)nothing to reject named ($name)(ansi reset)"
  }
  null
}

# the following is the help text

# autonym - automatic pseudonym generator
#
# commands:
#   autonym                review suggestions interactively
#   autonym scan           preview suggestions
#   autonym generate       regenerate potential aliases
#   autonym status         enabled / rejected / pending counts
#   autonym enable <name>  turn a suggestion on
#   autonym reject <name>  dismiss a suggestion for good
export def "main" []: nothing -> nothing {
  loop {
    let path = (emit aliases-path)
    if (not ($path | path exists)) {
      print $"  (ansi attr_dimmed)no suggestions yet; run(ansi reset) autonym generate"
      return
    }
    let lines = (open --raw $path | lines)
    let st = (emit read-state --path $path)
    let rows = (
      $lines
      | each {|l| $l | parse --regex '^\s*#\s*alias\s+(?<name>[^\s=]+)\s*=\s*(?<body>.+?)\s*#\s*(?<count>\d+)×' }
      | flatten
      | each {|s| { name: $s.name, body: ($s.body | str trim), state: "unconfirmed", key: ($s.body | str trim) } }
    )
    let enabled_rows = ($st.enabled | each {|e| { name: $e.name, body: $e.body, state: "confirmed", key: $e.body } })
    let rejected_rows = ($st.rejected | where {|r| $r.body | is-not-empty } | each {|r| { name: $r.name, body: $r.body, state: "denied", key: $r.body } })
    let all = ($enabled_rows | append $rows | append $rejected_rows)
    if ($all | is-empty) {
      print $"  (ansi green)nothing to review(ansi reset)"
      emit mark-seen
      return
    }
    let initial = ($all | reduce --fold {} {|r, acc| $acc | upsert $r.name $r.state })
    let decided = (review run $all)
    emit mark-seen
    if $decided == null { return }
    $decided.rows | each {|r|
      if $r.state == ($initial | get $r.name) { return }
      match $r.state {
        "confirmed" => { emit enable $r.name --body $r.body | ignore }
        "denied" => { emit reject $r.name --body $r.body | ignore }
        _ => { emit forget $r.name | ignore }
      }
    }
    match $decided.action {
      "regen" => { review spin "regenerating suggestions…" {|| hook rescan }; continue }
      "search" => { search-add; continue }
      "add" => { add-alias (input $"  command to alias: "); continue }
      _ => { print $"  (ansi green)saved(ansi reset)"; return }
    }
  }
}

def add-alias [body: string]: nothing -> nothing {
  let body = ($body | str trim)
  if ($body | is-empty) { return }
  let reserved = (emit read-state | get enabled | get name)
  let proposed = (name propose $body --reserved $reserved)
  let hint = (if ($proposed == null) { "" } else { $" [($proposed)]" })
  let typed = (input $"  alias name($hint): " | str trim)
  let nm = (if ($typed | is-empty) { $proposed } else { $typed })
  if ($nm == null or ($nm | is-empty)) {
    print $"  (ansi attr_dimmed)no name; skipped(ansi reset)"
    return
  }
  if (emit enable $nm --body $body) {
    print $"  [(ansi green)✓(ansi reset)] added (ansi attr_bold)($nm)(ansi reset) = ($body)"
  } else {
    print $"  (ansi red)could not add ($nm)(ansi reset)"
  }
}

# fuzzy-search the full shell history for a command to alias
def search-add []: nothing -> nothing {
  let enabled_bodies = (emit read-state | get enabled | get body)
  let ranked = (
    ingest read --limit 0
    | uniq --count
    | sort-by count --reverse
    | get value
    | where {|c| ($c | str length) > 2 and ($c not-in $enabled_bodies) }
  )
  if ($ranked | is-empty) {
    print $"  (ansi attr_dimmed)no history to search(ansi reset)"
    return
  }
  print -n $"(ansi -e '2J')(ansi -e 'H')"
  let pick = ($ranked | input list --fuzzy "search history")
  if ($pick | is-empty) { return }
  add-alias $pick
}

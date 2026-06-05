export def "state-dir" []: nothing -> string {
  let base = ($env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state))
  $base | path join autonym
}
export def "aliases-path" []: nothing -> string {
  let autoload = ($nu.user-autoload-dirs? | default [] | get -o 0)
  if ($autoload | is-empty) {
    state-dir | path join aliases.nu
  } else {
    $autoload | path join autonym-aliases.nu
  }
}
export def "pending-path" []: nothing -> string { state-dir | path join pending.nuon }

const HEADER = "# autonym managed file. enabled aliases survive regeneration."
const SUBTITLE = "# run `autonym` to review, `autonym generate` to refresh, uncomment a line to enable."
const SEC_ENABLED = "# --- enabled ---"
const SEC_REJECTED = "# --- rejected (will not be re-suggested) ---"
const SEC_SUGGEST = "# --- suggestions (uncomment to enable; kept on next run) ---"

export def "read-state" [--path: string]: nothing -> record {
  let p = ($path | default (aliases-path))
  if (not ($p | path exists)) { return { enabled: [], rejected: [] } }
  let raw = (open --raw $p | lines)

  let enabled = (
    $raw
    | each {|l| $l | parse --regex '^\s*alias\s+(?<name>[^\s=]+)\s*=\s*(?<body>.+)$' }
    | flatten
    | each {|r| { name: $r.name, body: ($r.body | str replace --regex '\s+#.*$' '' | str trim) } }
  )
  let rejected = (
    $raw
    | each {|l| $l | parse --regex '^\s*#\s*reject:\s*(?<name>\S+?)(\s*=\s*(?<body>.+))?\s*$' }
    | flatten
    | each {|r| { name: $r.name, body: ($r.body? | default "" | str trim) } }
  )
  { enabled: $enabled, rejected: $rejected }
}

def parse-suggestion-lines [lines: list<string>]: nothing -> list {
  $lines
  | each {|l| $l | parse --regex '^\s*#\s*alias\s+(?<name>[^\s=]+)\s*=\s*(?<body>.+?)\s*#\s*(?<count>\d+)×,\s*saves\s*(?<savings>\d+)/use\s*$' }
  | flatten
  | each {|s| { name: $s.name, body: ($s.body | str trim), count: ($s.count | into int), savings: ($s.savings | into int) } }
}

def render-suggestion [s: record]: nothing -> string {
  let head = $"# alias ($s.name) = ($s.body)"
  let padded = ($head | fill --alignment left --width 40)
  $"($padded) # ($s.count)×, saves ($s.savings)/use"
}

def render-file [enabled: list, rejected: list, suggestions: list]: nothing -> string {
  let enabled_lines = ($enabled | each {|e| $"alias ($e.name) = ($e.body)" })
  let rejected_lines = ($rejected | uniq-by name | each {|r|
    if ($r.body | is-empty) { $"# reject: ($r.name)" } else { $"# reject: ($r.name) = ($r.body)" }
  })
  let suggest_lines = ($suggestions | each {|s| render-suggestion $s })
  [
    $HEADER
    $SUBTITLE
    ""
    $SEC_ENABLED
    ...$enabled_lines
    ""
    $SEC_REJECTED
    ...$rejected_lines
    ""
    $SEC_SUGGEST
    ...$suggest_lines
    ""
  ] | str join "\n"
}

# regenerates suggestions, never touching enabled aliases or rejections
export def "write" [named: list, --out: string]: nothing -> record {
  let path = ($out | default (aliases-path))
  $path | path dirname | mkdir $in

  let state = (read-state --path $path)
  let enabled_names = ($state.enabled | get name)
  let enabled_bodies = ($state.enabled | get body)
  let rejected_names = ($state.rejected | get name)

  let suggestions = (
    $named
    | where {|s| $s.name not-in $enabled_names }
    | where {|s| $s.body not-in $enabled_bodies }
    | where {|s| $s.name not-in $rejected_names }
    | select name body count savings
  )

  render-file $state.enabled $state.rejected $suggestions | save --force $path
  { enabled: ($state.enabled | length), suggested: ($suggestions | length), rejected: ($state.rejected | length), path: $path }
}

def lookup-body [name: string, sugg: list, enabled: list]: nothing -> string {
  let cands = (($sugg | where name == $name | get body) ++ ($enabled | where name == $name | get body))
  $cands | get -o 0 | default ""
}

export def "enable" [name: string, --body: string, --path: string]: nothing -> bool {
  let p = ($path | default (aliases-path))
  if (not ($p | path exists)) { return false }
  let state = (read-state --path $p)
  if ($name in ($state.enabled | get name)) { return true }
  let lines = (open --raw $p | lines)
  let re = ('^\s*#\s*alias\s+' + $name + '\s*=\s*(?<body>.+)$')
  let match = ($lines | each {|l| $l | parse --regex $re } | flatten | get -o 0)
  let derived = (if ($match != null) { $match.body | str replace --regex '\s+#.*$' '' | str trim } else { null })
  let b = ($body | default $derived)
  if ($b == null or ($b | is-empty)) { return false }
  let enabled = ($state.enabled | append { name: $name, body: $b })
  let rejected = ($state.rejected | where name != $name)
  let suggestions = (parse-suggestion-lines $lines | where name != $name)
  render-file $enabled $rejected $suggestions | save --force $p
  true
}

export def "reject" [name: string, --body: string, --path: string]: nothing -> bool {
  let p = ($path | default (aliases-path))
  if (not ($p | path exists)) { return false }
  let state = (read-state --path $p)
  if ($name in ($state.rejected | get name)) { return true }
  let lines = (open --raw $p | lines)
  let sugg = (parse-suggestion-lines $lines)
  let b = ($body | default (lookup-body $name $sugg $state.enabled))
  let rejected = ($state.rejected | append { name: $name, body: $b })
  let enabled = ($state.enabled | where name != $name)
  let suggestions = ($sugg | where name != $name)
  render-file $enabled $rejected $suggestions | save --force $p
  true
}

export def "forget" [name: string, --path: string]: nothing -> bool {
  let p = ($path | default (aliases-path))
  if (not ($p | path exists)) { return false }
  let state = (read-state --path $p)
  let lines = (open --raw $p | lines)
  let enabled = ($state.enabled | where name != $name)
  let rejected = ($state.rejected | where name != $name)
  let suggestions = (parse-suggestion-lines $lines | where name != $name)
  render-file $enabled $rejected $suggestions | save --force $p
  true
}

def pending-hash [names: list<string>]: nothing -> string {
  $names | sort | str join "\n" | hash sha256
}

export def "write-pending" [
  names: list<string>
  history_len: int
  now: any
]: nothing -> record {
  let p = (pending-path)
  $p | path dirname | mkdir $in
  let h = (pending-hash $names)
  let prev = (try { open $p } catch { null })
  let seen = (if ($prev != null and ($prev.hash? == $h)) { $prev.seen? | default false } else { false })
  let marker = { count: ($names | length), hash: $h, seen: $seen, last_run: $now, history_len: $history_len }
  $marker | save --force $p
  $marker
}

export def "read-pending" []: nothing -> record {
  let p = (pending-path)
  try { open $p } catch { { count: 0, hash: "", seen: true, last_run: null, history_len: 0 } }
}

export def "mark-seen" []: nothing -> nothing {
  let p = (pending-path)
  if ($p | path exists) {
    open $p | upsert seen true | save --force $p
  }
}

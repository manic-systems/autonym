const MAXVIS = 9

const GLYPH = {
  unconfirmed: { c: "yellow", g: "*" }
  confirmed: { c: "green", g: "✓" }
  denied: { c: "red", g: "✗" }
}

def glyph [state: string]: nothing -> string {
  let e = ($GLYPH | get $state)
  $"[(ansi $e.c)($e.g)(ansi reset)]"
}

def cycle [state: string]: nothing -> string {
  match $state {
    "unconfirmed" => "confirmed"
    "confirmed" => "denied"
    _ => "unconfirmed"
  }
}

def render-row [r: record, state: string, selected: bool]: nothing -> string {
  let gutter = (if $selected { $"(ansi attr_reverse)>(ansi reset)" } else { " " })
  $"($gutter) (glyph $state) ($r.body)  ($r.name)"
}

def visible-idx [initial: list<string>, show_removed: bool]: nothing -> list<int> {
  0..<($initial | length) | where {|i| $show_removed or (($initial | get $i) != "denied") }
}

def redraw [
  rows: list, states: list<string>, initial: list<string>
  show_removed: bool, pos: int, top: int, prev: int
]: nothing -> int {
  let vis = (visible-idx $initial $show_removed)
  let lines = if ($vis | is-empty) {
    [$"  (ansi attr_dimmed)no entries; press r to show removed(ansi reset)"]
  } else {
    let total = ($vis | length)
    let h = ([$total $MAXVIS] | math min)
    let win = ($vis | skip $top | first $h)
    let counter = (if $total > $h { $"($top + 1)-($top + $h)/($total)" } else { $"($total)" })
    let removed = (if $show_removed { "" } else { "  ·  r: removed" })
    let header = $"  (ansi attr_dimmed)($counter)($removed)(ansi reset)"
    [$header] ++ ($win | enumerate | each {|it|
      render-row ($rows | get $it.item) ($states | get $it.item) (($top + $it.index) == $pos)
    })
  }
  let cur = ($lines | length)
  let eol = (ansi -e '0K')
  mut out = (if $prev > 0 { ansi -e $"($prev)F" } else { "" })
  $out = $out + ($lines | each {|l| $l + $eol } | str join "\n") + "\n"
  if $prev > $cur {
    let extra = ($prev - $cur)
    $out = $out + ((1..$extra | each {|_| $eol } | str join "\n") + "\n")
    $out = $out + (ansi -e $"($extra)F")
  }
  print -n $out
  $cur
}

const SPINNER = ["/" "-" "\\" "|"]

# run `work` in a background job, animating a spinner with `label` until it ends
export def "spin" [label: string, work: closure]: nothing -> nothing {
  let n = ($SPINNER | length)
  print -n (ansi -e '?25l')
  job spawn { try { do $work } catch {|e| }; "done" | job send 0 } | ignore
  mut i = 0
  loop {
    let done = (try { job recv --timeout 100ms | ignore; true } catch { false })
    if $done { break }
    print -n $"\r  [(ansi blue)($SPINNER | get ($i mod $n))(ansi reset)] ($label)"
    $i = $i + 1
  }
  print -n $"\r(ansi -e '0K')(ansi -e '?25h')"
}

export def "run" [rows: list]: nothing -> any {
  if ($rows | is-empty) {
    print $"  (ansi green)nothing to review(ansi reset)"
    return null
  }
  let initial = ($rows | get state)

  print -n $"(ansi -e '2J')(ansi -e 'H')"
  print $"  (ansi attr_dimmed)jk move · space cycle · y/x enable/reject · a add · s search · g regen · r removed · enter save · esc cancel(ansi reset)"
  print -n (ansi -e '?25l')
  mut states = $initial
  mut show_removed = false
  mut pos = 0
  mut top = 0
  mut drawn = (redraw $rows $states $initial $show_removed $pos $top 0)

  mut result: any = null
  loop {
    let ev = (input listen --types [key])
    let code = ($ev.code? | default "")
    if ($code == "esc" or ($ev.key_type? == "char" and $code == "q")) { break }
    if ($code in ["enter" "g" "s" "a"]) {
      let final = $states
      $result = {
        action: (match $code { "enter" => "save", "g" => "regen", "s" => "search", _ => "add" })
        rows: ($rows | enumerate | each {|it| $it.item | upsert state ($final | get $it.index) })
      }
      break
    }

    if $code == "r" {
      $show_removed = (not $show_removed)
      $pos = 0
      $top = 0
    } else {
      let vis = (visible-idx $initial $show_removed)
      if ($vis | is-not-empty) {
        let count = ($vis | length)
        let abs = ($vis | get $pos)
        match $code {
          "up" | "k" => { $pos = (($pos - 1 + $count) mod $count) }
          "down" | "j" => { $pos = (($pos + 1) mod $count) }
          " " | "tab" => { $states = ($states | update $abs (cycle ($states | get $abs))) }
          "y" => { $states = ($states | update $abs "confirmed") }
          "x" => { $states = ($states | update $abs "denied") }
          _ => {}
        }
      }
    }

    let vis = (visible-idx $initial $show_removed)
    let count = ($vis | length)
    let h = ([$count $MAXVIS] | math min)
    if $count > 0 {
      if $pos >= $count { $pos = ($count - 1) }
      if $pos < $top { $top = $pos }
      if $pos >= ($top + $h) { $top = ($pos - $h + 1) }
      let maxtop = ([0 ($count - $h)] | math max)
      if $top > $maxtop { $top = $maxtop }
    }
    $drawn = (redraw $rows $states $initial $show_removed $pos $top $drawn)
  }
  # wipe the help line + menu on the way out so the caller starts clean
  print -n (ansi -e $"($drawn + 1)F")
  print -n (ansi -e '0J')
  print -n (ansi -e '?25h')
  $result
}

const HEAD_SHAPES = [shape_external shape_internalcall]
const SUBCMD_SHAPES = [shape_externalarg]

export def "tokens" [line: string]: nothing -> table {
  try {
    ast $line --flatten | collect | reject span
  } catch {
    []
  }
}

def is-flag [tok: record]: nothing -> bool {
  $tok.shape == shape_flag or ($tok.shape == shape_externalarg and ($tok.content | str starts-with "-"))
}

def is-subcmd [tok: record]: nothing -> bool {
  ($tok.shape in $SUBCMD_SHAPES) and ($tok.content =~ '^[a-z][a-z0-9_-]*$')
}

export def "segment" [toks: table]: nothing -> list<int> {
  let is_head = {|tok| $tok.item.shape in $HEAD_SHAPES }
  let starts: list<int> = ($toks | enumerate | where $is_head | get index)
  mut ranges: list<int> = []
  for i in 0..<($starts | length) {
    let start = ($starts | get $i)
    let end = (if ($i + 1 < ($starts | length)) { $starts | get ($i + 1) } else { $toks | length })
    $ranges = ($ranges ++ [$start $end])
  }
  $ranges
}

export def "signature" [seg: table]: nothing -> any {
  if ($seg | is-empty) { return null }
  let head = ($seg | get content | first)
  let rest = ($seg | skip 1 | collect)

  mut subs = []
  for tok in $rest {
    if (is-flag $tok) { break }
    if (is-subcmd $tok) { $subs = ($subs | append $tok.content) } else { break }
  }

  mut flags = []
  for tok in $rest {
    if (is-flag $tok) and ($tok.content not-in $flags) { $flags = ($flags | append $tok.content) }
  }
  let body = ([$head] ++ $subs ++ $flags | str join " ")
  let key = ([$head] ++ $subs ++ ($flags | sort) | str join " ")
  { head: $head, subcommands: $subs, flags: $flags, body: $body, key: $key }
}

export def "line" [raw: string]: nothing -> list {
  let toks = (tokens $raw)
  if ($toks | is-empty) { return [] }
  let ranges = (segment $toks)
  let n = (($ranges | length) / 2 | math floor | into int)
  mut result = []
  for i in 0..<$n {
    let start = ($ranges | get ($i * 2))
    let end = ($ranges | get (($i * 2) + 1))
    let sig = (signature ($toks | skip $start | first ($end - $start)))
    if $sig != null { $result = ($result | append [$sig]) }
  }
  $result
}

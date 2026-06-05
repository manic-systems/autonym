const HEAD_SHAPES = [shape_external shape_internalcall]
const SUBCMD_SHAPES = [shape_externalarg]

export def "tokens" [line: string]: nothing -> list {
  let toks = (try { ast $line --flatten --json | from json } catch { [] })
  if ($toks | is-empty) { return [] }
  $toks | where shape != shape_garbage
}

def is-flag [tok: record]: nothing -> bool {
  $tok.shape == shape_flag or ($tok.shape == shape_externalarg and ($tok.content | str starts-with "-"))
}

def is-subcmd [tok: record]: nothing -> bool {
  ($tok.shape in $SUBCMD_SHAPES) and ($tok.content =~ '^[a-z][a-z0-9_-]*$')
}

export def "segment" [toks: list]: nothing -> list {
  mut segments = []
  mut cur = []
  for tok in $toks {
    if ($tok.shape in $HEAD_SHAPES) {
      if ($cur | is-not-empty) { $segments = ($segments | append [$cur]) }
      $cur = [$tok]
    } else if ($cur | is-not-empty) {
      $cur = ($cur | append $tok)
    }
  }
  if ($cur | is-not-empty) { $segments = ($segments | append [$cur]) }
  $segments
}

export def "signature" [seg: list]: nothing -> any {
  if ($seg | is-empty) { return null }
  let head = ($seg | first | get content)
  let rest = ($seg | skip 1)

  mut subs = []
  for tok in $rest {
    if (is-flag $tok) { break }
    if (is-subcmd $tok) { $subs = ($subs | append $tok.content) } else { break }
  }

  let flags = ($rest | where {|t| is-flag $t } | get content | uniq)
  let body = ([$head] ++ $subs ++ $flags | str join " ")
  let key = ([$head] ++ $subs ++ ($flags | sort) | str join " ")
  { head: $head, subcommands: $subs, flags: $flags, body: $body, key: $key }
}

export def "line" [raw: string]: nothing -> list {
  let toks = (tokens $raw)
  if ($toks | is-empty) { return [] }
  segment $toks | each {|seg| signature $seg } | where {|s| $s != null }
}

# syllable-aware alias candidate generation.
#
# guesses syllable boundaries with the maximal-onset principle
# and interleaves them preferentially with prefix-based acronyms

# syllable onset clusters
const ONSETS3 = [str spl spr scr squ thr shr sch phr]
const ONSETS2 = [
  bl br ch cl cr dr fl fr gl gr ph pl pr sc sh sk sl sm sn sp st sw th tr tw wh wr qu kn gn
]

def is-vowel [c: string, i: int]: nothing -> bool {
  if $c in [a e i o u] { return true }
  # y is a vowel except when it opens the word
  ($c == "y") and ($i > 0)
}

# longest legal onset that is a suffix of a consonant cluster
def onset-len [cluster: list<string>]: nothing -> int {
  let n = ($cluster | length)
  if $n == 0 { return 0 }
  if $n == 1 { return 1 }
  let last3 = ($cluster | last 3 | str join)
  let last2 = ($cluster | last 2 | str join)
  if ($n >= 3) and ($last3 in $ONSETS3) { return 3 }
  if ($last2 in $ONSETS2) { return 2 }
  1
}

# split one word into syllables via the maximal-onset principle
export def syllables [token: string]: nothing -> list<string> {
  let chars = ($token | str downcase | split chars)
  let n = ($chars | length)
  if $n == 0 { return [] }

  let flags = ($chars | enumerate | each {|e| is-vowel $e.item $e.index })
  mut nuclei = []
  mut i = 0
  while $i < $n {
    if ($flags | get $i) {
      mut j = $i
      while ($j + 1 < $n) and ($flags | get ($j + 1)) { $j = $j + 1 }
      $nuclei = ($nuclei | append {start: $i, end: $j})
      $i = $j + 1
    } else {
      $i = $i + 1
    }
  }
  if ($nuclei | is-empty) { return [$token] }

  let m = ($nuclei | length)
  mut bounds = [0]
  for k in 0..<($m - 1) {
    let gap_start = (($nuclei | get $k | get end) + 1)
    let gap_end = (($nuclei | get ($k + 1) | get start) - 1)
    let cluster = (if $gap_end >= $gap_start { $chars | slice $gap_start..$gap_end } else { [] })
    $bounds = ($bounds | append (($gap_end + 1) - (onset-len $cluster)))
  }
  let edges = ($bounds | append $n)
  0..<(($edges | length) - 1) | each {|k|
    $chars | slice ($edges | get $k)..<($edges | get ($k + 1)) | str join
  }
}

def split-words [body: string]: nothing -> list<string> {
  $body | str downcase | split row --regex '[-_ ]+' | where {|w| $w != "" }
}

def syl-initials [word: string]: nothing -> list<string> {
  syllables $word | each {|s| $s | str substring 0..0 }
}

# inclusion order is first, then last, then middles earliest-first
def word-variants [inits: list<string>]: nothing -> list {
  let n = ($inits | length)
  if $n <= 1 { return [ {level: 0, str: ($inits | str join)} ] }

  mut chosen = [0, ($n - 1)]
  mut variants = [ {level: 0, idx: [0]} {level: 1, idx: $chosen} ]
  mut lvl = 2
  for mid in (1..<($n - 1)) {
    $chosen = ($chosen | append $mid)
    $variants = ($variants | append {level: $lvl, idx: $chosen})
    $lvl = $lvl + 1
  }
  $variants | each {|v|
    { level: $v.level, str: ($v.idx | sort | each {|x| $inits | get $x } | str join) }
  }
}

def acronyms [words: list<string>]: nothing -> list<string> {
  let per = ($words | each {|w| word-variants (syl-initials $w) })

  mut combos = [ {parts: [], penalty: 0.0} ]
  for wi in 0..<($per | length) {
    let opts = ($per | get $wi)
    let acc = $combos
    $combos = (
      $acc | each {|c|
        $opts | each {|o|
          {
            parts: ($c.parts | append $o.str)
            penalty: ($c.penalty + ($o.level * (1.0 + ($wi * 0.5))))
          }
        }
      } | flatten
    )
  }
  $combos
  | each {|c|
      let a = ($c.parts | str join)
      { alias: $a, cost: ((($a | str length) * 10.0) + $c.penalty) }
    }
  | sort-by cost
  | get alias
  | uniq
}

def prefix-at [words: list<string>, L: int]: nothing -> any {
  let lens = ($words | each {|w| $w | str length })
  let n = ($words | length)
  if $L < $n { return null }
  if $L > ($lens | math sum) { return null }

  mut q = ($lens | each { 1 })
  mut extra = ($L - $n)
  mut i = 0
  while ($extra > 0) and ($i < $n) {
    let room = (($lens | get $i) - ($q | get $i))
    let add = ([$extra $room] | math min)
    $q = ($q | update $i (($q | get $i) + $add))
    $extra = $extra - $add
    $i = $i + 1
  }
  if $extra > 0 { return null }
  let quota = $q
  $words | enumerate | each {|w| $w.item | str substring 0..(($quota | get $w.index) - 1) } | str join
}

# returns n syllable based rankings, then n prefix, then n+1 etc
export def candidates [
  words: list<string>
  --window: int = 2
  --max-len: int = 8
  --min-len: int = 2
]: nothing -> list<string> {
  if ($words | is-empty) { return [] }
  let acr = (acronyms $words)
  let cap = ([$max_len (($words | each {|w| $w | str length }) | math sum)] | math min)

  mut out = []
  for lo in (seq ($min_len) $window $cap) {
    let hi = ([$cap ($lo + $window - 1)] | math min)
    for L in $lo..$hi {
      $out = ($out | append ($acr | where {|c| ($c | str length) == $L }))
    }
    for L in $lo..$hi {
      let p = (prefix-at $words $L)
      if $p != null { $out = ($out | append $p) }
    }
  }
  $out | uniq | where {|a| ($a | str length) >= $min_len }
}

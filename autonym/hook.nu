use ingest.nu
use analyze.nu
use name.nu
use emit.nu

export def "rescan" [
  --min-count: int = 8
  --min-savings: int = 3
  --top: int
  --source: string
  --out: string
  --limit: int = -1
]: nothing -> record {
  let lines = (ingest read --source $source --limit $limit)
  let prep = (analyze prepare $lines --min-count $min_count)
  let named = (name assign $prep.ranked --min-savings $min_savings --reserved-heads $prep.heads)
  let named = (if $top != null { $named | first ([$top ($named | length)] | math min) } else { $named })
  let summary = (emit write $named --out $out)
  let st = (emit read-state --path $summary.path)
  let enabled_names = ($st.enabled | get name)
  let rejected_names = ($st.rejected | get name)
  let pending = ($named | get name | where {|n| $n not-in $enabled_names and $n not-in $rejected_names })
  let marker = (emit write-pending $pending ($lines | length) (date now))
  { summary: $summary, pending: $marker, named: $named }
}

def notify [p: record]: nothing -> nothing {
  if $p.count > 0 and (not ($p.seen? | default false)) {
    let word = (if $p.count == 1 { "shortcut" } else { "shortcuts" })
    print $"[(ansi yellow)!(ansi reset)] ($p.count) new ($word) to review; check autonym"
  }
}

def maybe-rescan [p: record, grow: int]: nothing -> nothing {
  let hist = (try { open --raw $nu.history-path | lines | length } catch { 0 })
  let last = ($p.last_run? | default null)
  let aged = ($last == null or ((date now) - $last) > 1day)
  let grown = (($hist - ($p.history_len? | default 0)) >= $grow)
  if ($aged or $grown) { job spawn {|| rescan } | ignore }
}

export def "tick" [--grow: int = 200]: nothing -> nothing {
  let p = (emit read-pending)
  notify $p
  maybe-rescan $p $grow
}

export def "snippet" [--every-min: int = 30, --min-prompts: int = 5]: nothing -> string {
  let path = (emit aliases-path)
  let head = [
    "# autonym"
    $"source ($path)"
    $"$env.AUTONYM_EVERY_MIN = ($every_min)"
    $"$env.AUTONYM_MIN_PROMPTS = ($min_prompts)"
    "$env.AUTONYM_TICK = 0"
    "$env.AUTONYM_LAST = (date now)"
  ]
  let body = r#'$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | default [] | append {
  code: "$env.AUTONYM_TICK = ($env.AUTONYM_TICK + 1); if ((((date now) - $env.AUTONYM_LAST) >= ($env.AUTONYM_EVERY_MIN * 1min)) and ($env.AUTONYM_TICK >= $env.AUTONYM_MIN_PROMPTS)) { $env.AUTONYM_TICK = 0; $env.AUTONYM_LAST = (date now); autonym hook tick }"
})'#
  ($head | append $body) | str join "\n"
}

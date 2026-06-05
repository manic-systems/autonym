def detect-format []: nothing -> string {
  try { $env.config.history.file_format } catch { "plaintext" }
}

def unescape-plaintext [line: string]: nothing -> string {
  $line | str replace --all '\n' "\n"
}

def resolve-limit [limit: int]: nothing -> int {
  if $limit >= 0 { $limit } else {
    try { $env.AUTONYM_HISTORY_LIMIT | into int } catch { 1000 }
  }
}

export def "read" [--source: string, --limit: int = -1]: nothing -> list<string> {
  let path = ($source | default $nu.history-path)
  if (not ($path | path exists)) { return [] }

  let fmt = if ($source | is-empty) {
    detect-format
  } else if ($path | str ends-with ".sqlite3") {
    "sqlite"
  } else {
    "plaintext"
  }

  let all = if $fmt == "sqlite" {
    try {
      open $path | query db "select command_line from history order by id"
        | get command_line
        | where {|c| $c != null and ($c | str trim | is-not-empty) }
    } catch { [] }
  } else {
    open --raw $path
      | lines
      | each {|l| unescape-plaintext $l }
      | where {|l| ($l | str trim | is-not-empty) }
  }

  let lim = (resolve-limit $limit)
  if $lim > 0 { $all | last $lim } else { $all }
}
